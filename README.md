# plexamp-versions.sh

A comprehensive Bash utility for discovering, comparing, and downloading [Plexamp Headless](https://www.plex.tv/plexamp/) releases for Linux. It queries the official Plex API for the current latest version, performs parallel scans across configurable version ranges, and supports advanced features like batch downloads, checksum verification, and webhook notifications.

**Current Version:** 3.0.0

---

## Features

### Core Functionality
- **Official API lookup** — fetches the current latest version from `plexamp.plex.tv/headless/version.json`
- **Dynamic version scanning** — probes configurable `major.minor.patch` ranges with parallel requests
- **Architecture detection** — auto-detects `x86_64` (headless) or `arm64` builds with fallback
- **Export to file** — saves results to `available_versions.txt` with version, arch, tag, and URL columns

### Download Features
- **Direct download** — fetch specific versions with `./plexamp-versions.sh 4.12.4`
- **Batch downloads** — download multiple versions: `--download 4.11.2,4.12.0,4.12.4`
- **Checksum verification** — generate and display SHA256 hashes: `--verify`
- **Auto-extraction** — extract tarballs after download: `--extract`
- **Symlink management** — create `plexamp-latest.tar.bz2` symlink: `--symlink`

### Output & Formatting
- **Multiple formats** — table (default), JSON, CSV, Markdown: `-f json`
- **Quiet mode** — minimal output for scripting: `-q`
- **Verbose mode** — debug information: `-V`
- **No color** — disable ANSI codes: `--no-color`

### Advanced Features
- **Interactive mode** — browse and select versions: `-i`
- **Version comparison** — compare two versions side-by-side: `--compare 4.11.2,4.12.4`
- **Release notes** — fetch changelog from GitHub: `--release-notes 4.12.4`
- **Auto-detect range** — find available version range automatically: `--auto-range`
- **Webhook notifications** — send results to Discord/Slack: `--webhook URL`
- **Retry logic** — exponential backoff for failed requests: `--retries 3`

### Filtering & Control
- **Architecture filter** — `--arch headless|arm64|all`
- **Version range** — `--min-version`, `--max-version`, `--latest-n`
- **Throttling** — control concurrent requests: `--throttle 50`
- **Caching** — custom cache dir: `--cache-dir`, disable: `--no-cache`

---

## Requirements

| Tool | Purpose |
|------|---------|
| `curl` | HTTP requests and downloads |
| `jq` | JSON parsing of API responses |
| Bash 3.2+ | Compatible with macOS and Linux |

Install missing dependencies:

```bash
# Debian / Ubuntu
sudo apt-get install curl jq

# Arch Linux
sudo pacman -S curl jq

# macOS
brew install curl jq
```

---

## Usage

Make the script executable first:

```bash
chmod +x plexamp-versions.sh
```

### Basic Commands

```bash
# Show help
./plexamp-versions.sh --help

# Show version
./plexamp-versions.sh --version

# Scan for all available versions
./plexamp-versions.sh

# Download a specific version
./plexamp-versions.sh 4.12.4

# Download with verification and extraction
./plexamp-versions.sh --verify --extract 4.12.4
```

### Scan Mode

Discover all available versions with progress tracking:

```bash
./plexamp-versions.sh
```

**Example output:**
```
╔══════════════════════════════════════════════════════════╗
║        Plexamp Headless — Version Discovery Tool         ║
║                        v3.0.0                            ║
╚══════════════════════════════════════════════════════════╝
  Architecture: x86_64 → headless

  Contacting official API...
  Official latest: v4.12.4
  Scanning versions 4.0.0 → 4.20.10
  Max concurrent requests: 50

  Progress: [==============================] 100% (231/231)

VERSION         ARCH         TAG                URL
─────────────────────────────────────────────────────────────────
v4.12.2         headless     ARCHIVED           https://...
v4.12.3         headless     ARCHIVED           https://...
v4.12.4         headless     OFFICIAL LATEST    https://...
─────────────────────────────────────────────────────────────────

  Found 38 version(s)
  Results saved to available_versions.txt
```

### Download Mode

Fetch a specific version:

```bash
./plexamp-versions.sh 4.12.4
```

Batch download multiple versions:

```bash
./plexamp-versions.sh --download 4.11.2,4.12.0,4.12.4
```

Download with post-processing:

```bash
# Download with checksum, extraction, and symlink
./plexamp-versions.sh --verify --extract --symlink 4.12.4

# Download to specific directory
./plexamp-versions.sh --output-dir ~/Downloads 4.12.4
```

### Interactive Mode

Browse and select versions interactively:

```bash
./plexamp-versions.sh --interactive
```

**Example:**
```
Interactive Mode - Browse Available Versions
Select a version to download, or 'q' to quit

Scanning for available versions...

Found 38 versions

    1) v4.3.0
    2) v4.4.0
   ...
   38) v4.12.4
   39) Quit

Enter choice [1-39]:
```

### Comparison Mode

Compare two versions side-by-side:

```bash
./plexamp-versions.sh --compare 4.11.2,4.12.4
```

**Example output:**
```
Comparing v4.11.2 vs v4.12.4...

PROPERTY             v4.11.2              v4.12.4             
─────────────────────────────────────────────────────────────────
Version              v4.11.2              v4.12.4             
Newer Version                             v4.12.4             
Architectures        headless             headless            

Download URLs:
  v4.11.2 (headless): https://...
  v4.12.4 (headless): https://...
```

### Output Formats

Export results in different formats:

```bash
# JSON format
./plexamp-versions.sh -f json

# CSV format (great for scripting)
./plexamp-versions.sh -q -f csv

# Markdown format
./plexamp-versions.sh -f markdown
```

**JSON example:**
```json
{
  "generated": "2026-02-26T07:51:26Z",
  "architecture": "x86_64",
  "primary_arch": "headless",
  "official_latest": "4.12.4",
  "count": 38,
  "versions": [
    {"version": "4.12.2", "arch": "headless", "tag": "ARCHIVED", "url": "..."},
    {"version": "4.12.4", "arch": "headless", "tag": "OFFICIAL LATEST", "url": "..."}
  ]
}
```

### Auto-Detect Range

Automatically find the available version range:

```bash
./plexamp-versions.sh --auto-range
```

**Example:**
```
Auto-detecting version range...
  Probing for available versions...
  Found versions from 4.3 to 4.12
  Scan range set to: 4.3.0 → 4.12.10
```

### Webhook Notifications

Send scan results to Discord or Slack:

```bash
./plexamp-versions.sh --webhook https://discord.com/api/webhooks/...
```

---

## Output File

After a scan, `available_versions.txt` is written to the current directory (or cache directory):

```
# Plexamp Headless — Available Versions
# Generated: 2026-02-26 07:32 UTC
# Architecture priority: x86_64 (headless)
# ──────────────────────────────────────────────────────────────
VERSION         ARCH         TAG                URL
────────────────────────────────────────────────────────────────
v4.11.2         headless     ARCHIVED           https://...
v4.12.4         headless     OFFICIAL LATEST    https://...
```

---

## Configuration

### Script Variables

The scan range is defined by variables at the top of the script:

```bash
MAJOR_START=4; MAJOR_END=4      # Expand when new major releases
MINOR_START=0; MINOR_END=20     # Forward-looking minor range
PATCH_START=0; PATCH_END=10     # Patch ceiling (most releases are .0–.5)
```

### Environment Variables

All configuration can be overridden via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PLEXAMP_BASE_URL` | `https://plexamp.plex.tv/headless` | API base URL |
| `PLEXAMP_OUTPUT_FILE` | `available_versions.txt` | Output file name |
| `PLEXAMP_MAJOR_START` | `4` | Starting major version |
| `PLEXAMP_MAJOR_END` | `4` | Ending major version |
| `PLEXAMP_MINOR_START` | `0` | Starting minor version |
| `PLEXAMP_MINOR_END` | `20` | Ending minor version |
| `PLEXAMP_PATCH_START` | `0` | Starting patch version |
| `PLEXAMP_PATCH_END` | `10` | Ending patch version |
| `PLEXAMP_DOWNLOAD_DIR` | `.` | Default download directory |
| `PLEXAMP_CACHE_DIR` | `./.plexamp-cache` | Cache directory |
| `PLEXAMP_CACHE_TTL` | `3600` | Cache TTL in seconds |
| `PLEXAMP_THROTTLE` | `50` | Max concurrent requests |
| `PLEXAMP_RETRIES` | `3` | Max retry attempts |

**Example:**
```bash
PLEXAMP_MINOR_END=25 PLEXAMP_THROTTLE=100 ./plexamp-versions.sh
```

---

## Command Reference

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show script version |
| `-q, --quiet` | Quiet mode (results only) |
| `-V, --verbose` | Verbose mode (debug output) |
| `-i, --interactive` | Interactive TUI mode |
| `-f, --format FORMAT` | Output format: table, json, csv, markdown |
| `-o, --output-dir DIR` | Download directory |
| `-a, --arch ARCH` | Filter: headless, arm64, all |
| `--min-version VER` | Minimum version filter |
| `--max-version VER` | Maximum version filter |
| `--latest-n N` | Show only latest N versions |
| `--download VER` | Download version(s), comma-separated |
| `--verify` | Verify SHA256 checksum |
| `--extract` | Extract tarball after download |
| `--symlink` | Create plexamp-latest symlink |
| `--compare V1,V2` | Compare two versions |
| `--release-notes VER` | Fetch release notes |
| `--auto-range` | Auto-detect scan range |
| `--webhook URL` | Send results to webhook |
| `--retries N` | Max retry attempts |
| `--dry-run` | Show what would be done |
| `--no-color` | Disable colored output |
| `--cache-dir DIR` | Custom cache directory |
| `--no-cache` | Disable caching |
| `--throttle N` | Max concurrent requests |

---

## How It Works

1. **Dependency check** — validates `curl` and `jq` are installed
2. **Architecture detection** — reads `uname -m` for build selection
3. **API lookup** — fetches `version.json` for current latest
4. **Parallel scanning** — spawns background probes for each version
5. **Result collection** — gathers findings from temp directory
6. **Output** — displays table and writes to file
7. **Optional post-processing** — checksum, extract, symlink, webhook

---

## Examples

```bash
# Quick scan with JSON output
./plexamp-versions.sh -q -f json | jq '.versions | length'

# Download latest with all options
./plexamp-versions.sh --verify --extract --symlink 4.12.4

# Compare and download older version
./plexamp-versions.sh --compare 4.11.2,4.12.4
./plexamp-versions.sh 4.11.2

# Automated daily scan with webhook
PLEXAMP_CACHE_TTL=86400 ./plexamp-versions.sh --webhook https://hooks.slack.com/...

# Find specific architecture only
./plexamp-versions.sh --arch arm64 -q -f csv

# Scan with custom range
PLEXAMP_MAJOR_END=5 PLEXAMP_MINOR_END=5 ./plexamp-versions.sh
```

---

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success |
| `1` | General error (missing deps, network failure, version not found) |
| `2` | Invalid arguments |

---

## Troubleshooting

**No versions found:**
- Expand the scan range variables
- Check network connectivity
- Try `--no-cache` to bypass cached results

**Download fails:**
- Verify the version exists with a scan first
- Check disk space in download directory
- Try with `--retries 5` for unstable connections

**Interactive mode doesn't work:**
- Requires a terminal (doesn't work when piped)
- Run directly: `./plexamp-versions.sh --interactive`

---

## License

MIT — use freely, modify as needed.

---

## Project

GitHub: [Lunatic16/plexamp-headless-dl](https://github.com/Lunatic16/plexamp-headless-dl)
