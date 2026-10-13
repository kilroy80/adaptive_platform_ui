import 'dart:async';
import 'dart:ui' as ui;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_glass_capsule.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets(
    'images keep original pixels and use state-specific loading UI after taps',
    (tester) async {
      final normal = DeferredNetworkImage();
      final selected = DeferredImage();
      final normalKey = GlobalKey();
      final selectedKey = GlobalKey();
      var selectedIndex = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => AdaptiveScaffold(
              body: const SizedBox(),
              bottomNavigationBar: AdaptiveBottomNavigationBar(
                selectedIndex: selectedIndex,
                onTap: (index) => setState(() => selectedIndex = index),
                selectedItemColor: Colors.transparent,
                unselectedItemColor: Colors.blue,
                items: [
                  AdaptiveNavigationDestination(
                    label: 'Profile',
                    icon: RepaintBoundary(
                      key: normalKey,
                      child: AdaptiveNavigationImage(
                        image: normal,
                        placeholder: const Text('Loading normal'),
                        errorWidget: const Text('Failed normal'),
                      ),
                    ),
                    selectedIcon: RepaintBoundary(
                      key: selectedKey,
                      child: AdaptiveNavigationImage(
                        image: selected,
                        placeholder: const Text('Loading selected'),
                        errorWidget: const Text('Failed selected'),
                      ),
                    ),
                  ),
                  const AdaptiveNavigationDestination(
                    icon: Icons.home,
                    label: 'Home',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Loading selected'), findsOneWidget);
      expect(find.byType(ColorFiltered), findsNothing);
      Future<ui.Image> pixels(Color color) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(color, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 2);
        picture.dispose();
        return image;
      }

      selected.completer.complete(ImageInfo(image: await pixels(Colors.red)));
      normal.completer.complete(ImageInfo(image: await pixels(Colors.green)));
      await tester.pumpAndSettle();

      Future<void> expectOriginalPixels(GlobalKey key, Color color) async {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset =
              ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
          expect(pixels.getUint8(offset), (color.r * 255).round());
          expect(pixels.getUint8(offset + 1), (color.g * 255).round());
          expect(pixels.getUint8(offset + 2), (color.b * 255).round());
          expect(pixels.getUint8(offset + 3), 255);
          image.dispose();
        });
      }

      await expectOriginalPixels(selectedKey, Colors.red);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await expectOriginalPixels(normalKey, Colors.green);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await expectOriginalPixels(selectedKey, Colors.red);
    },
  );

  testWidgets('placeholder is replaced by a decoded custom provider image', (
    tester,
  ) async {
    final provider = DeferredImage();
    final destination = AdaptiveNavigationDestination(
      icon: AdaptiveNavigationImage(
        image: provider,
        placeholder: const Text('Loading'),
      ),
      label: 'Profile',
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
      icon: AdaptiveNavigationImage(
        image: provider,
        placeholder: const Text('Loading'),
        errorWidget: const Text('Failed'),
      ),
      label: 'Profile',
    );
    await tester.pumpWidget(MaterialApp(home: destination.buildIcon()));
    provider.completer.completeError(StateError('Download failed'));
    await tester.pump();
    expect(find.text('Failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each icon state keeps its own placeholder and error widget', (
    tester,
  ) async {
    final normal = DeferredImage();
    final selected = DeferredImage();
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) => AdaptiveScaffold(
            body: const SizedBox(),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              selectedIndex: index,
              onTap: (next) => setState(() => index = next),
              items: [
                AdaptiveNavigationDestination(
                  label: 'Profile',
                  icon: AdaptiveNavigationImage(
                    image: normal,
                    placeholder: const Text('Loading normal'),
                    errorWidget: const Text('Failed normal'),
                  ),
                  selectedIcon: AdaptiveNavigationImage(
                    image: selected,
                    placeholder: const Text('Loading selected'),
                    errorWidget: const Text('Failed selected'),
                  ),
                ),
                const AdaptiveNavigationDestination(
                  icon: Icons.home,
                  label: 'Home',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Loading selected'), findsOneWidget);
    selected.completer.completeError(StateError('Selected download failed'));
    await tester.pumpAndSettle();
    expect(find.text('Failed selected'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Loading normal'), findsOneWidget);
    normal.completer.completeError(StateError('Normal download failed'));
    await tester.pumpAndSettle();
    expect(find.text('Failed normal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'plain image sources keep the native path; custom loading uses Flutter',
    () {
      const plain = AdaptiveNavigationDestination(
        icon: NetworkImage('https://example.com/avatar.png'),
        label: 'Profile',
      );
      expect(plain.requiresFlutterIcon, isFalse);
      expect(
        const AdaptiveNavigationDestination(
          icon: AssetImage('avatar.png'),
          label: 'Profile',
        ).requiresFlutterIcon,
        isFalse,
      );
      expect(
        const AdaptiveNavigationDestination(
          icon: NetworkImage(
            'https://example.com/avatar.png',
            headers: {'Authorization': 'test'},
          ),
          label: 'Profile',
        ).requiresFlutterIcon,
        isTrue,
      );
      expect(
        const AdaptiveNavigationDestination(
          icon: AssetImage('avatar.png', package: 'my_package'),
          label: 'Profile',
        ).requiresFlutterIcon,
        isTrue,
      );
      expect(
        const AdaptiveNavigationDestination(
          icon: AdaptiveNavigationImage(
            image: NetworkImage('https://example.com/avatar.png'),
          ),
          label: 'Profile',
        ).requiresFlutterIcon,
        isTrue,
      );
    },
  );

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
        icon: AdaptiveNavigationImage(
          image: NetworkImage('https://example.com/avatar.png'),
          placeholder: Icon(Icons.person),
        ),
        label: 'Profile',
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
