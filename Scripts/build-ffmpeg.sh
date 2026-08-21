#!/bin/zsh
# Builds a minimal, statically-linked **LGPL** ffmpeg for macOS arm64 from a
# pinned FFmpeg source tarball. Output: Resources/ffmpeg (~3 MB).
#
# Only LGPL components are enabled: demuxers + mp4 muxer + mov_text/srt/ass/
# webvtt subtitle codecs + stream copy parsers. No GPL libs (no x264/x265).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="Resources/ffmpeg"
SUMS="Scripts/ffmpeg.sha256"
FF_VER="${FFMPEG_VERSION:-9.0}"
TARBALL="ffmpeg-${FF_VER}.tar.xz"
URL="https://ffmpeg.org/releases/${TARBALL}"

mkdir -p Resources

# Configure matches C symbols here — the mov_text codec's symbol is `movtext`
# (its public/runtime name remains "mov_text").
RECIPE=(
  --disable-everything --disable-autodetect --disable-network
  --disable-doc --disable-debug --disable-ffprobe --disable-ffplay
  --enable-small --pkg-config-flags=--static
  --enable-demuxer=mov,matroska,avi,flv,mpegts,asf,srt,webvtt,ass
  --enable-muxer=mp4,mov,matroska
  --enable-parser=h264,hevc,aac,ac3,eac3,dca,flac,opus,vorbis,vp8,vp9,av1,mpeg4video,mpegvideo
  --enable-decoder=srt,ass,webvtt,movtext,text,wrapped_avframe,pcm_s16le,pcm_s16be,pcm_f32le,pcm_u8
  --enable-encoder=movtext,h264_videotoolbox,hevc_videotoolbox,aac
  --enable-protocol=file
  --enable-videotoolbox
  --enable-indev=lavfi
  --enable-filter=testsrc,testsrc2,sine,anullsrc,null,format,scale,aresample,aformat
)

# Rebuild when binary missing/unverified OR recipe changed.
if [[ -f "$OUT" ]] \
   && shasum -a 256 -c "$SUMS" >/dev/null 2>&1 \
   && [[ -f Scripts/ffmpeg.recipe.sha256 ]] \
   && printf '%s\n' "${RECIPE[@]}" | shasum -a 256 -c Scripts/ffmpeg.recipe.sha256 >/dev/null 2>&1; then
  echo "ffmpeg already built and verified."
  exit 0
fi

BUILD="$(mktemp -d "${TMPDIR:-/tmp}vidp-ff.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

echo "Downloading $URL …"
curl -fsSL "$URL" -o "$BUILD/$TARBALL"

# Pin the source tarball on first fetch; enforce thereafter.
if [[ ! -f "Scripts/${TARBALL}.sha256" ]]; then
  ( cd "$BUILD" && shasum -a 256 "$TARBALL" ) > "Scripts/${TARBALL}.sha256"
elif ! ( cd "$BUILD" && shasum -a 256 -c "$ROOT/Scripts/${TARBALL}.sha256" ) >/dev/null 2>&1; then
  ( cd "$BUILD" && shasum -a 256 "$TARBALL" )
  echo "Tarball checksum mismatch vs Scripts/${TARBALL}.sha256"; exit 1
fi

tar -xf "$BUILD/$TARBALL" -C "$BUILD"
cd "$BUILD/ffmpeg-${FF_VER}"

./configure "${RECIPE[@]}"
make -j"$(sysctl -n hw.ncpu)" ffmpeg

cp ffmpeg "$ROOT/$OUT"
cd "$ROOT"
chmod +x "$OUT"
"$OUT" -version | head -1
shasum -a 256 "$OUT" > "$SUMS"
printf '%s\n' "${RECIPE[@]}" | shasum -a 256 > Scripts/ffmpeg.recipe.sha256
echo "OK — LGPL ffmpeg built; checksums pinned in $SUMS + ffmpeg.recipe.sha256"
