# NetSpeed

一个轻量级的 macOS 菜单栏网络监控工具，实时显示整体网速、各 App 实时网速榜单，以及今日和本月流量统计。

![NetSpeed 流量面板](screenshot.png?v=20260828-114436)

![Swift](https://img.shields.io/badge/Swift-5.7-orange) ![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)

## 新版特性

- **菜单栏双行网速**：实时显示总体上传与下载网速。
- **Surge 风格流量面板**：点击菜单栏网速即可打开原生弹层，集中展示实时流量、图表和排行。
- **App 实时流量 Top 5 榜单**：查看当前带宽占用最高的 5 个应用及进程。
- **今日与本月统计**：可切换当天累计量和当前自然月累计量，跨日、跨月自动换桶。
- **流量历史柱状图**：今日模式按小时显示，本月模式按天显示。
- **高清 App 图标与 SF Symbols**：自动匹配应用的高清图标，后台守护进程匹配矢量 SF Symbols。
- **异步无阻塞引擎**：后台异步轮询 `nettop`，点击弹出菜单 0 延迟，极速流畅。
- **展开面板动态刷新**：弹层打开时，网速、图表和排行保持实时刷新。
- **开机自启**：右键菜单栏网速可管理开机启动或退出应用。
- **零外部依赖**：纯 Swift & Cocoa 原生系统框架，无任何第三方依赖。

## 构建

```bash
git clone https://github.com/mrnotcool/netspeed.git
cd netspeed
bash build.sh
```

## 打包分发

```bash
bash distribute.sh
```

将在 `dist/` 目录下生成 `NetSpeed.zip` 和 `NetSpeed.dmg`。

## 安装与使用

下载后直接将 `NetSpeed.app` 拖入 `应用程序` 文件夹运行即可。

> 注意：应用未签名，首次打开时请在 Finder 中右键点击 → 选择「打开」以绕过 Gatekeeper。

## 许可证

MIT
