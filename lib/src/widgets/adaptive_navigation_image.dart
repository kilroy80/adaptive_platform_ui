import 'package:flutter/cupertino.dart';

/// Navigation image with its own loading and error widgets.
///
/// Use as icon or selectedIcon of AdaptiveNavigationDestination. Accepts any
/// ImageProvider, including CachedNetworkImageProvider. Pixels keep their
/// original colors; selection and text colors do not tint this widget.
class AdaptiveNavigationImage extends StatelessWidget {
  const AdaptiveNavigationImage({
    super.key,
    required this.image,
    this.placeholder,
    this.errorWidget,
    this.size = 26,
    this.clipOval = true,
  }) : assert(size > 0 && size < double.infinity);

  final ImageProvider image;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// Width and height in logical pixels. Defaults to 26.
  final double size;

  /// Whether to clip the image and loading/error widgets to a circle.
  /// Defaults to true. Set to false to keep square bounds.
  final bool clipOval;

  @override
  Widget build(BuildContext context) {
    final imageWidget = Image(
      // A different source must not inherit the previous source's error state.
      key: ValueKey(image),
      image: image,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, synchronouslyLoaded) =>
          synchronouslyLoaded || frame != null
          ? child
          : placeholder ?? const SizedBox.shrink(),
      errorBuilder: (_, __, ___) =>
          errorWidget ??
          placeholder ??
          const Icon(CupertinoIcons.person_crop_circle),
    );
    return SizedBox(
      width: size,
      height: size,
      child: clipOval ? ClipOval(child: imageWidget) : imageWidget,
    );
  }
}
