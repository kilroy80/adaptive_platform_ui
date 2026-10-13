# Network image support

This document describes local changes to `adaptive_platform_ui` separately from
upstream README and release history.

## API

Use the existing `icon` and `selectedIcon` slots. `AdaptiveNavigationImage` owns
its image provider, loading placeholder, and error widget. Each icon state can
have different loading/error visuals without extra destination properties:

```dart
AdaptiveNavigationDestination(
  label: 'Home',
  icon: AdaptiveNavigationImage(
    image: NetworkImage(normalUrl),
    placeholder: Image.asset('assets/home.png'),
    errorWidget: Image.asset('assets/home.png'),
  ),
  selectedIcon: AdaptiveNavigationImage(
    image: NetworkImage(selectedUrl),
    placeholder: Image.asset('assets/home_selected.png'),
    errorWidget: Image.asset('assets/home_selected.png'),
  ),
)
```

Omit `selectedIcon` to reuse `icon`. Plain `ImageProvider` values and complete
`Image`/`CachedNetworkImage` widgets remain supported. A complete widget manages
its own sizing and loading UI. `AdaptiveNavigationImage` defaults to a 26 × 26 round-avatar layout.
Set `size` to adjust its square bounds and `clipOval: false` to disable circular
clipping. The native snapshot also uses the configured size when this widget
is supplied directly as `icon` or `selectedIcon`. Switching providers resets the inner image state
so one state's error cannot leak into another state's pending download.

For caching, pass `CachedNetworkImageProvider(url)` as `image`; the application
supplies the cache package, so no extra package dependency is required here.

Images keep their original pixels. Ordinary `Icon`/`IconData`/SF Symbols keep
their normal icon behavior. Flutter's `ImageIcon` is itself a tintable widget;
use `Image` or `AdaptiveNavigationImage` for full-color pictures.

Set `selectedTextColor` on `AdaptiveBottomNavigationBar` to control the common
selected label color. It falls back to `selectedItemColor`, then platform/theme
defaults.

`unselectedTextColor` is an Android label color option. It falls back to
`unselectedItemColor`, then platform/theme defaults. Native iOS 26+ Liquid Glass
does not honor this option: unselected labels use system-controlled colors
(black in light mode, white in dark mode). `selectedTextColor` still applies.

Existing font sizes and weights are preserved. `applyTextTint` was removed;
label colors are independent of images and ordinary icon colors.

Migration: `applyImageTint`, `iconPlaceholder`, and `iconErrorWidget` were removed
from `AdaptiveNavigationDestination`. Move placeholders/errors into the image
widget and choose separate `icon`/`selectedIcon` pixels instead of image tint.

## Native rendering and performance

On iOS 26 and above, the native `UITabBar` remains mounted, preserving Liquid
Glass, native minimization, badges, tap handling, and search-tab configuration.
Custom providers and widgets render in an invisible Flutter paint layer. The
icon-sized logical-pixel bitmap is sent to the native item's normal/selected images
at the current device pixel ratio. The native side creates a `CGImage` directly
from premultiplied RGBA, with no PNG encoding, PNG decoding, or extra resizing.

Network loading, headers, placeholders, errors, and disk caching remain
controlled by the supplied Flutter provider or widget. Plain asset/file/network
providers retain the native path. Headers, package assets, custom providers,
and widget-based loading UI use Flutter rendering for correct source resolution.
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

The previous image refactor passed the complete package suite (338 tests),
Dart static analysis and Swift syntax checks. Validation was not run for the
subsequent label-color and image-size/clipping API changes, as requested.

Regression coverage checks decoded image pixels before and after selection,
independent state placeholders/errors, per-destination label colors, and the native bridge.
It also verifies shared-state snapshots, batched changes, no re-upload on
selection, native-view preservation while hidden, and stale update handling.
Swift syntax is checked separately. Real-device rendering and performance
benchmarks are not covered by these tests.

## Upstream scope

Common text colors are configured on `AdaptiveBottomNavigationBar`;
images use the existing `icon` and `selectedIcon` widget slots. The public image
widget reuses the previous image renderer rather than introducing a second
loading/cache implementation. The native snapshot bridge remains necessary to
show Flutter-only cached/custom loading UI inside the native Liquid Glass bar.
Other pre-existing branch changes are outside this refactor.
