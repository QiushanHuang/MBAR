# Third-party notices

MBAR is distributed under GPL-3.0 (see LICENSE).

The Objective-C runtime bridge in Sources/MBARBridge/MBARBridge.m is adapted from
Pelmet's MBAssessmentShim.m, Copyright (c) 2026 Gabriel Faucon, GPL-3.0:
https://github.com/fif7y/pelmet/blob/095cc56e96afd110743267894a803b58ab672333/Packages/PelmetEngine/Sources/PelmetEngineObjC/MBAssessmentShim.m

Runtime class/selector availability and the macOS 27 MenuBarAgent hierarchy were
investigated with reference to Pelmet at the same revision. MBAR's Swift app,
state policy, tests and panel UI were written for this workspace.

Ice (https://github.com/jordanbaird/Ice) and iBar
(https://www.better365.cn/ibar.html) served as behavior/visual references only.
No iBar binaries, artwork, license data or proprietary code are included.

## Liquid Glass design references

MBAR applies the [Liquid Glass skill’s AppKit guidance](https://github.com/farkasseb/liquid-glass-skill/blob/acb6ef099978eb9e914e9605d847df4ae904754c/references/appkit.md) to its native clear material. The separation of scattering, the curved bevel and opposing specular highlights follows [LiquidGlass’s optical model](https://github.com/shayann07/liquidglass/blob/9effb52bcb9d36e8048666b935f9d4ac46b99b47/ports/npm/optics.mjs#L144-L208). MBAR renders its own size-aware mask and reflections in Core Animation. AppKit composites the live backdrop.
