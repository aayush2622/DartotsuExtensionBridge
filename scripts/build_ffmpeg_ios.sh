#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: build_ffmpeg_ios.sh <ios-arm64|ios-sim-arm64|host> [version]}"
VERSION="${2:-7.1.1}"
ROOT="$(pwd)"
OUT="$ROOT/dist"
mkdir -p "$OUT"

[ -f ffmpeg.tar.xz ] || curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz" -o ffmpeg.tar.xz
rm -rf "ffmpeg-$VERSION"
tar xf ffmpeg.tar.xz
cd "ffmpeg-$VERSION"

sed -i.bak 's/^int main(int argc, char \*\*argv)$/int dartotsu_ffmpeg_main(int argc, char **argv)/' fftools/ffmpeg.c
sed -i.bak '/^void term_init(void)$/{n;s/^{$/{\n    return;/;}' fftools/ffmpeg.c
grep -q '^int dartotsu_ffmpeg_main' fftools/ffmpeg.c
{
  printf 'int dartotsu_ffmpeg_main(int argc, char **argv);\nint dartotsu_ffmpeg_run(int argc, char **argv);\nvoid dartotsu_ffmpeg_cancel(void);\n'
  cat fftools/ffmpeg.c
} > fftools/ffmpeg.c.new
mv fftools/ffmpeg.c.new fftools/ffmpeg.c
cat "$ROOT/ios/FfmpegRuntime/dartotsu_ffmpeg.c" >> fftools/ffmpeg.c

COMMON=(
  --disable-everything --disable-autodetect --disable-doc --disable-debug
  --disable-ffplay --disable-ffprobe --disable-network --disable-avdevice
  --disable-postproc --enable-small --enable-ffmpeg --enable-pic
  --enable-static --disable-shared
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

case "$TARGET" in
  host)
    ./configure "${COMMON[@]}" --disable-x86asm
    ;;
  ios-arm64)
    SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=13.0"
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=arm64 \
      --target-os=darwin --cc="xcrun -sdk iphoneos clang" \
      --extra-cflags="$FLAGS" --extra-ldflags="$FLAGS"
    ;;
  ios-sim-arm64)
    SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    FLAGS="-arch arm64 -isysroot $SDK -mios-simulator-version-min=13.0"
    ./configure "${COMMON[@]}" --enable-cross-compile --arch=arm64 \
      --target-os=darwin --cc="xcrun -sdk iphonesimulator clang" \
      --extra-cflags="$FLAGS" --extra-ldflags="$FLAGS"
    ;;
  *)
    echo "unknown target $TARGET" >&2
    exit 1
    ;;
esac

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
make -k -j"$JOBS" || true

for lib in libavformat libavcodec libavfilter libavutil libswscale libswresample; do
  test -f "$lib/$lib.a"
done
test -f fftools/ffmpeg.o

OBJS=$(ls fftools/*.o | grep -v -e '/ffprobe' -e '/ffplay' -e '/opt_common_probe')
ar rcs "$OUT/libdartotsu_ffmpeg_tools-$TARGET.a" $OBJS

if [ "$TARGET" = host ]; then
  ls -la "$OUT"
  exit 0
fi

libtool -static -o "$OUT/libdartotsu_ffmpeg-$TARGET.a" \
  "$OUT/libdartotsu_ffmpeg_tools-$TARGET.a" \
  libavformat/libavformat.a libavcodec/libavcodec.a libavfilter/libavfilter.a \
  libavutil/libavutil.a libswscale/libswscale.a libswresample/libswresample.a
rm "$OUT/libdartotsu_ffmpeg_tools-$TARGET.a"
xcrun strip -S -x "$OUT/libdartotsu_ffmpeg-$TARGET.a"
ls -la "$OUT"
