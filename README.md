# NetSpeed

A lightweight macOS menu bar app that displays real-time network upload and download speeds, per-app bandwidth usage, and 30-day cumulative traffic statistics.

![screenshot](screenshot.png)

![Swift](https://img.shields.io/badge/Swift-5.7-orange) ![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)

## Features

- **Menu Bar Net Speed**: Displays real-time upload and download speeds in the menu bar.
- **Top 5 Realtime Apps**: Click menu bar icon to view top 5 network-consuming applications in real-time.
- **Top 5 30-Day Cumulative Traffic**: Tracks 30-day accumulated data usage per app (automatically resets every 30 days).
- **High-DPI App Icons & SF Symbols**: Displays sharp application icons with fallback vector SF Symbols for background daemons.
- **Non-blocking & Asynchronous**: Asynchronous background polling via `nettop` ensures 0ms UI latency.
- **Live Menu Updating**: Menu stats update continuously in real-time even while the dropdown menu is open.
- **Launch at Login**: Easily toggle auto-launch at login.
- **Zero Dependencies**: Pure Swift & Cocoa system frameworks without external dependencies.

## Build

```bash
git clone https://github.com/mrnotcool/netspeed.git
cd netspeed
bash build.sh
```

## Distribute

```bash
bash distribute.sh
```

Generates `dist/NetSpeed.zip` and `dist/NetSpeed.dmg`.

## License

MIT
