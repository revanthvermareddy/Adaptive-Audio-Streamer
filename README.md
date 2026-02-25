# 🎵 Adaptive Audio Streaming Demo

A hands-on demo of **HTTP-based adaptive bitrate streaming** using both **HLS** (HTTP Live Streaming) and **DASH** (Dynamic Adaptive Streaming over HTTP). Feed it an OGG file and get a fully working browser player with real-time quality switching.

---

## What Is Adaptive Bitrate Streaming?

Traditional audio download: one file, one quality, the whole thing must arrive before playback starts.

**Adaptive streaming** is different:

1. **Multiple encodings** — the same audio is encoded at several quality levels (bitrates).
2. **Chunked into segments** — each encoding is split into small segments (typically 2–10 seconds).
3. **Manifest file** — a playlist/manifest describes the available qualities and segment URLs.
4. **Client-driven switching** — the player monitors network speed and buffer health, then picks the highest quality that won't cause buffering. It can switch quality at every segment boundary — seamlessly, mid-playback.

```
                    ┌──────────────────────────────┐
                    │     Source: sample-audio.ogg  │
                    └──────────────┬───────────────┘
                                   │ ffmpeg transcode
                    ┌──────────────▼───────────────┐
                    │    3 Quality Variants         │
                    │  ┌──────┬───────┬──────────┐  │
                    │  │ 64k  │ 128k  │  256k    │  │
                    │  │ (low)│ (mid) │  (high)  │  │
                    │  └──┬───┴───┬───┴────┬─────┘  │
                    └─────┼───────┼────────┼────────┘
                          │       │        │
                    ┌─────▼───────▼────────▼────────┐
                    │   4-second audio segments      │
                    │   + manifest (m3u8 / mpd)      │
                    └──────────────┬─────────────────┘
                                   │ HTTP
                    ┌──────────────▼─────────────────┐
                    │   Browser Player               │
                    │   • Fetches manifest            │
                    │   • Downloads segments          │
                    │   • ABR: measures bandwidth     │
                    │   • Switches quality on the fly │
                    └────────────────────────────────┘
```

### HLS vs DASH

| Feature | HLS | DASH |
|---------|-----|------|
| Developed by | Apple | MPEG (open standard) |
| Manifest format | `.m3u8` (text playlist) | `.mpd` (XML) |
| Segment format | `.ts` (MPEG-TS) | `.m4s` (fMP4) |
| Browser support | Safari (native), everywhere via hls.js | Everywhere via dash.js |
| Latency | Typically higher (~15-30s live) | Can be lower (~3-5s live) |
| DRM | FairPlay | Widevine, PlayReady |

Both achieve the same goal: **smooth playback with adaptive quality**. This demo supports both so you can compare them side-by-side.

---

## Project Structure

```
adaptive-audio-streamer/
├── transcode.sh          # Reads audio-sources.txt, encodes → HLS + DASH
├── server.js             # Express server (serves media + player)
├── public/
│   └── index.html        # Web player with hls.js + dash.js + track selector
├── media/                # Generated media (after transcoding)
│   └── <track-name>/    # One directory per source file
│       ├── hls/
│       │   ├── master.m3u8
│       │   ├── low/      # 64 kbps variant
│       │   ├── mid/      # 128 kbps variant
│       │   └── high/     # 256 kbps variant
│       └── dash/
│           ├── manifest.mpd
│           └── *.m4s
├── audio-sources.txt     # Source audio file paths (one per line)
├── package.json
└── README.md
```

---

## Quick Start

### Prerequisites

- **Node.js** ≥ 18
- **ffmpeg** ≥ 5.0 (`brew install ffmpeg` on macOS)

### 1. Install dependencies

```bash
npm install
```

### 2. Add your audio sources

Edit `audio-sources.txt` with the paths to your audio files (one per line):

```txt
# Lines starting with # are comments
/path/to/track-one.ogg
/path/to/track-two.ogg
./local-file.ogg
```

### 3. Transcode

This reads `audio-sources.txt` and creates multi-bitrate HLS + DASH for each file:

```bash
npm run transcode
```

You can also pass files directly (bypassing `audio-sources.txt`):

```bash
bash transcode.sh /path/to/file1.ogg /path/to/file2.ogg
```

What happens under the hood:
- Each source file gets its own directory under `media/<track-name>/`
- The track name is derived from the filename (e.g., `my-song.ogg` → `my-song`)
- Each track is encoded to AAC at **3 quality tiers**: 64k, 128k, 256k
- **HLS**: master playlist + per-variant playlists with 4-second `.ts` segments
- **DASH**: MPD manifest with adaptation set and `.m4s` segments

### 4. Start the server

```bash
npm start
```

### 5. Open the player

Navigate to **http://localhost:3000** in your browser. Use the **Track** dropdown to switch between ingested audio files.

Or run both transcode + server in one command:

```bash
npm run demo
```

---

## Understanding the Player

The web player has two tabs — **HLS** and **DASH** — so you can switch between protocols and see how each handles adaptive streaming.

### What You'll See

- **Current Bitrate** — the quality tier currently being played (64k / 128k / 256k)
- **Quality Level** — numeric level index (0 = lowest, 2 = highest)
- **Buffer Length** — how many seconds of audio are buffered ahead
- **Event Log** — real-time log showing:
  - Manifest parsing
  - Segment downloads (with size)
  - **Quality switches** (the key event!) — watch for `[SWITCH]` entries

### Triggering Quality Switches

To observe adaptive switching in action:

1. **Network throttling** — Open DevTools → Network tab → Throttle to "Slow 3G" or "Fast 3G". The player will drop to a lower bitrate to avoid buffering, then recover when you remove throttling.
2. **Watch the event log** — You'll see `[SWITCH] Quality → Level X` entries as the ABR algorithm adapts.

---

## How the Ingestion Pipeline Works

```
audio-sources.txt          transcode.sh              media/
┌──────────────────┐      ┌────────────────┐      ┌─────────────────────┐
│ /path/to/song.ogg│─────▶│ For each file: │─────▶│ song/               │
│ /path/to/mix.ogg │      │  • Validate    │      │   ├── hls/          │
│ # comment ignored│      │  • Slugify name│      │   │   ├── master..  │
└──────────────────┘      │  • Encode 3    │      │   │   ├── low/      │
        OR                │    bitrate tiers│     │   │   ├── mid/      │
  CLI args:               │  • Segment into│      │   │   └── high/     │
  ./transcode.sh f1 f2    │    4s chunks   │      │   └── dash/         │
                          └────────────────┘      │       ├── manifest..│
                                                  │       └── *.m4s     │
                                                  ├── mix/              │
                                                  │   ├── hls/ ...      │
                                                  │   └── dash/ ...     │
                                                  └─────────────────────┘
```

The `transcode.sh` script:

1. **Reads sources** from `audio-sources.txt` (or CLI args) — comments and blank lines are ignored
2. **Validates** all files exist before transcoding starts
3. **Derives a track name** from each filename (e.g., `My Song.ogg` → `my-song`)
4. **Encodes each track** into HLS + DASH at 3 bitrate tiers

### HLS Generation

```bash
ffmpeg -i input.ogg -vn -c:a aac -b:a 128k -ar 44100 \
  -f hls -hls_time 4 -hls_list_size 0 \
  -hls_segment_filename "mid/seg_%03d.ts" \
  mid/playlist.m3u8
```

- `-f hls` — output HLS format
- `-hls_time 4` — 4-second segment duration
- `-hls_list_size 0` — include all segments in playlist (VOD mode)

The master playlist ties variants together:

```m3u8
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
low/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
mid/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=256000,CODECS="mp4a.40.2"
high/playlist.m3u8
```

### DASH Generation

```bash
ffmpeg -i input.ogg -vn \
  -map 0:a -c:a:0 aac -b:a:0 64k  -ar:0 22050 \
  -map 0:a -c:a:1 aac -b:a:1 128k -ar:1 44100 \
  -map 0:a -c:a:2 aac -b:a:2 256k -ar:2 44100 \
  -f dash -seg_duration 4 \
  -use_template 1 -use_timeline 1 \
  -adaptation_sets "id=0,streams=0,1,2" \
  manifest.mpd
```

- All variants are generated in a single ffmpeg invocation
- `-adaptation_sets` groups all streams into one adaptation set for seamless switching
- `-use_template` and `-use_timeline` produce efficient segment naming

---

## Key Concepts

### Adaptive Bitrate (ABR) Algorithm

The player continuously measures:
- **Download throughput** — how fast segments arrive
- **Buffer occupancy** — how many seconds of audio are buffered

It then selects the highest quality whose bitrate is comfortably below the measured throughput. If the buffer runs low, it drops quality immediately to prevent stalling.

### Segment Boundaries

Quality switches can only happen at **segment boundaries** (every 4 seconds in this demo). Shorter segments = faster adaptation but more HTTP requests. Longer segments = fewer requests but slower to react. 4 seconds is a common default.

### Manifest Types

- **HLS Master Playlist** (`master.m3u8`) — lists all quality variants with their bandwidths. The player picks one, fetches that variant's playlist, and starts downloading segments.
- **DASH MPD** (`manifest.mpd`) — XML document describing periods, adaptation sets, and representations. The player parses it to discover available qualities and segment URLs.

---

## Customizing

### Change bitrate tiers

Edit the `TIERS` array in `transcode.sh`:

```bash
TIERS=(
  "low:64k:22050"
  "mid:128k:44100"
  "high:256k:44100"
)
```

### Change segment duration

Modify the `-hls_time` and `-seg_duration` values in `transcode.sh`.

### Adding more audio files

Add paths to `audio-sources.txt` (one per line) and re-run `npm run transcode`. The server auto-discovers new tracks — just refresh the browser.

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Transcoding | ffmpeg (OGG → AAC, HLS/DASH segmenting) |
| Server | Express.js (static file serving with correct MIME types) |
| HLS Player | [hls.js](https://github.com/video-dev/hls.js) |
| DASH Player | [dash.js](https://github.com/Dash-Industry-Forum/dash.js) |
| UI | Vanilla HTML/CSS/JS |

---

## License

ISC
