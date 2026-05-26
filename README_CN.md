# NetSpeed

一个轻量级的 macOS 菜单栏网络速度监控工具，实时显示上传和下载速度。

![screenshot](screenshot.png)

![Swift](https://img.shields.io/badge/Swift-5.7-orange) ![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)

## 功能

- 菜单栏显示实时上传↑和下载↓速度
- 每秒刷新一次
- 自动检测物理网络接口（Wi-Fi、USB-C、Thunderbolt 以太网）
- 右键菜单：开机启动开关、退出
- 零外部依赖，仅使用系统框架

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
