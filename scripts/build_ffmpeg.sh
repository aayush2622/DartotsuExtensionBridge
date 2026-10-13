#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: build_ffmpeg.sh <linux-x64|linux-arm64|windows-x64|windows-arm64|android-arm64|macos-arm64|macos-x64> [version]}"
VERSION="${2:-7.1.1}"
OUT="$(pwd)/dist"
mkdir -p "$OUT"

curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz" -o ffmpeg.tar.xz
tar xf ffmpeg.tar.xz
cd "ffmpeg-$VERSION"

COMMON=(
  --disable-everything --disable-autodetect --disable-doc --disable-debug
  --disable-ffplay --disable-ffprobe --disable-network --disable-avdevice
  --disable-postproc --disable-x86asm --enable-small --enable-ffmpeg
  --enable-avfilter --enable-swscale --enable-swresample
  --enable-filter=null,anull,format,aformat,scale,aresample,copy,setpts,asetpts,trim,atrim
  --enable-protocol=file,crypto,data,pipe
  --enable-demuxer=hls,mpegts,mov,matroska,mp3,aac,ac3,eac3,flac,ogg,webvtt,srt,ass
  --enable-muxer=mp4,matroska,webvtt,srt
  --enable-parser=h264,hevc,aac,aac_latm,ac3,vp9,av1,opus,vorbis,mpegaudio,flac
  --enable-bsf=aac_adtstoasc,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,vp9_superframe
  --enable-decoder=h264,hevc,vp9,av1,aac,aac_latm,ac3,eac3,mp3,opus,vorbis,flac,ass,srt,webvtt,subrip
  --enable-encoder=mov_text,webvtt,srt
)

EXT=""
case "$TARGET" in
  linux-x64)
    ./configure "${COMMON[@]}" --extra-ldflags=-static
    STRIP=strip
    ;;
  linux-arm64)
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=aarch64 \
      --target-os=linux --cross-prefix=aarch64-linux-gnu- --extra-ldflags=-static
    STRIP=aarch64-linux-gnu-strip
    ;;
  windows-x64)
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=x86_64 \
      --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32- --extra-ldflags=-static
    STRIP=x86_64-w64-mingw32-strip
    EXT=".exe"
    ;;
  windows-arm64)
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=aarch64 \
      --target-os=mingw32 --cc=aarch64-w64-mingw32-gcc --extra-ldflags=-static
    STRIP=aarch64-w64-mingw32-strip
    EXT=".exe"
    ;;
  android-arm64)
    BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=aarch64 \
      --target-os=android --cc="$BIN/aarch64-linux-android24-clang" \
      --strip="$BIN/llvm-strip" --ar="$BIN/llvm-ar" --nm="$BIN/llvm-nm" \
      --ranlib="$BIN/llvm-ranlib"
    STRIP="$BIN/llvm-strip"
    ;;
  macos-arm64)
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=arm64 \
      --target-os=darwin --extra-cflags="-arch arm64" --extra-ldflags="-arch arm64"
    STRIP=strip
    ;;
  macos-x64)
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=x86_64 \
      --target-os=darwin --extra-cflags="-arch x86_64" --extra-ldflags="-arch x86_64"
    STRIP=strip
    ;;
  *)
    echo "unknown target $TARGET" >&2
    exit 1
    ;;
esac

make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
"$STRIP" "ffmpeg$EXT" -o "$OUT/ffmpeg-$TARGET$EXT"
ls -la "$OUT"
