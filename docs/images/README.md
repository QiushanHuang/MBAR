# MBAR identity

The mark combines a menu-bar line, a downward chevron and a three-item shelf.
The teal gradient and rounded tile retain the app's original visual language.

`mbar-icon.png` is rendered by `scripts/make-icon.swift`; the same renderer builds
all sizes of the application's `AppIcon.icns`. It is deterministic AppKit artwork,
with no external image service or third-party logo assets.

Regenerate the documentation image:

```sh
swift scripts/make-icon.swift .build/brand.iconset
cp .build/brand.iconset/icon_512x512@2x.png docs/images/mbar-icon.png
```
