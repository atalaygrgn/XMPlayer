# VGM Files Compatibility Information

### Compatibility on Average Linux Handheld Hardware

**The only formats expected to stutter consistently are `.vgm` and `.vgz`**. All PSG and wavetable formats (`.spc`, `.nsf`, `.nsfe`, `.gbs`, `.hes`, `.kss`) should play smoothly.

---

### FM Synthesis

These formats use **Frequency Modulation synthesis**: multiple sine-wave operators per channel with cycle-accurate register emulation. This is the most CPU-intensive class of chip audio.

| Format | Chip | Notes |
|--------|------|-------|
| `.vgm` | YM2612 — Sega Genesis / Master System / Game Gear | 6 channels × 4 FM operators = 24 oscillators per sample. **May stutter** on constrained hardware. |
| `.vgz` | YM2612 (compressed VGM) | Identical to VGM after decompression. **May stutter** on constrained hardware. |

---

### PSG / Wavetable
These are **simple oscillators or sample playback**, just computing square waves, triangle waves, or reading sample tables. Orders of magnitude cheaper than FM.

| Format | Chip | Notes |
|--------|------|-------|
| `.spc` | SNES SPC700 DSP | 8 BRR-compressed sample channels with hardware echo/reverb. |
| `.nsf` | NES 2A03 APU | 2 pulse + 1 triangle + 1 noise + 1 DPCM. One of the simplest chips. |
| `.nsfe` | NES 2A03 APU | Extended NSF with track name/time metadata. Same chip as NSF.|
| `.gbs` | Game Boy APU | 2 pulse + 1 wavetable + 1 noise, similar to NES APU. |
| `.hes` | HuC6280 — TurboGrafx-16 / PC Engine | 6 wavetable channels, slightly more complex than NES, still lightweight. |
| `.kss` | AY-3-8910 / SN76489 — MSX & Sega Master System | 3–4 channel PSG square waves, extremely lightweight. |

---

### Not Supported

| Format | Notes |
|--------|--------|
| `.gym` | No native support |
| `.sap` | No native support |
| `.ay` | No native support |
| `.mod` | Requires `libopenmpt` |
| `.s3m` | Requires `libopenmpt` |
| `.xm` | Requires `libopenmpt` |
| `.it` | Requires `libopenmpt` |