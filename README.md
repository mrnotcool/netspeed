# NetSpeed

A lightweight macOS menu bar app that displays real-time network upload and download speeds, per-app bandwidth usage, and daily or monthly traffic statistics.

![screenshot](screenshot.png)

![Swift](https://img.shields.io/badge/Swift-5.7-orange) ![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)

## Features

- **Menu Bar Net Speed**: Displays real-time upload and download speeds in the menu bar.
- **Surge-Style Traffic Dashboard**: Click the menu bar item to open a native popover with a compact visual hierarchy.
- **Top 5 Realtime Apps**: View the five applications currently consuming the most bandwidth.
- **Today and This Month**: Switch between daily and calendar-month application totals.
- **Traffic History Chart**: Displays hourly bars for today and daily bars for the current month.
- **High-DPI App Icons & SF Symbols**: Displays sharp application icons with fallback vector SF Symbols for background daemons.
- **Non-blocking & Asynchronous**: Asynchronous background polling via `nettop` ensures 0ms UI latency.
- **Live Popover Updating**: Speeds, charts, and rankings refresh while the dashboard is open.
- **Launch at Login**: Right-click the menu bar item to manage launch-at-login or quit the app.
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
