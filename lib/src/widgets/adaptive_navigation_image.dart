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
  });

  final ImageProvider image;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 26,
    child: ClipOval(
      child: Image(
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
      ),
    ),
  );
}
