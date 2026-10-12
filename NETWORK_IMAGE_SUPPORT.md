# Network image support

This document describes local changes to `adaptive_platform_ui` separately from
upstream README and release history.

## Changes

- Added `iconPlaceholder` and `iconErrorWidget` to `AdaptiveNavigationDestination`.
- Both normal and selected image providers use the configured placeholder and error widget.
- Support arbitrary image providers, including `CachedNetworkImageProvider`, and complete `CachedNetworkImage` widgets without adding a mandatory caching dependency to the package.
- Preserve Flutter loading and caching behavior in iOS tab bars and Duo glass capsules.
- Added tests for loading, successful decoding, errors, selection, badges, and taps.

## Usage


Navigation image providers accept any widget as a loading placeholder and an
optional error widget. Both normal and selected icons share these widgets:

```dart
AdaptiveNavigationDestination(
  icon: NetworkImage(avatarUrl),
  label: 'Profile',
  iconPlaceholder: Image.asset('assets/avatar_placeholder.png'),
  iconErrorWidget: const Icon(Icons.person),
)
```

For disk caching, add `cached_network_image` to your application's dependencies
and import `package:cached_network_image/cached_network_image.dart`. The package
accepts `CachedNetworkImageProvider` without adding a mandatory cache dependency:

```dart
AdaptiveNavigationDestination(
  icon: CachedNetworkImageProvider(avatarUrl),
  label: 'Profile',
  iconPlaceholder: Image.asset('assets/avatar_placeholder.png'),
)
```

You can also supply a complete `CachedNetworkImage` widget as `icon` or
`selectedIcon`. Configure its own `placeholder` and `errorWidget` callbacks and
set `width: 26`, `height: 26`, and `fit: BoxFit.cover`; wrap it in `ClipOval` for a
round avatar. Destination placeholders apply to providers and `ImageIcon`, while
custom widgets manage their own loading UI.

On iOS 26, destinations with custom widgets, custom placeholders, error widgets,
or providers beyond `AssetImage`, `FileImage`, and `NetworkImage` use a Flutter
Cupertino bottom tab bar. Native Liquid Glass tab minimization and separated
search-tab behavior are unavailable in that mode. In the Duo vertical capsule,
Flutter draws these icons over the native glass controls. Native URL loading
remains available for ordinary `NetworkImage` destinations without overrides.

## Validation

- All 324 package tests passed.
- Static analysis of `lib` and `test` passed.
- A separate test project verified compatibility with the actual provider and widget types from `cached_network_image` 3.4.1.
- Native iOS rendering has not been verified on a device.
