# Targie

[English](README.md)

> **仅支持 macOS。** Targie 是一款原生 macOS 14+ 应用，没有 Windows 或 Linux 版本，也不计划提供。

Targie 通过结合元数据、内容哈希、感知指纹和视觉特征，在指定文件夹中寻找相似视频与图片。

## 功能

- 可切换“视频”“图片”“全部”三种扫描模式，并记住上次选择。
- 递归扫描常见视频格式，以及 JPEG、PNG、HEIC、WebP、TIFF、GIF 和 BMP 图片。
- 综合 SHA-256、可持久化感知指纹、元数据和复用的 Vision 特征，无法读取的文件不会中断扫描。
- 视频与图片分开分组，支持并排检查和应用内静态预览。
- 可用默认播放器打开视频，并可在 Finder 中显示任意媒体文件。
- 支持明确勾选多个文件后批量删除，部分失败时保留失败项并显示错误。
- 删除时必须选择移到废纸篓或永久删除，永久删除会再次确认。
- 支持英文和简体中文即时切换，并记住上次选择的语言。

## 构建（仅 macOS）

```bash
swift test
./script/build_app.sh
```

生成的应用位于：

```text
dist/Targie.app
```

开发时可以构建并启动：

```bash
./script/build_and_run.sh
```

应用使用临时签名，适合本机使用。如需通过网络或 App Store 分发，还需要 Developer ID、应用公证和对应的打包流程。

## 开源许可

Targie 采用 **[GNU General Public License v3.0](LICENSE)** 协议开源。

Copyright (C) 2026 Lirui Yu。

如果你复用本仓库的代码（无论是否修改）：

- **必须**保留版权声明，并署名原作者（Lirui Yu）。
- 任何对外分发的衍生作品**必须**同样以 GPL-3.0（或更新的 GPL 版本）开源，并向使用者提供完整源码。
- **不允许**闭源或私有化再分发。

完整法律条款见 [LICENSE](LICENSE) 文件。

## 贡献

欢迎提交 Pull Request。每个 commit 必须按 [Developer Certificate of Origin (DCO)](DCO) 签署，即在 `git commit` 时加 `-s` 参数。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。
