# Building Minimal Audio-Only FFmpeg for Linux Handhelds

This guide explains how to compile a tiny, static, audio-only `ffmpeg` binary (`~2.82 MB`) for ARM64 Linux retro gaming handhelds (Allwinner H700, Rockchip RK3566, Anbernic RG35XX series, Powkiddy RGB30, TrimUI Smart Pro, etc.) across CFWs such as **muOS**, **Knulli**, **Rocknix**, and **dArkOS**.

---

## 1. Overview & Requirements

XMPlayer's audio backend (`ffmpeg_audio.lua` and `audio_worker.lua`) uses `ffmpeg` solely for:
- Probing track duration (`ffmpeg -i <file>`)
- Decoding audio tracks to raw 16-bit PCM (`-f s16le -acodec pcm_s16le -ar <rate> -ac 2 -`)
- Packetizing output into fixed 1024-sample chunks (`-af "asetnsamples=n=1024"`)
- Synthesizing VGM and chiptune formats (`.vgm`, `.vgz`, `.spc`, `.nsf`, `.nsfe`, `.gbs`, `.hes`, `.kss`) via `libgme`

Generic static `ffmpeg` builds bundle video encoders (`libx264`, `libx265`, `libvpx`, `libaom`, etc.), video decoders, subtitle/font libraries, and networking stacks (~48+ MB). By disabling everything except audio decoding, `libgme`, `zlib` (for `.vgz`), `pcm_s16le`, and required audio filters, the stripped binary shrinks to **~2.82 MB** with zero loss in audio playback functionality.

Key build targets:
- **Target Architecture**: `aarch64` (ARM 64-bit Linux)
- **Static Linking**: `aarch64-linux-musl` (`-static`) for zero glibc/shared-library dependencies across CFWs
- **External Libraries**: `zlib` (`.vgz` decompression and compressed tags) and `libgme` (`game-music-emu`)
- **Minimal Binary Footprint**: `--enable-small --disable-everything` with only required audio codecs/demuxers/filters enabled

---

## 2. Environment Setup & Prerequisites

### Recommended Build Environment
- **WSL Ubuntu (x86_64)** or any Linux x86_64 host with `curl`, `tar`, `make`, and `perl`

### Step 2.1: Download Toolchain & Sources

Using the standalone `aarch64-linux-musl-cross` toolchain requires no `sudo` or system package installation and produces compact static-pie binaries:

```bash
BASE="$HOME/build_ffmpeg"
SYSROOT="$BASE/sysroot"
mkdir -p "$BASE" "$SYSROOT/include/gme" "$SYSROOT/lib"
cd "$BASE"

# 1. Prebuilt aarch64-linux-musl cross-compiler
curl -fsSL -o tc.tgz https://musl.cc/aarch64-linux-musl-cross.tgz
tar -xzf tc.tgz && rm tc.tgz

# 2. zlib 1.3.1
curl -fsSL -o zlib.tar.gz https://github.com/madler/zlib/archive/refs/tags/v1.3.1.tar.gz
tar -xzf zlib.tar.gz && rm zlib.tar.gz

# 3. game-music-emu 0.6.3 (libgme)
curl -fsSL -o gme.tar.xz https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.3.tar.xz
tar -xf gme.tar.xz && rm gme.tar.xz

# 4. FFmpeg 7.1
curl -fsSL -o ffmpeg.tar.xz https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz
tar -xf ffmpeg.tar.xz && rm ffmpeg.tar.xz

export PATH="$BASE/aarch64-linux-musl-cross/bin:$PATH"
```

---

## 3. Building Dependencies for AArch64

### Step 3.1: Build Static `zlib`

```bash
cd "$BASE/zlib-1.3.1"
CHOST=aarch64-linux-musl \
CC=aarch64-linux-musl-gcc \
AR=aarch64-linux-musl-ar \
RANLIB=aarch64-linux-musl-ranlib \
CFLAGS="-Os" \
./configure --prefix="$SYSROOT" --static

make -j"$(nproc)"
make install
```

### Step 3.2: Build Static `libgme` (with `.vgz` Support)

Compile `game-music-emu` directly with `-DHAVE_ZLIB_H` (enables gzipped `.vgz` decompression) and `-DBLARGG_BUILD_DLL` (required by `blargg_source.h` macros), using the lightweight `GENS` YM2612 emulator:

```bash
cd "$BASE/game-music-emu-0.6.3/gme"
mkdir -p obj

for f in *.cpp; do
  if [ "$f" = "Ym2612_MAME.cpp" ] || [ "$f" = "Ym2612_Nuked.cpp" ]; then
    continue
  fi
  aarch64-linux-musl-g++ \
    -Os -DNDEBUG -DBLARGG_BUILD_DLL -DVGM_YM2612_GENS -DSPC_ISOLATED_ECHO_BUFFER -DHAVE_ZLIB_H \
    -I"$SYSROOT/include" -c "$f" -o "obj/${f%.cpp}.o"
done

aarch64-linux-musl-ar rcs "$SYSROOT/lib/libgme.a" obj/*.o
aarch64-linux-musl-ranlib "$SYSROOT/lib/libgme.a"
cp *.h "$SYSROOT/include/gme/"
```

### Step 3.3: Create Minimal `pkg-config` Wrapper

FFmpeg's `./configure` probes `libgme` and `zlib` via `pkg-config`. Create a lightweight cross-compile wrapper inside the toolchain `bin/` directory:

```bash
PKG_CFG="$BASE/aarch64-linux-musl-cross/bin/aarch64-linux-musl-pkg-config"
cat << EOF > "$PKG_CFG"
#!/bin/sh
case "\$*" in
  *--version*) echo "0.29.2"; exit 0 ;;
  *--exists*libgme*) exit 0 ;;
  *--cflags*libgme*) echo "-I$SYSROOT/include"; exit 0 ;;
  *--libs*libgme*) echo "-L$SYSROOT/lib -lgme -lz -lstdc++ -lm"; exit 0 ;;
  *--exists*zlib*) exit 0 ;;
  *--cflags*zlib*) echo "-I$SYSROOT/include"; exit 0 ;;
  *--libs*zlib*) echo "-L$SYSROOT/lib -lz"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$PKG_CFG"
```

---

## 4. Configuring & Compiling FFmpeg

### Step 4.1: Configure FFmpeg (Audio-Only + `libgme`)

```bash
cd "$BASE/ffmpeg-7.1"

./configure \
  --arch=aarch64 \
  --target-os=linux \
  --enable-cross-compile \
  --cross-prefix=aarch64-linux-musl- \
  --pkg-config="$PKG_CFG" \
  --enable-static \
  --disable-shared \
  --extra-cflags="-I$SYSROOT/include -Os" \
  --extra-ldflags="-L$SYSROOT/lib -static" \
  --extra-libs="-lgme -lz -lstdc++ -lm" \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-avdevice \
  --disable-swscale \
  --disable-postproc \
  --disable-network \
  --disable-autodetect \
  --enable-small \
  --disable-everything \
  --enable-gpl \
  --enable-libgme \
  --enable-zlib \
  --enable-protocol=file,pipe \
  --enable-demuxer=mp3,wav,flac,ogg,mov,aac,asf,aiff,ape,wv,mpc,mpc8,tta,dsf,iff,matroska,ac3,eac3,dts,libgme \
  --enable-parser=mpegaudio,flac,vorbis,opus,aac,ac3,dca \
  --enable-decoder=mp1,mp1float,mp2,mp2float,mp3,mp3float,flac,vorbis,opus,aac,aac_latm,alac,wmav1,wmav2,wmapro,wmalossless,ape,wavpack,mpc7,mpc8,tta,dsd_lsbf,dsd_msbf,dsd_lsbf_planar,dsd_msbf_planar,ac3,eac3,dca,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be,pcm_f64le,pcm_u8,pcm_s8,libgme \
  --enable-encoder=pcm_s16le \
  --enable-muxer=pcm_s16le \
  --enable-filter=asetnsamples,aresample,aformat,anull
```

> **Note:** In FFmpeg, the raw signed 16-bit little-endian muxer (`-f s16le`) is enabled via `--enable-muxer=pcm_s16le`.

### Step 4.2: Compile & Strip

```bash
make -j"$(nproc)" ffmpeg
aarch64-linux-gnu-strip --strip-all ffmpeg 2>/dev/null || aarch64-linux-musl-strip --strip-all ffmpeg
```

Verify the final binary:

```bash
file ffmpeg
ls -lh ffmpeg
# Expected output:
# ffmpeg: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), static-pie linked, stripped
# -rwxr-xr-x ... 2.9M ... ffmpeg
```

Copy the resulting `ffmpeg` binary to `.xmplayer/bin/ffmpeg` and rebuild the release packages with `make all`.
