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

## Native rendering and performance

On iOS 26 and above, the native `UITabBar` remains mounted, preserving Liquid
Glass, native minimization, badges, tap handling, and search-tab configuration.
Custom providers and widgets render in an invisible Flutter paint layer. The
26 × 26 logical-pixel bitmap is sent to the native item's normal/selected images
at the current device pixel ratio. The native side creates a `CGImage` directly
from premultiplied RGBA, with no PNG encoding, PNG decoding, or extra resizing.

Network loading, headers, placeholders, errors, and disk caching remain
controlled by the supplied Flutter provider or widget. Native URL loading
remains available for ordinary `NetworkImage` destinations without overrides.
Source-image decoding and cache size limits remain the responsibility of the
provider/widget; this bridge does not resize or re-download the source file.

Optimizations:

- Observe changes inside the icon's composed layer subtree. Unrelated frames,
  scrolling, and movement of ancestors do not trigger GPU readback for a static
  icon. Nested repaint boundaries, transforms, and opacity fades are observed.
- Compare RGBA before uploading. Identical repaints produce no channel update.
- Send only changed icon states, coalesced into batches over a 16 ms window.
  Only the affected native items are updated, without rebuilding the tab bar.
- If `selectedIcon` is omitted or equals `icon`, share one Flutter subtree, one
  bitmap, one transfer, and one native image for both states.
- Keep snapshot state and unchanged native images across destination updates.
  Revisions reject stale uploads; pending updates survive revision/view changes.
- Stop snapshot rendering and queued uploads while the tab bar is hidden.
  Hiding/showing preserves the native view, and identical cached pixels are not
  uploaded again when it is shown.
- Serialize GPU readbacks and channel uploads, release temporary images and
  timers on disposal, and recapture when the device pixel ratio changes.
- Throttle changing icons to at most ten captures per second. Static icons do
  not request a frame loop; animated placeholders and fades are sampled at
  up to ten frames per second.

RGBA trades compression for lower processing work. At a device pixel ratio of
3, one 78 × 78 icon uses 24,336 bytes (about 24 KB) per changed bitmap. Both states
share those bytes when identical. Bitmaps and the last RGBA comparison buffer
are bounded per mounted icon. No real-device CPU, frame-time, or battery
benchmark has been performed, so these are verified work reductions rather
than claims about measured device speed.

In the Duo vertical capsule, Flutter draws custom icons over the native Liquid
Glass controls. The native capsule itself remains in use.

## Validation

- All 330 package tests passed, covering image loading, errors, selection,
  badges, taps, and the native image bridge.
- Native bridge tests check that `UiKitView` stays mounted, both icon states
  reach the platform channel, and the Flutter snapshot layer remains invisible.
- Capture instrumentation verifies that 60 frames of ancestor movement produce
  zero additional readbacks after the initial capture. Identical repaints do not
  upload; nested fade changes do update pixels.
- Channel tests verify shared-state rendering, batched delta updates, no upload
  on selection changes, native-view preservation while hidden, cached-pixel
  reuse on showing, and pending updates surviving revision changes.
- Static analysis of `lib` and `test` passed.
- A separate test project validates `cached_network_image` 3.4.1 provider and
  widget loading with delayed cache responses, headers, fades, and no further
  captures after loading completes. The package adds no mandatory cache dependency.
- Native Swift code is type-checked against the iOS simulator SDK. A separate
  Core Graphics check verifies RGBA byte order and premultiplied alpha.
- Liquid Glass appearance has not been visually verified on an iOS device.

## Native tab icon tint

Flutter-rendered icons use UIKit template rendering on the native iOS tab bar.
`unselectedItemColor` colors unselected icons, and the selected tab tint colors
selected icons. UIKit uses the bitmap alpha as the icon mask, so original RGB
colors (including photo colors) are replaced by the state tint. Tint changes
do not require another Flutter snapshot or image upload. Liquid Glass remains
provided by the native tab bar.
