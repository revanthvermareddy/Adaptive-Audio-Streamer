const express = require("express");
const path = require("path");
const fs = require("fs");

const app = express();
const PORT = process.env.PORT || 3000;
const MEDIA_DIR = path.join(__dirname, "media");

// CORS — allow the player to fetch segments
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "Range");
  res.header("Access-Control-Expose-Headers", "Content-Length, Content-Range");
  next();
});

// Correct MIME types for streaming manifests and segments
const MIME_TYPES = {
  ".m3u8": "application/vnd.apple.mpegurl",
  ".ts": "video/mp2t",
  ".mpd": "application/dash+xml",
  ".m4s": "video/iso.segment",
  ".mp4": "video/mp4",
};

// Serve media files with correct content types
app.use(
  "/media",
  (req, res, next) => {
    const ext = path.extname(req.path).toLowerCase();
    if (MIME_TYPES[ext]) {
      res.type(MIME_TYPES[ext]);
    }
    // Disable caching during development so quality switches are observable
    res.header("Cache-Control", "no-cache, no-store, must-revalidate");
    next();
  },
  express.static(MEDIA_DIR)
);

// Serve the web player
app.use(express.static(path.join(__dirname, "public")));

// Discover available tracks by scanning the media directory
function discoverTracks() {
  if (!fs.existsSync(MEDIA_DIR)) return [];

  return fs
    .readdirSync(MEDIA_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => {
      const trackDir = path.join(MEDIA_DIR, d.name);
      const hlsManifest = path.join(trackDir, "hls", "master.m3u8");
      const dashManifest = path.join(trackDir, "dash", "manifest.mpd");
      return {
        name: d.name,
        hls: fs.existsSync(hlsManifest)
          ? `/media/${d.name}/hls/master.m3u8`
          : null,
        dash: fs.existsSync(dashManifest)
          ? `/media/${d.name}/dash/manifest.mpd`
          : null,
      };
    })
    .filter((t) => t.hls || t.dash);
}

// List all available tracks
app.get("/api/tracks", (req, res) => {
  res.json(discoverTracks());
});

app.listen(PORT, () => {
  const tracks = discoverTracks();
  console.log(`\n  🎵  Audio Streaming Server`);
  console.log(`  ─────────────────────────`);
  console.log(`  Player:  http://localhost:${PORT}`);
  console.log(`  Tracks:  http://localhost:${PORT}/api/tracks`);
  console.log(`  Found:   ${tracks.length} track(s)`);
  tracks.forEach((t) => console.log(`           • ${t.name}`));
  console.log();
});
