# Contributing

Please open an issue describing the macOS version, MBAR version, affected app and
its version, display arrangement, and steps to reproduce. Remove personal app
identifiers and paths from diagnostics before posting.

Build with macOS 27 and a Swift 6 toolchain (release validation uses Swift 6.4):

```sh
swift test
swift test -c release
./scripts/build-app.sh
```

Keep verified menu-bar resource adapters explicit. Label heuristic matches and
user-imported images separately; incomplete or ambiguous scans must not auto-select.
Source rules: no app-icon fallback in the shelf,
no hidden screen expansion to collect artwork, and no execution of another app's
binary. Native capture must be an explicit user request. Use ScreenCaptureKit's
result as the authority; a negative preflight alone must not block that request.
Include focused tests for resource parsers or policy changes. Private API
and physical multi-display behavior require manual checks beyond unit tests.

Submit a pull request with the problem, change, validation and remaining limits.
Contributions are distributed under the project's GPL-3.0 license; preserve all
upstream notices. See [CONTRIBUTORS.md](CONTRIBUTORS.md).

## 中文

提交问题时请注明 macOS、MBAR、目标应用版本、显示器布局和复现步骤。
公开诊断信息前移除个人应用标识和路径。使用上述命令构建和测试。

图标适配需明确来源，区分已验证适配、自动匹配、用户选择和自定义图片。
扫描不完整或候选歧义时不能自动采用；不用应用 logo 自动替代菜单图标、不为获取图标展开系统栏、
不执行其他应用的二进制。原生采集必须由用户主动触发，以 ScreenCaptureKit 的实际结果判断授权，
不能仅凭旧预检值阻断请求。资源解析和策略变更需提供针对性测试；
私有接口及真实多显示器行为仍需手动验证。PR 请说明问题、修改、验证及限制。
贡献采用项目的 GPL-3.0 许可，并保留上游署名。

## Local test fixtures / 本地测试素材

`swift scripts/make-test-catalog.swift` regenerates the original rectangle artwork
used by the catalog tests. Do not add extracted third-party icons or personal
capture images to the repository.

The live capture test is opt-in through `MBAR_NATIVE_PROBE_BUNDLES`, a comma-separated
list of running app bundle IDs whose menu items are already visible. It requires
existing permissions and does not change visibility or grant access. Keep this
separate from ordinary unit-test claims.

上述命令重建资源库测试用的原创矩形素材，不应提交第三方图标或个人采集图像。
`MBAR_NATIVE_PROBE_BUNDLES` 可显式指定已有权限、正在运行且图标可见的应用标识，启用实机采集测试。
该测试不修改显示方式或系统权限，验证结果与普通单元测试分开记录。
