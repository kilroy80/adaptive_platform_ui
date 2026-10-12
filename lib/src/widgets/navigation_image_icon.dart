import 'package:flutter/cupertino.dart';

/// Shared avatar renderer for arbitrary providers, including cached providers.
class NavigationImageIcon extends StatelessWidget {
  const NavigationImageIcon({
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
