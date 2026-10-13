part of 'adaptive_scaffold.dart';

BottomNavigationBarItem _buildCupertinoNavigationItem(
  AdaptiveNavigationDestination destination,
  BuildContext context, {
  Color? selectedColor,
  Color? unselectedColor,
  Color? selectedTextColor,
  Color? unselectedTextColor,
}) {
  var normalIcon = destination.buildIcon(color: unselectedColor);
  var activeIcon = destination.buildIcon(selected: true, color: selectedColor);
  if (destination.hasBadge) {
    normalIcon = destination.wrapWithBadge(normalIcon);
    activeIcon = destination.wrapWithBadge(activeIcon);
  }
  if (selectedTextColor != null || unselectedTextColor != null) {
    final normalColor =
        unselectedTextColor ?? unselectedColor ?? CupertinoColors.inactiveGray;
    final activeColor =
        selectedTextColor ??
        selectedColor ??
        CupertinoTheme.of(context).primaryColor;
    return BottomNavigationBarItem(
      icon: Column(
        children: [
          Expanded(child: Center(child: normalIcon)),
          Text(
            destination.label,
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(normalColor, context),
            ),
          ),
        ],
      ),
      activeIcon: Column(
        children: [
          Expanded(child: Center(child: activeIcon)),
          Text(
            destination.label,
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(activeColor, context),
            ),
          ),
        ],
      ),
    );
  }
  return BottomNavigationBarItem(
    icon: normalIcon,
    activeIcon: activeIcon,
    label: destination.label,
  );
}

Widget _buildNavigationIconWidget(
  AdaptiveNavigationDestination destination, {
  bool selected = false,
  Color? color,
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  final value = selected
      ? destination.selectedIcon ?? destination.icon
      : destination.icon;
  if (value is Icon) {
    return color == null
        ? value
        : IconTheme.merge(
            data: IconThemeData(color: color),
            child: value,
          );
  }
  if (value is Widget) return value;
  if (value is ImageProvider) return AdaptiveNavigationImage(image: value);
  if (value is IconData) return Icon(value, color: color);
  if (value is String) {
    return Icon(
      platform == TargetPlatform.iOS
          ? _sfSymbolToCupertinoIcon(value)
          : Icons.circle,
      color: color,
    );
  }
  return const Icon(CupertinoIcons.circle);
}

IconData _sfSymbolToCupertinoIcon(String sfSymbol) {
  const iconMap = {
    'house': CupertinoIcons.house,
    'house.fill': CupertinoIcons.house_fill,
    'magnifyingglass': CupertinoIcons.search,
    'heart': CupertinoIcons.heart,
    'heart.fill': CupertinoIcons.heart_fill,
    'person': CupertinoIcons.person,
    'person.fill': CupertinoIcons.person_fill,
    'gear': CupertinoIcons.settings,
    'star': CupertinoIcons.star,
    'star.fill': CupertinoIcons.star_fill,
    'bell': CupertinoIcons.bell,
    'bell.fill': CupertinoIcons.bell_fill,
    'bag': CupertinoIcons.bag,
    'bag.fill': CupertinoIcons.bag_fill,
    'bookmark': CupertinoIcons.bookmark,
    'bookmark.fill': CupertinoIcons.bookmark_fill,
    'info.circle': CupertinoIcons.info_circle,
    'info.circle.fill': CupertinoIcons.info_circle_fill,
    'plus.circle': CupertinoIcons.add_circled,
    'plus': CupertinoIcons.add,
    'checkmark.circle': CupertinoIcons.checkmark_circle,
  };
  return iconMap[sfSymbol] ?? CupertinoIcons.circle;
}
