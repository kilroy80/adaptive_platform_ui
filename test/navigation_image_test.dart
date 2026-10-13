import 'dart:async';
import 'dart:ui' as ui;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_glass_capsule.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DeferredImage extends ImageProvider<DeferredImage> {
  final completer = Completer<ImageInfo>();
  @override
  Future<DeferredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    DeferredImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(completer.future);
}

// Keep the NetworkImage rendering path while controlling decoding in tests.
class DeferredNetworkImage extends ImageProvider<NetworkImage>
    implements NetworkImage {
  @override
  String get url => 'https://example.com/icon.png';
  @override
  double get scale => 1;
  @override
  Map<String, String>? get headers => null;
  @override
  WebHtmlElementStrategy get webHtmlElementStrategy =>
      WebHtmlElementStrategy.never;
  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  final completer = Completer<ImageInfo>();
  @override
  ImageStreamCompleter loadImage(
    NetworkImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(completer.future);
}

void main() {
  testWidgets('Android image tint follows item colors only when enabled', (
    tester,
  ) async {
    for (final provider in [DeferredImage(), DeferredNetworkImage()]) {
      for (final enabled in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: AdaptiveScaffold(
              body: const SizedBox(),
              bottomNavigationBar: AdaptiveBottomNavigationBar(
                selectedIndex: 0,
                onTap: (_) {},
                selectedItemColor: Colors.red,
                unselectedItemColor: Colors.blue,
                items: [
                  AdaptiveNavigationDestination(
                    icon: provider,
                    label: 'Profile',
                    applyImageTint: enabled,
                    iconPlaceholder: const SizedBox(),
                  ),
                  AdaptiveNavigationDestination(
                    icon: provider,
                    label: 'Other',
                    applyImageTint: enabled,
                    iconPlaceholder: const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        );
        final filters = tester.widgetList<ColorFiltered>(
          find.byType(ColorFiltered),
        );
        if (enabled) {
          expect(
            filters.map((w) => w.colorFilter),
            containsAll([
              const ColorFilter.mode(Colors.red, BlendMode.srcIn),
              const ColorFilter.mode(Colors.blue, BlendMode.srcIn),
            ]),
          );
        } else {
          expect(filters, isEmpty);
        }
      }
    }
  });

  testWidgets('image widgets can opt into inherited tint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconTheme(
          data: const IconThemeData(color: Colors.green),
          child: const AdaptiveNavigationDestination(
            icon: SizedBox(width: 26, height: 26),
            label: 'Image',
            applyImageTint: true,
          ).buildIcon(),
        ),
      ),
    );
    expect(
      tester.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter,
      const ColorFilter.mode(Colors.green, BlendMode.srcIn),
    );
  });

  testWidgets('placeholder is replaced by a decoded custom provider image', (
    tester,
  ) async {
    final provider = DeferredImage();
    final destination = AdaptiveNavigationDestination(
      icon: provider,
      label: 'Profile',
      iconPlaceholder: const Text('Loading'),
    );
    await tester.pumpWidget(MaterialApp(home: destination.buildIcon()));
    expect(find.text('Loading'), findsOneWidget);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    provider.completer.complete(ImageInfo(image: await picture.toImage(1, 1)));
    picture.dispose();
    await tester.pump();
    await tester.pump();
    expect(find.text('Loading'), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('failed image uses custom error widget', (tester) async {
    final provider = DeferredImage();
    final destination = AdaptiveNavigationDestination(
      icon: provider,
      label: 'Profile',
      iconPlaceholder: const Text('Loading'),
      iconErrorWidget: const Text('Failed'),
    );
    await tester.pumpWidget(MaterialApp(home: destination.buildIcon()));
    provider.completer.completeError(StateError('Download failed'));
    await tester.pump();
    expect(find.text('Failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native tab fallback keeps selected widgets, badges and taps', (
    tester,
  ) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: IOS26NativeTabBar(
            destinations: const [
              AdaptiveNavigationDestination(
                icon: Text('Normal'),
                selectedIcon: Text('Selected'),
                label: 'Profile',
                badgeText: 'NEW',
              ),
              AdaptiveNavigationDestination(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
            ],
            selectedIndex: 0,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('NEW'), findsWidgets);
    await tester.tap(find.text('Home'));
    expect(tapped, 1);
  });

  test(
    'native capsule uses Flutter for custom image placeholders and widgets',
    () {
      const destination = AdaptiveNavigationDestination(
        icon: NetworkImage('https://example.com/avatar.png'),
        label: 'Profile',
        iconPlaceholder: Icon(Icons.person),
      );
      final item = GlassCapsuleItem.fromDestination(destination);
      expect(item.canShowNatively, isFalse);
      expect(item.fallback, isNotNull);
      expect(
        const AdaptiveNavigationDestination(
          icon: Text('Cached widget'),
          label: 'Profile',
        ).requiresFlutterIcon,
        isTrue,
      );
      expect(
        AdaptiveNavigationDestination(
          icon: DeferredImage(),
          label: 'Profile',
        ).requiresFlutterIcon,
        isTrue,
      );
    },
  );
}
