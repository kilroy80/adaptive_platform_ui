import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_icon_snapshot.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> encodeFrame(WidgetTester tester) async {
  // GPU readback completes outside FakeAsync; advance both the throttle and
  // batching timers after delivering the real raster result.
  for (var i = 0; i < 2; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  }
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('snapshot produces pixels while Flutter copy stays transparent', (
    tester,
  ) async {
    final output = <NativeIconPixels>[];
    final sceneKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: sceneKey,
            child: SizedBox(
              width: 26,
              height: 26,
              child: NativeIconSnapshot(
                onPixels: output.add,
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
    await encodeFrame(tester);
    expect(output, hasLength(1));
    await tester.runAsync(() async {
      expect(output.single.rgba[0], 244);
      expect(output.single.rgba[3], 255);
      expect(
        output.single.rgba.length,
        output.single.width * output.single.height * 4,
      );
      final scene =
          await (sceneKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final scenePixels = await scene.toByteData();
      expect(scenePixels!.getUint8(3), 0);
      scene.dispose();
    });
    await encodeFrame(tester);
    expect(output, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unrelated frames and ancestor movement do not capture static icons',
    (tester) async {
      final offset = ValueNotifier<double>(0);
      var captures = 0;
      final snapshot = NativeIconSnapshot(
        onCapture: () => captures++,
        onPixels: (_) {},
        child: const ColoredBox(color: Colors.red),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: offset,
              child: snapshot,
              builder: (_, value, child) => Transform.translate(
                offset: Offset(value, 0),
                child: SizedBox(width: 26, height: 26, child: child),
              ),
            ),
          ),
        ),
      );
      await encodeFrame(tester);
      expect(captures, 1);
      for (var i = 0; i < 60; i++) {
        offset.value = i.toDouble();
        await tester.pump(const Duration(milliseconds: 16));
      }
      await encodeFrame(tester);
      expect(captures, 1, reason: 'No GPU readback for unrelated frames');
      await tester.pumpWidget(const SizedBox.shrink());
      offset.dispose();
    },
  );

  testWidgets('identical repaint skips pixel upload; nested fade is captured', (
    tester,
  ) async {
    final tick = ValueNotifier<int>(0);
    final opacity = AnimationController(vsync: tester, value: 1);
    final output = <NativeIconPixels>[];
    var captures = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: NativeIconSnapshot(
              onPixels: output.add,
              onCapture: () => captures++,
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: opacity,
                  child: ValueListenableBuilder<int>(
                    valueListenable: tick,
                    builder: (_, value, _) =>
                        CustomPaint(painter: SolidPainter(value)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await encodeFrame(tester);
    expect(captures, 1);
    tick.value++;
    await encodeFrame(tester);
    expect(captures, 2);
    expect(output, hasLength(1), reason: 'Identical RGBA does not upload');
    opacity.value = 0.5;
    await encodeFrame(tester);
    expect(
      captures,
      3,
      reason: 'Nested composited opacity changes are observed',
    );
    expect(output, hasLength(2));
    await tester.runAsync(() async {
      expect(output.last.rgba[3], closeTo(128, 1));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    opacity.dispose();
    tick.dispose();
  });

  testWidgets(
    'iOS custom icons keep UIKit bar and send both states over channel',
    (tester) async {
      final calls = <MethodCall>[];
      Map<Object?, Object?>? params;
      MethodChannel? iconChannel;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final args = call.arguments as Map;
          params =
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(args['params'] as Uint8List),
                  )
                  as Map;
          iconChannel = MethodChannel(
            'adaptive_platform_ui/ios26_tab_bar_${args['id']}',
          );
          messenger.setMockMethodCallHandler(iconChannel!, (call) async {
            calls.add(call);
            if (call.method == 'getIntrinsicSize') return {'height': 50.0};
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (iconChannel != null) {
          messenger.setMockMethodCallHandler(iconChannel!, null);
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: IOS26NativeTabBar(
              destinations: const [
                AdaptiveNavigationDestination(
                  applyImageTint: false,
                  icon: ColoredBox(color: Colors.red),
                  selectedIcon: ColoredBox(color: Colors.blue),
                  label: 'Profile',
                  badgeText: 'NEW',
                ),
                AdaptiveNavigationDestination(
                  applyImageTint: false,
                  icon: 'magnifyingglass',
                  label: 'Search',
                  isSearch: true,
                ),
              ],
              selectedIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await encodeFrame(tester);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.byType(CupertinoTabBar), findsNothing);
      expect(params!['searchFlags'], [false, true]);
      expect(params!['badgeTexts'], ['NEW', null]);
      final images = calls.where((c) => c.method == 'setFlutterIcons').toList();
      expect(images, isNotEmpty);
      final icons = (images.last.arguments as Map)['icons'] as List;
      expect(
        icons.map((i) => (i as Map)['selected']),
        containsAll([false, true]),
      );
      expect(icons.every((i) => (i as Map)['bytes'] is Uint8List), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: IOS26NativeTabBar(
              destinations: const [
                AdaptiveNavigationDestination(
                  applyImageTint: false,
                  icon: ColoredBox(color: Colors.green),
                  selectedIcon: 'heart',
                  label: 'Profile',
                ),
                AdaptiveNavigationDestination(
                  applyImageTint: false,
                  icon: 'magnifyingglass',
                  label: 'Search',
                  isSearch: true,
                ),
              ],
              selectedIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await encodeFrame(tester);
      await encodeFrame(tester);
      final items =
          calls.lastWhere((c) => c.method == 'setItems').arguments as Map;
      expect(items['iconRevision'], 1);
      expect((items['selectedSfSymbols'] as List).first, 'heart');
      final replacement =
          calls.lastWhere((c) => c.method == 'setFlutterIcons').arguments
              as Map;
      expect(replacement['revision'], 1);
      final replacementIcons = replacement['icons'] as List;
      expect(replacementIcons, hasLength(1));
      expect((replacementIcons.single as Map)['selected'], isFalse);
      expect(find.byType(UiKitView), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
  testWidgets(
    'identical icon states share rendering and only changed icons are sent',
    (tester) async {
      final harness = NativeBarHarness();
      harness.install();
      addTearDown(harness.dispose);
      const initial = [
        AdaptiveNavigationDestination(
          applyImageTint: false,
          icon: ColoredBox(color: Colors.red),
          label: 'One',
        ),
        AdaptiveNavigationDestination(
          applyImageTint: false,
          icon: ColoredBox(color: Colors.blue),
          label: 'Two',
        ),
      ];
      await tester.pumpWidget(harness.build(initial));
      await tester.pump();
      await encodeFrame(tester);
      await encodeFrame(tester);
      expect(find.byType(NativeIconSnapshot), findsNWidgets(2));
      final initialUpdates = harness.iconUpdates;
      expect(
        initialUpdates,
        hasLength(1),
        reason: 'Coalesce both icons into one batch',
      );
      final initialIcons = initialUpdates.single['icons'] as List;
      expect(initialIcons, hasLength(2));
      expect(initialIcons.every((i) => (i as Map)['both'] == true), isTrue);
      final oldBar = tester.widget<UiKitView>(find.byType(UiKitView));
      const changed = [
        AdaptiveNavigationDestination(
          applyImageTint: false,
          icon: ColoredBox(color: Colors.green),
          label: 'One',
        ),
        AdaptiveNavigationDestination(
          applyImageTint: false,
          icon: ColoredBox(color: Colors.blue),
          label: 'Two',
        ),
      ];
      await tester.pumpWidget(harness.build(changed));
      await tester.pump();
      await encodeFrame(tester);
      await encodeFrame(tester);
      final update = harness.iconUpdates.last;
      expect(update['revision'], 1);
      final changedIcons = update['icons'] as List;
      expect(
        changedIcons,
        hasLength(1),
        reason: 'Do not resend unchanged tab Two',
      );
      expect((changedIcons.single as Map)['index'], 0);
      expect((changedIcons.single as Map)['both'], isTrue);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(
        tester.widget<UiKitView>(find.byType(UiKitView)).viewType,
        oldBar.viewType,
      );
      final sent = harness.iconUpdates.length;
      await tester.pumpWidget(harness.build(changed, selectedIndex: 1));
      await encodeFrame(tester);
      await encodeFrame(tester);
      expect(
        harness.iconUpdates,
        hasLength(sent),
        reason: 'Selection requires no pixel upload',
      );
      await tester.pumpWidget(harness.build(changed, hidden: true));
      await encodeFrame(tester);
      expect(find.byType(NativeIconSnapshot), findsNothing);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(
        harness.creations,
        1,
        reason: 'Hiding preserves the native glass view',
      );
      expect(harness.iconUpdates, hasLength(sent));
      await tester.pumpWidget(harness.build(changed));
      await encodeFrame(tester);
      expect(harness.creations, 1);
      expect(
        harness.iconUpdates,
        hasLength(sent),
        reason: 'Reuse identical cached pixels after showing',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
  testWidgets('pending icon updates survive a revision change', (tester) async {
    final harness = NativeBarHarness();
    harness.install();
    addTearDown(harness.dispose);
    const initial = [
      AdaptiveNavigationDestination(
        applyImageTint: false,
        icon: ColoredBox(color: Colors.red),
        label: 'One',
      ),
      AdaptiveNavigationDestination(
        applyImageTint: false,
        icon: ColoredBox(color: Colors.blue),
        label: 'Two',
      ),
    ];
    await tester.pumpWidget(harness.build(initial));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(
      harness.iconUpdates,
      isEmpty,
      reason: 'Raster results are waiting for the batch timer',
    );
    await tester.pumpWidget(
      harness.build(const [
        AdaptiveNavigationDestination(
          applyImageTint: false,
          icon: ColoredBox(color: Colors.green),
          label: 'One',
        ),
        AdaptiveNavigationDestination(
          applyImageTint: false,
          icon: ColoredBox(color: Colors.blue),
          label: 'Two',
        ),
      ]),
    );
    await encodeFrame(tester);
    await encodeFrame(tester);
    final sent = harness.iconUpdates
        .where((u) => u['revision'] == 1)
        .expand((u) => u['icons'] as List)
        .cast<Map>();
    expect(
      sent.any((icon) => icon['index'] == 1),
      isTrue,
      reason: 'Unchanged icon Two must not lose its first pending upload',
    );
    expect(sent.any((icon) => icon['index'] == 0), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));
}

class SolidPainter extends CustomPainter {
  SolidPainter(this.tick);
  final int tick;
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.red);
  @override
  bool shouldRepaint(SolidPainter oldDelegate) => oldDelegate.tick != tick;
}

class NativeBarHarness {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  MethodChannel? channel;
  int creations = 0;

  void install() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        creations++;
        channel = MethodChannel(
          'adaptive_platform_ui/ios26_tab_bar_${(call.arguments as Map)['id']}',
        );
        messenger.setMockMethodCallHandler(channel!, (call) async {
          calls.add(call);
          if (call.method == 'getIntrinsicSize') return {'height': 50.0};
          return null;
        });
      }
      return null;
    });
  }

  void dispose() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    if (channel != null) {
      messenger.setMockMethodCallHandler(channel!, null);
    }
  }

  List<Map> get iconUpdates => calls
      .where((c) => c.method == 'setFlutterIcons')
      .map((c) => c.arguments as Map)
      .toList();
  Widget build(
    List<AdaptiveNavigationDestination> destinations, {
    int selectedIndex = 0,
    bool hidden = false,
  }) => MaterialApp(
    home: Scaffold(
      bottomNavigationBar: IOS26NativeTabBar(
        destinations: destinations,
        hidden: hidden,
        selectedIndex: selectedIndex,
        onTap: (_) {},
      ),
    ),
  );
}
