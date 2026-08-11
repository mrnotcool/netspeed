# NetSpeed

一个轻量级的 macOS 菜单栏网络监控工具，实时显示整体网速、各 App 实时网速榜单及 30 日累计流量统计。

![screenshot](screenshot.png)

![Swift](https://img.shields.io/badge/Swift-5.7-orange) ![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)

## 新版特性

- **菜单栏双行网速**：实时显示总体上传与下载网速。
- **App 实时流量 Top 5 榜单**：点击菜单可查看当前网速前 5 名的应用及进程，右侧数值右对齐。
- **App 30日累计流量 Top 5 榜单**：自动记录并累计各应用 30 天内消耗的总流量（每 30 天自动重置）。
- **高清 App 图标与 SF Symbols**：自动匹配应用的高清图标，后台守护进程匹配矢量 SF Symbols。
- **异步无阻塞引擎**：后台异步轮询 `nettop`，点击弹出菜单 0 延迟，极速流畅。
- **展开面板动态刷新**：在菜单展开状态下，榜单网速与流量依然保持每秒实时刷新。
- **开机自启**：支持一键开启或关闭开机自动启动。
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
