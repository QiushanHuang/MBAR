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

Keep menu-bar resource adapters explicit: no app-icon fallback in the shelf,
no hidden screen expansion to collect artwork, and no execution of another app's
binary. Include focused tests for resource parsers or policy changes. Private API
and physical multi-display behavior require manual checks beyond unit tests.

Submit a pull request with the problem, change, validation and remaining limits.
Contributions are distributed under the project's GPL-3.0 license; preserve all
upstream notices. See [CONTRIBUTORS.md](CONTRIBUTORS.md).

## 中文

提交问题时请注明 macOS、MBAR、目标应用版本、显示器布局和复现步骤。
公开诊断信息前移除个人应用标识和路径。使用上述命令构建和测试。

图标适配需明确来源，不用应用 logo 替代菜单图标、不为获取图标展开系统栏、
不执行其他应用的二进制。资源解析和策略变更需提供针对性测试；
私有接口及真实多显示器行为仍需手动验证。PR 请说明问题、修改、验证及限制。
贡献采用项目的 GPL-3.0 许可，并保留上游署名。
