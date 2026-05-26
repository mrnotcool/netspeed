# NetSpeed

A lightweight macOS menu bar app that displays real-time network upload and download speeds.

![screenshot](screenshot.png)

![Swift](https://img.shields.io/badge/Swift-5.7-orange) ![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue)

## Features

- Displays upload ↑ and download ↓ speeds in the menu bar
- Updates every second
- Auto-detects physical network interfaces (Wi-Fi, USB-C, Thunderbolt Ethernet)
- Right-click menu with Launch at Login toggle and Quit
- Zero dependencies — uses only system frameworks

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
