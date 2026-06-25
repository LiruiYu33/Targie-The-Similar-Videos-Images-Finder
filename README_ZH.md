# <img src="asset/icon_white.png" width="28" alt="" /> Targie

[English](README.md) | [繁體中文](README_ZH_HANT.md) | [Español](README_ES.md) | [Français](README_FR.md)

> **仅支持 macOS。** Targie 是一款原生 macOS 14+ 应用，没有 Windows 或 Linux 版本，也不计划提供。

Targie 通过结合元数据、内容哈希、感知指纹和视觉特征，在多个所选文件夹之间寻找相似视频与图片。

## 功能

- 可切换“视频”“图片”“全部”三种扫描模式，并记住上次选择。
- 可通过文件夹选择器或 Finder 拖放同时添加多个文件夹，并跨目录统一比较媒体文件。
- 递归扫描常见视频格式，以及 JPEG、PNG、HEIC、HEIF、WebP、TIFF、GIF 和 BMP 图片。
- 综合 SHA-256、可持久化感知指纹、元数据和复用的 Vision 特征，无法读取的文件不会中断扫描。
- 视频与图片分开分组，支持并排检查和应用内静态预览。
- 可用默认播放器打开视频，并可在 Finder 中显示任意媒体文件。
- 支持明确勾选多个文件后批量删除，部分失败时保留失败项并显示错误。
- 删除时必须选择移到废纸篓或永久删除，永久删除会再次确认。
- 支持英文、简体中文、繁体中文、西班牙语和法语即时切换，并记住上次选择的语言。
- **浏览模式**：以可排序、可筛选的表格浏览所选文件夹中所有文件，支持拖拽调整列宽、批量选择，窗口标题实时显示筛选后的文件数量。

![图片相似比较](asset/Screenshot1.png)

![视频相似比较](asset/Screenshot2.png)

![浏览模式 — 文件列表与预览](asset/Screenshot3.png)

## 安装

1. 从 [Releases](https://github.com/LiruiYu33/Targie-The-Similar-Videos-Images-Finder/releases) 下载最新的 `Targie-v*.zip`。
2. 解压后将 **Targie.app** 拖入"应用程序"文件夹（或其他任意位置）。
3. 本 App 使用临时签名，首次启动时 macOS 门禁会拦截：
   - **右键**（或按住 Control 点击）App → **打开** → 在对话框中点击 **打开**。
   - 或者前往 **系统设置 → 隐私与安全性**，滚动到底部，在 Targie 条目旁点击 **仍然允许**，然后正常打开 App。
   - 只需操作一次。首次成功启动后门禁不会再拦截。

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
