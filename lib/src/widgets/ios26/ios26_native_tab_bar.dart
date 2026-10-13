import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../adaptive_scaffold.dart';
import '../adaptive_navigation_image.dart';
import 'native_icon_snapshot.dart';

/// Native iOS 26 tab bar using UITabBar platform view
class IOS26NativeTabBar extends StatefulWidget {
  const IOS26NativeTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    this.tint,
    this.unselectedItemTint,
    this.selectedTextColor,
    this.unselectedTextColor,
    this.backgroundColor,
    this.height,
    this.minimizeBehavior = TabBarMinimizeBehavior.automatic,
    this.showNativeView = true,
    this.hidden = false,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Color? tint;
  final Color? unselectedItemTint;
  final Color? selectedTextColor;
  final Color? unselectedTextColor;
  final Color? backgroundColor;
  final double? height;
  final bool showNativeView;

  /// Whether the native tab bar is hidden.
  /// Use this to hide the tab bar when showing modal bottom sheets
  /// to prevent native platform views from bleeding through.
  final bool hidden;

  /// Tab bar minimize behavior (iOS 26+)
  /// Controls how the tab bar minimizes when scrolling
  final TabBarMinimizeBehavior minimizeBehavior;

  @override
  State<IOS26NativeTabBar> createState() => _IOS26NativeTabBarState();
}

class _IOS26NativeTabBarState extends State<IOS26NativeTabBar> {
  MethodChannel? _channel;
  int _iconRevision = 0;
  int? _lastIconRevision;
  final Map<(int, bool), NativeIconPixels> _iconPixels = {};
  final Set<(int, bool)> _dirtyIconPixels = {};
  Timer? _iconSendTimer;
  bool _sendingIconPixels = false;
  int? _nativeIconRevision;

  int? _lastIndex;
  int? _lastSelectedTextColor;
  int? _lastUnselectedTextColor;
  int? _lastTint;
  int? _lastUnselectedTint;
  int? _lastBg;
  bool? _lastIsDark;
  bool? _lastIsRtl;
  double? _intrinsicHeight;
  List<String>? _lastLabels;
  List<String>? _lastSymbols;
  List<String>? _lastSelectedSymbols;
  List<String>? _lastAssetIcons;
  List<String>? _lastSelectedAssetIcons;
  List<String>? _lastFileIcons;
  List<String>? _lastSelectedFileIcons;
  List<String>? _lastNetworkIcons;
  List<String>? _lastSelectedNetworkIcons;
  List<int?>? _lastBadgeCounts;
  List<String?>? _lastBadgeTexts;
  List<int?>? _lastBadgeColors;
  List<int?>? _lastBadgeTextColors;
  TabBarMinimizeBehavior? _lastMinimizeBehavior;
  bool? _lastHidden;

  bool get _isDark =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark;
  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;
  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  @override
  void didUpdateWidget(covariant IOS26NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hidden) {
      _iconSendTimer?.cancel();
      _iconSendTimer = null;
    }
    if (!_sameImageInputs(oldWidget.destinations, widget.destinations)) {
      _iconRevision++;
      _nativeIconRevision = null;
      _dirtyIconPixels.removeWhere(
        (key) =>
            key.$1 >= widget.destinations.length ||
            !widget.destinations[key.$1].requiresFlutterIconFor(key.$2) ||
            (key.$2 && _sharesIcon(key.$1)),
      );
      _iconPixels.removeWhere(
        (key, _) =>
            key.$1 >= widget.destinations.length ||
            !widget.destinations[key.$1].requiresFlutterIconFor(key.$2) ||
            (key.$2 && _sharesIcon(key.$1)),
      );
      for (var i = 0; i < widget.destinations.length; i++) {
        if (_sharesIcon(i) &&
            (i >= oldWidget.destinations.length ||
                !_sharesDestinationIcon(oldWidget.destinations[i])) &&
            _iconPixels.containsKey((i, false))) {
          _dirtyIconPixels.add((i, false));
        }
      }
    }
    _syncPropsToNativeIfNeeded();
    _queueIconPixels();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncDirectionalityIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _iconSendTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  int _colorToARGB(Color color) {
    // Resolve CupertinoDynamicColor if needed
    Color resolvedColor = color;
    if (color is CupertinoDynamicColor) {
      // Resolve based on current brightness
      final brightness = CupertinoTheme.brightnessOf(context);
      resolvedColor = brightness == Brightness.dark
          ? color.darkColor
          : color.color;
    }

    return ((resolvedColor.a * 255.0).round() & 0xff) << 24 |
        ((resolvedColor.r * 255.0).round() & 0xff) << 16 |
        ((resolvedColor.g * 255.0).round() & 0xff) << 8 |
        ((resolvedColor.b * 255.0).round() & 0xff);
  }

  /// Extract SF Symbol name from an icon value.
  /// Returns empty string for non-SF-Symbol icons (asset paths, IconData, widgets).
  String _extractSymbol(Object? icon) {
    if (icon is String && !icon.contains('/')) return icon;
    return '';
  }

  /// Extract asset path from an icon value.
  /// Supports AssetImage and string paths containing '/'.
  /// Returns empty string for SF Symbols or other icon types.
  String _extractAssetPath(Object? icon) {
    if (icon is AssetImage) return icon.assetName;
    if (icon is String && icon.contains('/')) return icon;
    return '';
  }

  String _extractFilePath(Object? icon) {
    if (icon is FileImage) return icon.file.path;
    return '';
  }

  String _extractNetworkUrl(Object? icon) {
    if (icon is NetworkImage) return icon.url;
    return '';
  }

  List<String> _mapIcons(String Function(Object?) extract, bool selected) =>
      widget.destinations
          .map(
            (d) => d.requiresFlutterIconFor(selected)
                ? ''
                : extract(selected ? d.selectedIcon ?? d.icon : d.icon),
          )
          .toList();

  List<String> _mapSymbols() => _mapIcons(_extractSymbol, false);
  List<String> _mapSelectedSymbols() => _mapIcons(_extractSymbol, true);
  List<String> _mapAssetIcons() => _mapIcons(_extractAssetPath, false);
  List<String> _mapSelectedAssetIcons() => _mapIcons(_extractAssetPath, true);
  List<String> _mapFileIcons() => _mapIcons(_extractFilePath, false);
  List<String> _mapSelectedFileIcons() => _mapIcons(_extractFilePath, true);
  List<String> _mapNetworkIcons() => _mapIcons(_extractNetworkUrl, false);
  List<String> _mapSelectedNetworkIcons() =>
      _mapIcons(_extractNetworkUrl, true);

  bool _sameImageInputs(
    List<AdaptiveNavigationDestination> a,
    List<AdaptiveNavigationDestination> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].icon != b[i].icon || a[i].selectedIcon != b[i].selectedIcon) {
        return false;
      }
    }
    return true;
  }

  // Ordinary Flutter icons use UIKit tint; image/widget pixels stay original.
  bool _usesNativeTemplate(int index, bool selected) {
    final d = widget.destinations[index];
    final icon = selected ? d.selectedIcon ?? d.icon : d.icon;
    return icon is IconData || (icon is Icon && icon.color == null);
  }

  bool _sharesDestinationIcon(AdaptiveNavigationDestination d) =>
      d.requiresFlutterIconFor(false) &&
      d.requiresFlutterIconFor(true) &&
      (d.selectedIcon == null || d.selectedIcon == d.icon);

  bool _sharesIcon(int index) =>
      _sharesDestinationIcon(widget.destinations[index]);

  List<List<bool>> get _flutterIconStates => [
    for (final d in widget.destinations)
      [d.requiresFlutterIconFor(false), d.requiresFlutterIconFor(true)],
  ];

  void _queueIconPixels() {
    if (widget.hidden ||
        _dirtyIconPixels.isEmpty ||
        _sendingIconPixels ||
        _iconSendTimer != null ||
        _nativeIconRevision != _iconRevision) {
      return;
    }
    // Coalesce normal/selected and multiple icon changes into one small batch.
    _iconSendTimer = Timer(const Duration(milliseconds: 16), () {
      _iconSendTimer = null;
      _sendIconPixels();
    });
  }

  Future<void> _sendIconPixels() async {
    final ch = _channel;
    if (widget.hidden ||
        ch == null ||
        _dirtyIconPixels.isEmpty ||
        _sendingIconPixels ||
        _nativeIconRevision != _iconRevision) {
      return;
    }
    final revision = _iconRevision;
    final keys = _dirtyIconPixels.toList();
    _dirtyIconPixels.removeAll(keys);
    _sendingIconPixels = true;
    try {
      await ch.invokeMethod('setFlutterIcons', {
        'revision': revision,
        'icons': [
          for (final key in keys)
            if (_iconPixels[key] != null)
              {
                'index': key.$1,
                'selected': key.$2,
                'template': _usesNativeTemplate(key.$1, key.$2),
                'both': !key.$2 && _sharesIcon(key.$1),
                'bytes': _iconPixels[key]!.rgba,
                'width': _iconPixels[key]!.width,
                'height': _iconPixels[key]!.height,
                'scale': _iconPixels[key]!.scale,
              },
        ],
      });
    } on PlatformException {
      // Cached pixels are replayed when a new platform view is created.
    } on MissingPluginException {
      // The view went away before its channel received the update.
    } finally {
      _sendingIconPixels = false;
      if (mounted) {
        if (revision != _iconRevision || ch != _channel) {
          // The receiver may have rejected this batch after a revision/view
          // change. Resend current cached pixels, not the stale payload.
          _dirtyIconPixels.addAll(keys.where(_iconPixels.containsKey));
        }
        _queueIconPixels();
      }
    }
  }

  Widget _withIconSnapshots(Widget nativeBar) {
    final revision = _iconRevision;
    final snapshots = <Widget>[];
    if (!widget.hidden) {
      for (var i = 0; i < widget.destinations.length; i++) {
        final destination = widget.destinations[i];
        for (final selected in [false, true]) {
          if (!destination.requiresFlutterIconFor(selected) ||
              (selected && _sharesIcon(i))) {
            continue;
          }
          final icon = selected
              ? destination.selectedIcon ?? destination.icon
              : destination.icon;
          final size = icon is AdaptiveNavigationImage ? icon.size : 26.0;
          snapshots.add(
            Positioned(
              left: 0,
              top: 0,
              width: size,
              height: size,
              child: NativeIconSnapshot(
                key: ValueKey((i, selected)),
                onPixels: (pixels) {
                  if (!mounted || revision != _iconRevision) return;
                  final cached = _iconPixels[(i, selected)];
                  if (cached != null &&
                      cached.width == pixels.width &&
                      cached.height == pixels.height &&
                      cached.scale == pixels.scale &&
                      listEquals(cached.rgba, pixels.rgba)) {
                    return;
                  }
                  _iconPixels[(i, selected)] = pixels;
                  _dirtyIconPixels.add((i, selected));
                  _queueIconPixels();
                },
                child: destination.buildIcon(selected: selected),
              ),
            ),
          );
        }
      }
    }
    return Stack(children: [nativeBar, ...snapshots]);
  }

  // Native badge styling: badge content + colors mapped to the
  // native side (UITabBarItem.badgeValue / .badgeColor / badge text attrs).
  List<String?> _mapBadgeTexts() =>
      widget.destinations.map((e) => e.badgeText).toList();

  List<int?> _mapBadgeColors() => widget.destinations
      .map((e) => e.badgeColor != null ? _colorToARGB(e.badgeColor!) : null)
      .toList();

  List<int?> _mapBadgeTextColors() => widget.destinations
      .map(
        (e) =>
            e.badgeTextColor != null ? _colorToARGB(e.badgeTextColor!) : null,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final labels = widget.destinations.map((e) => e.label).toList();
      final symbols = _mapSymbols();
      final selectedSymbols = _mapSelectedSymbols();
      final assetIcons = _mapAssetIcons();
      final selectedAssetIcons = _mapSelectedAssetIcons();
      final fileIcons = _mapFileIcons();
      final selectedFileIcons = _mapSelectedFileIcons();
      final networkIcons = _mapNetworkIcons();
      final selectedNetworkIcons = _mapSelectedNetworkIcons();

      final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
      final badgeCounts = widget.destinations.map((e) => e.badgeCount).toList();
      final badgeTexts = _mapBadgeTexts();
      final badgeColors = _mapBadgeColors();
      final badgeTextColors = _mapBadgeTextColors();
      final spacerFlags = widget.destinations
          .map((e) => e.addSpacerAfter)
          .toList();

      final creationParams = <String, dynamic>{
        'iconRevision': _iconRevision,
        'flutterIconStates': _flutterIconStates,
        'selectedTextColor': widget.selectedTextColor == null
            ? null
            : _colorToARGB(widget.selectedTextColor!),
        'unselectedTextColor': widget.unselectedTextColor == null
            ? null
            : _colorToARGB(widget.unselectedTextColor!),
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': badgeTexts,
        'badgeColors': badgeColors,
        'badgeTextColors': badgeTextColors,
        'spacerFlags': spacerFlags,
        'selectedIndex': widget.selectedIndex,
        'isDark': _isDark,
        'isRtl': _isRtl,
        'minimizeBehavior': widget.minimizeBehavior.index,
        if (_effectiveTint != null) 'tint': _colorToARGB(_effectiveTint!),
        if (widget.unselectedItemTint != null)
          'unselectedItemTint': _colorToARGB(widget.unselectedItemTint!),
        if (widget.backgroundColor != null)
          'backgroundColor': _colorToARGB(widget.backgroundColor!),
      };

      final platformView = widget.showNativeView
          ? UiKitView(
              viewType: 'adaptive_platform_ui/ios26_tab_bar',
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onCreated,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
              },
            )
          : const SizedBox.shrink();

      final h = widget.height ?? _intrinsicHeight ?? 50.0;
      return SizedBox(
        height: h,
        child: widget.showNativeView
            ? _withIconSnapshots(platformView)
            : platformView,
      );
    }

    // Flutter resolves custom providers so caches and placeholders are honored.
    if (!widget.showNativeView || widget.hidden) {
      return SizedBox(height: widget.height ?? 50);
    }
    if (widget.destinations.length < 2) {
      return SizedBox(
        height: widget.height ?? 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < widget.destinations.length; i++)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => widget.onTap(i),
                child: widget.destinations[i].buildIcon(
                  selected: i == widget.selectedIndex,
                ),
              ),
          ],
        ),
      );
    }
    return CupertinoTabBar(
      currentIndex: widget.selectedIndex,
      onTap: widget.onTap,
      height: widget.height ?? 50,
      activeColor: widget.tint,
      inactiveColor: widget.unselectedItemTint ?? CupertinoColors.inactiveGray,
      backgroundColor: widget.backgroundColor,
      items: [
        for (final d in widget.destinations)
          d.buildCupertinoItem(
            context,
            selectedColor: _effectiveTint,
            selectedTextColor: widget.selectedTextColor,
            unselectedTextColor: widget.unselectedTextColor,
            unselectedColor: widget.unselectedItemTint,
          ),
      ],
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('adaptive_platform_ui/ios26_tab_bar_$id');
    _channel = ch;
    _nativeIconRevision = null;
    ch.setMethodCallHandler(_onMethodCall);
    _lastIndex = null;
    _lastTint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    _lastUnselectedTint = widget.unselectedItemTint != null
        ? _colorToARGB(widget.unselectedItemTint!)
        : null;
    _lastBg = widget.backgroundColor != null
        ? _colorToARGB(widget.backgroundColor!)
        : null;
    _lastIsDark = _isDark;
    _lastIsRtl = _isRtl;
    _lastMinimizeBehavior = widget.minimizeBehavior;
    _requestIntrinsicSize();
    _cacheItems();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _channel != ch) return;
      _pushInitialStateToNative(ch);
    });
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      if (idx != null) {
        widget.onTap(idx);
        _lastIndex = idx;
      }
    }
    return null;
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    final idx = widget.selectedIndex;
    final tint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    final unselectedTint = widget.unselectedItemTint != null
        ? _colorToARGB(widget.unselectedItemTint!)
        : null;
    final bg = widget.backgroundColor != null
        ? _colorToARGB(widget.backgroundColor!)
        : null;

    if (_lastIndex != idx) {
      await ch.invokeMethod('setSelectedIndex', {'index': idx});
      _lastIndex = idx;
    }

    final style = <String, dynamic>{};
    final selectedTextColor = widget.selectedTextColor == null
        ? null
        : _colorToARGB(widget.selectedTextColor!);
    final unselectedTextColor = widget.unselectedTextColor == null
        ? null
        : _colorToARGB(widget.unselectedTextColor!);
    if (_lastSelectedTextColor != selectedTextColor) {
      style['selectedTextColor'] = selectedTextColor;
      _lastSelectedTextColor = selectedTextColor;
    }
    if (_lastUnselectedTextColor != unselectedTextColor) {
      style['unselectedTextColor'] = unselectedTextColor;
      _lastUnselectedTextColor = unselectedTextColor;
    }

    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastUnselectedTint != unselectedTint && unselectedTint != null) {
      style['unselectedItemTint'] = unselectedTint;
      _lastUnselectedTint = unselectedTint;
    }
    if (_lastBg != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBg = bg;
    }
    if (style.isNotEmpty) {
      await ch.invokeMethod('setStyle', style);
    }

    // Items update (for hot reload or dynamic changes)
    final labels = widget.destinations.map((e) => e.label).toList();
    final symbols = _mapSymbols();
    final selectedSymbols = _mapSelectedSymbols();
    final assetIcons = _mapAssetIcons();
    final selectedAssetIcons = _mapSelectedAssetIcons();
    final fileIcons = _mapFileIcons();
    final selectedFileIcons = _mapSelectedFileIcons();
    final networkIcons = _mapNetworkIcons();
    final selectedNetworkIcons = _mapSelectedNetworkIcons();
    final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
    final badgeCounts = widget.destinations.map((e) => e.badgeCount).toList();

    if (_lastIconRevision != _iconRevision ||
        _lastLabels?.join('|') != labels.join('|') ||
        _lastSymbols?.join('|') != symbols.join('|') ||
        _lastSelectedSymbols?.join('|') != selectedSymbols.join('|') ||
        _lastAssetIcons?.join('|') != assetIcons.join('|') ||
        _lastSelectedAssetIcons?.join('|') != selectedAssetIcons.join('|') ||
        _lastFileIcons?.join('|') != fileIcons.join('|') ||
        _lastSelectedFileIcons?.join('|') != selectedFileIcons.join('|') ||
        _lastNetworkIcons?.join('|') != networkIcons.join('|') ||
        _lastSelectedNetworkIcons?.join('|') !=
            selectedNetworkIcons.join('|')) {
      final revision = _iconRevision;
      await ch.invokeMethod('setItems', {
        'iconRevision': revision,
        'flutterIconStates': _flutterIconStates,
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': _mapBadgeTexts(),
        'badgeColors': _mapBadgeColors(),
        'badgeTextColors': _mapBadgeTextColors(),
        'selectedIndex': widget.selectedIndex,
      });
      _lastIconRevision = revision;
      if (mounted && _channel == ch && _iconRevision == revision) {
        _nativeIconRevision = revision;
        _queueIconPixels();
      }
      _lastLabels = labels;
      _lastSymbols = symbols;
      _lastSelectedSymbols = selectedSymbols;
      _lastAssetIcons = assetIcons;
      _lastSelectedAssetIcons = selectedAssetIcons;
      _lastFileIcons = fileIcons;
      _lastSelectedFileIcons = selectedFileIcons;
      _lastNetworkIcons = networkIcons;
      _lastSelectedNetworkIcons = selectedNetworkIcons;
      _requestIntrinsicSize();
    }

    // Badge update (count + text + colors). Re-push when any badge input changes.
    final currentBadgeCounts = widget.destinations
        .map((e) => e.badgeCount)
        .toList();
    final currentBadgeTexts = _mapBadgeTexts();
    final currentBadgeColors = _mapBadgeColors();
    final currentBadgeTextColors = _mapBadgeTextColors();
    if (_lastBadgeCounts?.join('|') != currentBadgeCounts.join('|') ||
        _lastBadgeTexts?.join('|') != currentBadgeTexts.join('|') ||
        _lastBadgeColors?.join('|') != currentBadgeColors.join('|') ||
        _lastBadgeTextColors?.join('|') != currentBadgeTextColors.join('|')) {
      await ch.invokeMethod('setBadgeCounts', {
        'badgeCounts': currentBadgeCounts,
        'badgeTexts': currentBadgeTexts,
        'badgeColors': currentBadgeColors,
        'badgeTextColors': currentBadgeTextColors,
      });
      _lastBadgeCounts = currentBadgeCounts;
      _lastBadgeTexts = currentBadgeTexts;
      _lastBadgeColors = currentBadgeColors;
      _lastBadgeTextColors = currentBadgeTextColors;
    }

    // Minimize behavior update
    if (_lastMinimizeBehavior != widget.minimizeBehavior) {
      await ch.invokeMethod('setMinimizeBehavior', {
        'behavior': widget.minimizeBehavior.index,
      });
      _lastMinimizeBehavior = widget.minimizeBehavior;
    }

    // Hidden state update
    await _syncHiddenIfNeeded();
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      await ch.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }
  }

  Future<void> _syncDirectionalityIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isRtl = _isRtl;
    if (_lastIsRtl != isRtl) {
      await ch.invokeMethod('setDirectionality', {'isRtl': isRtl});
      _lastIsRtl = isRtl;
    }
  }

  void _cacheItems() {
    _lastIconRevision = _iconRevision;
    _lastLabels = widget.destinations.map((e) => e.label).toList();
    _lastSymbols = _mapSymbols();
    _lastSelectedSymbols = _mapSelectedSymbols();
    _lastAssetIcons = _mapAssetIcons();
    _lastSelectedAssetIcons = _mapSelectedAssetIcons();
    _lastFileIcons = _mapFileIcons();
    _lastSelectedFileIcons = _mapSelectedFileIcons();
    _lastNetworkIcons = _mapNetworkIcons();
    _lastSelectedNetworkIcons = _mapSelectedNetworkIcons();
    _lastBadgeCounts = widget.destinations.map((e) => e.badgeCount).toList();
    _lastBadgeTexts = _mapBadgeTexts();
    _lastBadgeColors = _mapBadgeColors();
    _lastBadgeTextColors = _mapBadgeTextColors();
  }

  Future<void> _syncHiddenIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final hidden = widget.hidden;
    if (_lastHidden == hidden) return;
    await ch.invokeMethod('setHidden', {'hidden': hidden});
    _lastHidden = hidden;
  }

  Future<void> _requestIntrinsicSize() async {
    if (widget.height != null) return;
    final ch = _channel;
    if (ch == null) return;
    try {
      final size = await ch.invokeMethod<Map>('getIntrinsicSize');
      final h = (size?['height'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        if (h != null && h > 0) _intrinsicHeight = h;
      });
    } catch (_) {}
  }

  Future<void> _pushInitialStateToNative(MethodChannel ch) async {
    final labels = widget.destinations.map((e) => e.label).toList();
    final symbols = _mapSymbols();
    final selectedSymbols = _mapSelectedSymbols();
    final assetIcons = _mapAssetIcons();
    final selectedAssetIcons = _mapSelectedAssetIcons();
    final fileIcons = _mapFileIcons();
    final selectedFileIcons = _mapSelectedFileIcons();
    final networkIcons = _mapNetworkIcons();
    final selectedNetworkIcons = _mapSelectedNetworkIcons();
    final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
    final badgeCounts = widget.destinations.map((e) => e.badgeCount).toList();

    try {
      final revision = _iconRevision;
      await ch.invokeMethod('setItems', {
        'iconRevision': revision,
        'flutterIconStates': _flutterIconStates,
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': _mapBadgeTexts(),
        'badgeColors': _mapBadgeColors(),
        'badgeTextColors': _mapBadgeTextColors(),
        'selectedIndex': widget.selectedIndex,
      });

      if (mounted && _channel == ch && _iconRevision == revision) {
        _nativeIconRevision = revision;
        _dirtyIconPixels.addAll(_iconPixels.keys);
        _queueIconPixels();
      }
      final style = <String, dynamic>{};
      final selectedTextColor = widget.selectedTextColor == null
          ? null
          : _colorToARGB(widget.selectedTextColor!);
      final unselectedTextColor = widget.unselectedTextColor == null
          ? null
          : _colorToARGB(widget.unselectedTextColor!);
      if (_lastSelectedTextColor != selectedTextColor) {
        style['selectedTextColor'] = selectedTextColor;
        _lastSelectedTextColor = selectedTextColor;
      }
      if (_lastUnselectedTextColor != unselectedTextColor) {
        style['unselectedTextColor'] = unselectedTextColor;
        _lastUnselectedTextColor = unselectedTextColor;
      }

      if (_effectiveTint != null) {
        style['tint'] = _colorToARGB(_effectiveTint!);
      }
      if (widget.unselectedItemTint != null) {
        style['unselectedItemTint'] = _colorToARGB(widget.unselectedItemTint!);
      }
      if (widget.backgroundColor != null) {
        style['backgroundColor'] = _colorToARGB(widget.backgroundColor!);
      }
      if (style.isNotEmpty) {
        await ch.invokeMethod('setStyle', style);
      }

      await ch.invokeMethod('setSelectedIndex', {
        'index': widget.selectedIndex,
      });
      _lastIndex = widget.selectedIndex;
      await _requestIntrinsicSize();
    } catch (_) {}
  }
}
