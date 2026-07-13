# VGM Files Compatibility Information

### Compatibility on Average Linux Handheld Hardware
**The only formats expected to stutter consistently are `.vgm`, `.vgz`, and `.gym`**, all sharing the same YM2612 FM chip. Everything else should behave more like `.spc` and `.nsf`. The tracker formats (`.it` especially) may stutter on particularly dense compositions but should be fine for typical files.

### Formats with FM Synthesis
These use **Frequency Modulation synthesis**: multiple sine-wave operators per channel and cycle-accurate register emulation. This is the most CPU-intensive class of chip music.
| Format | Chip | Reason |
|--------|------|--------|
| `.vgm` | YM2612 (Genesis) | 6 channels × 4 FM operators = 24 oscillators computed per sample |
| `.vgz` | YM2612 (compressed VGM) | Identical to VGM after decompression |
| `.gym` | YM2612 (Genesis) | Same chip as VGM, raw register log of the same hardware |

### PSG / Wavetable
These are **simple oscillators or sample playback**, just computing square waves, triangle waves, or reading sample tables. Orders of magnitude cheaper than FM.

| Format | Chip | Complexity |
|--------|------|------------|
| `.spc` | SNES SPC700 DSP | 8 BRR-compressed sample channels + hardware echo/reverb. **Confirmed working well.** |
| `.nsf` | NES 2A03 APU | 2 pulse + 1 triangle + 1 noise + 1 DPCM. One of the simplest chips. **Confirmed working well.** |
| `.nsfe` | NES 2A03 APU | Extended NSF with track name/time metadata. Same chip as NSF. **Confirmed working well.** |
| `.gbs` | Game Boy APU | 2 pulse + 1 wavetable + 1 noise, similar to NES |
| `.hes` | HuC6280 (PC Engine) | 6 wavetable channels, slightly more than NES, still cheap |
| `.kss` | AY-3-8910 / SN76489 | 3-4 channel PSG square waves, extremely lightweight |
| `.sap` | Atari POKEY | 4 channels, simple waveforms |
| `.ay` | AY-3-8910 (ZX Spectrum) | 3-channel PSG, one of the simplest chips |

### Tracker Formats
MOD/S3M/XM/IT are **sample-based trackers**. They replay PCM samples at different pitches with envelopes. Handled by `libopenmpt` in FFmpeg. Simple files will be fine; heavily complex files with many channels and DSP effects may stutter.

| Format | Max Channels | Risk |
|--------|-------------|------|
| `.mod` | 4 (Amiga Paula) | Always fine, only 4 channels of sample playback |
| `.s3m` | 32 | Usually fine |
| `.xm` | 32 + some FM emulation | Complex files might struggle |
| `.it` | 64 + resonant filters + NNA | Complex IT files with many active voices and filter DSP are the most demanding tracker format |