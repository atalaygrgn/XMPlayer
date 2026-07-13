# Feature Compatibility Complete List
### Current version: v0.2.0

| Feature | muOS App (.muxapp) | muOS PortMaster | Knulli PortMaster | Rocknix PortMaster | EmuELEC PortMaster | dArkOS PortMaster |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Background Play on Clamshell Lid-Close | ✅ | ❌ | ❌ | ❌ | ❎ | ❎ |
| Volume & Brightness Tracking | ✅ | ✅ | ❌ | ❎ | ❎ | ❌ |
| Battery Level Display | ✅ | ✅ | ✅ | ✅ | ❎ | ❌ |
| Power-Saving Display Sleep | ✅ | ✅ | ✅ | ✅ | ❎ | ❌ |
| Video Playback | ✅ mpv & ffplay | ✅ mpv & ffplay | ✅ mpv | ✅ mpv | ✅ mpv | ❌ ffplay |
| Music Playback | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Photo Viewing | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

✅: Implemented, ❎: Not necessary to implement, ❌: Not implemented yet,❓: Should work, but untested

### Features in the muOS App (.muxapp) build, but NOT in the PortMaster build

- **Background Play on Clamshell Lid-Close**: The muOS app contains an override to the system hall sensor directories. This prevents clamshell devices from entering sleep mode when the lid is closed, allowing music playback to continue. This is omitted in the PortMaster release for now, and planned to be implemented in future builds.

### Features in muOS (.muxapp and PortMaster) but NOT in other CFWs

- **Volume & Brightness Tracking**: XMPlayer tracks volume and brightness changes by reading muOS-specific system paths. On other CFWs, this is yet to be implemented as different (efficient) approaches are needed to get system stats. Rocknix and EmuELEC don't need this feature since they provide their own volume/brightness overlay to ports.

### About dArkOS Compatibility

- **FFplay Video Playback**: Launching `ffplay` from XMPlayer on dArkOS fails with a missing `libvulkan.so.1` error because the Love2D runtime overrides `LD_LIBRARY_PATH` with its own bundled library directory, which interferes with the system paths containing Vulkan libraries.