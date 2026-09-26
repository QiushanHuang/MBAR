# Catalog fixture

`CatalogFixture.bundle` contains two original black rectangles, named `StatusBarIcon`
and `ToolbarIcon`, both configured as template images. It has no executable and no
third-party artwork. Tests exercise real assetutil metadata, AppKit decoding,
ranking, and digest-stable readback.

Regenerate from the repository root with Xcode's actool:

```sh
swift scripts/make-test-catalog.swift
```
