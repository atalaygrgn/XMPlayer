# Building FFplay for Linux Handhelds

This guide explains how to compile a lightweight, optimized, static binary of `ffplay` for ARM64 Linux retro gaming handhelds (Allwinner H700, Rockchip RK3566, Anbernic RG35XX series, Powkiddy RGB30, TrimUI Smart Pro, etc.) across CFWs such as **muOS**, **Knulli**, **Rocknix**, and **dArkOS**.

---

## 1. Overview & Requirements

XMPlayer uses `ffplay` as a fast, lightweight video playback player as the alternative to `mpv`. To ensure maximum compatibility and performance across handheld CFWs, `ffplay` should be built with:
- **Target Architecture**: `aarch64` (ARM 64-bit Linux)
- **Static Linking**: `--enable-static --disable-shared` (prevents shared library mismatches across CFWs)
- **SDL2 Integration**: `--enable-sdl2` (used for video rendering and audio output)
- **Hardware Acceleration & Optimizations**: NEON SIMD instruction set, V4L2 M2M, and DRM/KMS support
- **Minimal Binary Footprint**: Disabling unneeded encoders and muxers (since `ffplay` is strictly a media player)

---

## 2. Environment Setup & Prerequisites

### Recommended Build Environments
1. **Ubuntu 20.04 / 22.04 LTS (x86_64 Cross-Compilation)** *(Recommended)*
2. **PortMaster Docker Build Environment**

### Installing Prerequisites (Ubuntu / Debian x86_64)

Install the AArch64 cross-compiler toolchain, build automation tools, and essential development headers:

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    bison \
    flex \
    gettext \
    git \
    make \
    ninja-build \
    pkg-config \
    nasm \
    yasm \
    cmake \
    libtool \
    autoconf \
    automake
```

---

## 3. Building Dependencies for AArch64

`ffplay` requires **SDL2** (and optionally **libass**, **freetype**, **zlib**) compiled for `aarch64-linux-gnu`.

### Step 3.1: Build Static SDL2 for AArch64

```bash
# Clone SDL2 source
git clone https://github.com/libsdl-org/SDL.git -b SDL2
cd SDL
mkdir build_arm64 && cd build_arm64

# Configure SDL2 for AArch64 Linux cross-compilation
CC=aarch64-linux-gnu-gcc \
CXX=aarch64-linux-gnu-g++ \
../configure \
    --host=aarch64-linux-gnu \
    --prefix=/tmp/sysroot_arm64 \
    --enable-static \
    --disable-shared \
    --enable-video-kmsdrm \
    --enable-video-x11 \
    --enable-alsa \
    --enable-pulseaudio=no

make -j$(nproc)
make install
cd ../..
```

---

## 4. Downloading & Configuring FFmpeg / FFplay

### Step 4.1: Download FFmpeg Source

```bash
git clone https://git.ffmpeg.org/ffmpeg.git -b n6.1.1 --depth 1
cd ffmpeg
```

### Step 4.2: Configure FFmpeg for FFplay Target

Run `./configure` tuned specifically for ARM64 handheld players:

```bash
PKG_CONFIG_PATH=/tmp/sysroot_arm64/lib/pkgconfig \
./configure \
    --prefix=/tmp/ffplay_build \
    --target-os=linux \
    --arch=aarch64 \
    --cpu=cortex-a53 \
    --enable-cross-compile \
    --cross-prefix=aarch64-linux-gnu- \
    --pkg-config=pkg-config \
    --pkg-config-flags="--static" \
    --enable-gpl \
    --enable-version3 \
    --enable-static \
    --disable-shared \
    --enable-ffplay \
    --enable-sdl2 \
    --enable-neon \
    --enable-v4l2-m2m \
    --enable-libdrm \
    --disable-doc \
    --disable-htmlpages \
    --disable-podpages \
    --disable-txtpages \
    --disable-encoders \
    --disable-muxers \
    --extra-cflags="-I/tmp/sysroot_arm64/include -O3 -pipe -ftree-vectorize" \
    --extra-ldflags="-L/tmp/sysroot_arm64/lib -static-libgcc -static-libstdc++"
```

---

## 5. Compiling & Stripping the Binary

### Step 5.1: Compile FFplay

```bash
make ffplay -j$(nproc)
```

### Step 5.2: Strip Debug Symbols

To shrink the executable size for handheld storage:

```bash
aarch64-linux-gnu-strip ffplay
```

Verify binary properties:

```bash
file ffplay
# Expected output:
# ffplay: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), dynamically linked / statically linked...
```

---

