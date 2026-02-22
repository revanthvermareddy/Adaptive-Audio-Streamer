#!/usr/bin/env bash
#
# transcode.sh — Encode audio files into HLS and DASH multi-bitrate streams.
#
# Usage:
#   ./transcode.sh                      # reads from audio-sources.txt
#   ./transcode.sh file1.ogg file2.ogg  # explicit files
#
# Sources file format (audio-sources.txt):
#   One file path per line. Blank lines and lines starting with # are ignored.
#   Paths can be absolute or relative to this script's directory.
#
# Output structure:
#   media/<track-name>/hls/   — HLS master playlist + variants + .ts segments
#   media/<track-name>/dash/  — DASH MPD manifest + .m4s segments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_FILE="$SCRIPT_DIR/audio-sources.txt"
MEDIA_ROOT="$SCRIPT_DIR/media"

# Bitrate tiers: label, audio bitrate, sample rate
TIERS=(
  "low:64k:22050"
  "mid:128k:44100"
  "high:256k:44100"
)

# ── Collect input files ──────────────────────────────────────────────────────
FILES=()

if [[ $# -gt 0 ]]; then
  # Files passed as CLI arguments
  FILES=("$@")
else
  # Read from audio-sources.txt
  if [[ ! -f "$SOURCES_FILE" ]]; then
    echo "Error: No files provided and $SOURCES_FILE not found."
    echo ""
    echo "Usage:"
    echo "  $0 file1.ogg file2.ogg        # pass files directly"
    echo "  echo '/path/to/audio.ogg' > audio-sources.txt && $0   # use sources file"
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue
    FILES+=("$line")
  done < "$SOURCES_FILE"
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Error: No audio files to process."
  echo "Add file paths to audio-sources.txt (one per line) or pass them as arguments."
  exit 1
fi

# ── Validate all files exist before starting ─────────────────────────────────
echo "==> Validating ${#FILES[@]} source file(s)..."
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "    ✗ Not found: $f"
    exit 1
  fi
  echo "    ✓ $f"
done
echo ""

# ── Derive a URL-safe track name from a filename ────────────────────────────
slugify() {
  local name
  name="$(basename "$1")"              # strip directory
  name="${name%.*}"                     # strip extension
  echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# ── Transcode a single file ─────────────────────────────────────────────────
transcode_file() {
  local INPUT="$1"
  local TRACK
  TRACK="$(slugify "$INPUT")"
  local TRACK_DIR="$MEDIA_ROOT/$TRACK"
  local HLS_DIR="$TRACK_DIR/hls"
  local DASH_DIR="$TRACK_DIR/dash"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Track: $TRACK"
  echo "  Source: $INPUT"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  rm -rf "$HLS_DIR" "$DASH_DIR"
  mkdir -p "$HLS_DIR" "$DASH_DIR"

  # ── HLS ──
  echo "  [HLS] Generating streams..."

  local MASTER_PLAYLIST="$HLS_DIR/master.m3u8"
  echo "#EXTM3U" > "$MASTER_PLAYLIST"

  for tier in "${TIERS[@]}"; do
    IFS=: read -r label bitrate samplerate <<< "$tier"
    echo "    [$label] ${bitrate}bps @ ${samplerate}Hz"

    local TIER_DIR="$HLS_DIR/$label"
    mkdir -p "$TIER_DIR"

    ffmpeg -y -i "$INPUT" \
      -vn \
      -c:a aac -b:a "$bitrate" -ar "$samplerate" -ac 2 \
      -f hls \
      -hls_time 4 \
      -hls_list_size 0 \
      -hls_segment_filename "$TIER_DIR/seg_%03d.ts" \
      "$TIER_DIR/playlist.m3u8" \
      -loglevel warning

    local BW
    BW=$(echo "$bitrate" | sed 's/k//' | awk '{printf "%d", $1 * 1000}')
    echo "#EXT-X-STREAM-INF:BANDWIDTH=${BW},CODECS=\"mp4a.40.2\"" >> "$MASTER_PLAYLIST"
    echo "${label}/playlist.m3u8" >> "$MASTER_PLAYLIST"
  done

  # ── DASH ──
  echo "  [DASH] Generating streams..."

  local DASH_ARGS=(-y -i "$INPUT" -vn)
  local IDX=0

  for tier in "${TIERS[@]}"; do
    IFS=: read -r label bitrate samplerate <<< "$tier"
    echo "    [$label] ${bitrate}bps @ ${samplerate}Hz"
    DASH_ARGS+=(-map "0:a" -c:a:"$IDX" aac -b:a:"$IDX" "$bitrate" -ar:"$IDX" "$samplerate" -ac:"$IDX" 2)
    IDX=$((IDX + 1))
  done

  DASH_ARGS+=(
    -f dash
    -seg_duration 4
    -use_template 1
    -use_timeline 1
    -init_seg_name 'init-stream$RepresentationID$.m4s'
    -media_seg_name 'chunk-stream$RepresentationID$-$Number%05d$.m4s'
    -adaptation_sets "id=0,streams=0,1,2"
    "$DASH_DIR/manifest.mpd"
  )

  ffmpeg "${DASH_ARGS[@]}" -loglevel warning

  echo "  ✓ Done → $TRACK_DIR"
  echo ""
}

# ── Process all files ────────────────────────────────────────────────────────
echo "==> Transcoding ${#FILES[@]} file(s) into $MEDIA_ROOT"
echo ""

for f in "${FILES[@]}"; do
  transcode_file "$f"
done

echo "==> All tracks ready in $MEDIA_ROOT"
