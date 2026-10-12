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

void main() {
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
