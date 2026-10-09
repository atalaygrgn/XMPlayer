# Feature Compatibility Complete List
### Current version: v0.2.1

| Feature | muOS App (.muxapp) | muOS PortMaster | Knulli PortMaster | Rocknix PortMaster | EmuELEC PortMaster | dArkOS PortMaster |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Background Play on Clamshell Lid-Close | ✅ | ❌ | ❌ | ❌ | ❎ | ❎ |
| Volume & Brightness Tracking | ✅ | ✅ | ❌ | ❎ | ❎ | ❌ |
| Battery Level Display | ✅ | ✅ | ✅ | ✅ | ❎ | ❌ |
| Power-Saving Display Sleep | ✅ | ✅ | ✅ | ✅ | ❎ | ❌ |
| Video Playback | ✅ mpv & ffplay | ✅ mpv & ffplay | ✅ mpv | ✅ mpv | ✅ mpv | ⚠️ ffplay |
| Music Playback | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Photo Viewing | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

✅: Implemented, ⚠️: Partially implemented with issues ❎: Not necessary to implement, ❌: Not implemented yet,❓: Should work, but untested

### Features in the muOS App (.muxapp) build, but NOT in the PortMaster build

- **Background Play on Clamshell Lid-Close**: The muOS app contains an override to the system hall sensor directories. This prevents clamshell devices from entering sleep mode when the lid is closed, allowing music playback to continue. This is omitted in the PortMaster release for now, and planned to be implemented in future builds.

### Features in muOS (.muxapp and PortMaster) but NOT in other CFWs

- **Volume & Brightness Tracking**: XMPlayer tracks volume and brightness changes by reading muOS-specific system paths. On other CFWs, this is yet to be implemented as different (efficient) approaches are needed to get system stats. Rocknix and EmuELEC don't need this feature since they provide their own volume/brightness overlay to ports.

### About dArkOS Compatibility

- **FFplay Video Playback**: XMPlayer's own `ffplay` core has audio issues on dArkOS. Some users have reported no audio playing in video. This issue is being investigated.