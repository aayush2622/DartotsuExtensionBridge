#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FRAMEWORKS_DIR="${SCRIPT_DIR}/dartotsu_extension_bridge/Frameworks"
ZIP="${FRAMEWORKS_DIR}/ffmpeg-v1/DartotsuFfmpeg.xcframework.zip"

if [ ! -f "${ZIP}" ]; then
  echo "No DartotsuFfmpeg.xcframework.zip, iOS builds without FFmpeg"
  exit 0
fi

if [ -d "${FRAMEWORKS_DIR}/DartotsuFfmpeg.xcframework" ]; then
  exit 0
fi

/usr/bin/unzip -q -o "${ZIP}" -d "${FRAMEWORKS_DIR}"
test -d "${FRAMEWORKS_DIR}/DartotsuFfmpeg.xcframework"
echo "Prepared DartotsuFfmpeg.xcframework for dartotsu_extension_bridge"
