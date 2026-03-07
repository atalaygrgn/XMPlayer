# XMPlayer 🎵

![XMPlayer Hero](assets/readme/hero.png)

**XMPlayer** is a premium, XMB-inspired media player designed specifically for handheld gaming devices running **muOS** (like the Anbernic RG35XX series). It provides a sleek, high-end interface for managing and enjoying your music, videos, and photos.

---

## ✨ Features

- 💎 **XMB Interface:** A beautiful, responsive XrossMediaBar UI inspired by classic console interfaces.
- 🎧 **iPod Classic Mode:** A dedicated full-screen music player interface with album art, smooth progress bars, and classic controls.
- 📽️ **Video Playback:** Integrated **MPV** support for high-performance video playing with custom gamepad mappings.
- 🖼️ **Photo Viewer:** Browse and view your photo collection with smooth transitions and slideshow support.
- 🌈 **Dynamic Backgrounds:** Fluid particle animations and customizable gradients that react to the current theme.
- 🎨 **Premium Themes:** Choose between Light and Dark modes with a variety of accent colors including Silver, Black, Beige, Tan, and more.
- ⚡ **Fast Indexing:** High-performance background indexing to handle large media libraries without slowing down the UI.
- 🔋 **System Integration:** Live battery percentage and clock display in the status bar.

---

## 🚀 Installation

### Prerequisites
- A handheld device running **muOS**.
- Your music, videos, and photos organized on your SD card.

### Steps
1. Download the latest release or clone this repository.
2. Copy the `XMPlayer` folder to your muOS application directory (usually `/mnt/sdcard/MUOS/app/` or `/mnt/mmc/MUOS/app/`).
3. Ensure the `mux_launch.sh` script is executable.
4. Launch **XMPlayer** from the Apps menu in muOS.

---

## 🎮 Controls

XMPlayer uses a custom `gptokeyb` mapping to ensure a comfortable handheld experience.

| Button | Function (Global) | Function (Music Player) |
| :--- | :--- | :--- |
| **D-Pad Up/Down** | Navigate Menu | Volume Up/Down |
| **D-Pad Left/Right** | Change Category | Skip Forward/Backward |
| **A** | Select / Open | Play / Pause |
| **B** | Back | Close Player |
| **X** | Context Menu | Toggle Shuffle |
| **Y** | - | Toggle Repeat |
| **L1 / R1** | Page Up / Down | Previous / Next Track |
| **Start** | Play Selection | - |
| **Select** | Settings | - |
| **Menu (Guide)** | Exit Application | Exit to XMB |

> [!TIP]
> While in the Video Player (MPV), use **A** to Pause, **Y** for OSD, and **Select** to Quit.

---

## 🎨 Customization

You can personalize XMPlayer via the **Settings** menu:

- **Themes:** Toggle between `Light` and `Dark` modes.
- **Accents:** Choose from `Blue`, `Red`, `Green`, `Teal`, `Purple`, `Yellow`, `Orange`, `Silver`, `Black`, `Beige`, or `Tan`.
- **Paths:** Configure your media directories for Music, Photos, and Videos.

---

## 🛠️ Architecture

XMPlayer is built using the **LÖVE (Love2D)** framework and organized into modular Lua scripts:

- `xmb.lua`: Core interface and navigation logic.
- `music_player.lua`: iPod-style playback interface.
- `player.lua`: MPV integration for video playback.
- `background.lua`: Particle and gradient rendering.
- `indexing.lua`: Media library scanning and metadata extraction.
- `theme.lua`: Color palette and styling system.

---

## 📜 Credits

- Developed for the **muOS** community.
- Built with **Love2D**.
- Icons provided by various open-source libraries.

---

*Made with ❤️ for handheld enthusiasts.*
