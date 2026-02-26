# plexamp-versions.sh

A Bash utility for discovering and downloading [Plexamp Headless](https://www.plex.tv/plexamp/) releases for Linux. It queries the official Plex API for the current latest version, then performs a parallel scan across a configurable version range to surface all available archived builds — outputting results to both the terminal and a local text file.

---

## Features

- **Official API lookup** — fetches the current latest version from `plexamp.plex.tv/headless/version.json` at startup
- **Dynamic version scanning** — probes a configurable `major.minor.patch` range instead of a hard-coded list, with all requests running in parallel for speed
- **Architecture detection** — reads `uname -m` and automatically prioritises `x86_64` (`headless`) or `arm64` builds; always falls back to the other arch if the primary isn't found
- **Direct download mode** — pass a version number as an argument to skip the scan and download that release immediately
- **Export to file** — all found versions are saved to `available_versions.txt` with version, arch, tag, and URL columns
- **Dependency check** — validates that `curl` and `jq` are installed before running, with platform-specific install instructions if they are missing
- **Colour-coded output** — official latest shown in green, archived releases dimmed; clear tagging in both terminal and file output

---

## Requirements

| Tool | Purpose |
|------|---------|
| `curl` | HTTP requests and downloads |
| `jq` | JSON parsing of the official API response |
| Bash 3.2+ | Compatible with macOS default shell and most Linux distros |

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

### Scan mode — discover all available versions

```bash
./plexamp-versions.sh
```

Contacts the official API, then scans the configured version range in parallel. Prints a formatted table to the terminal and saves results to `available_versions.txt`.

**Example output:**
```
╔══════════════════════════════════════════════════════════╗
║        Plexamp Headless — Version Discovery Tool         ║
╚══════════════════════════════════════════════════════════╝
  Detected architecture : x86_64 → prioritising headless builds
  Official latest        : v4.12.4

VERSION         ARCH         TAG                URL
──────────────────────────────────────────────────────────────────────────────────────────
v4.9.2          headless     ARCHIVED           https://plexamp.plex.tv/headless/Plexamp-Linux-headless-v4.9.2.tar.bz2
v4.11.2         headless     ARCHIVED           https://plexamp.plex.tv/headless/Plexamp-Linux-headless-v4.11.2.tar.bz2
v4.12.4         headless     OFFICIAL LATEST    https://plexamp.plex.tv/headless/Plexamp-Linux-headless-v4.12.4.tar.bz2
```

### Download mode — fetch a specific version

```bash
./plexamp-versions.sh 4.11.2
```

Skips the scan entirely. Checks the correct URL for your architecture (with fallback), then downloads the `.tar.bz2` to the current directory with a progress bar.

---

## Output file

After a scan, `available_versions.txt` is written (or overwritten) in the current directory:

```
# Plexamp Headless — Available Versions
# Generated: 2025-06-10 14:32 UTC
# Architecture priority: x86_64 (headless)
# ──────────────────────────────────────────────────────────────
VERSION         ARCH         TAG                URL
────────────────────────────────────────────────────────────────
v4.11.2         headless     ARCHIVED           https://...
v4.12.4         headless     OFFICIAL LATEST    https://...
```

---

## Configuration

The scan range is defined by six variables near the top of the script:

```bash
MAJOR_START=4; MAJOR_END=4      # Expand when a new major version releases
MINOR_START=9; MINOR_END=15     # Forward-looking minor range
PATCH_START=0; PATCH_END=5      # Patch ceiling (most releases are .0–.3)
```

Widen any of these values to extend the scan. The total number of probes is `(MAJOR range) × (MINOR range) × (PATCH range)` — all fired in parallel, so widening the range has minimal impact on wall-clock time.

---

## How it works

1. Checks for `curl` and `jq`; exits with install instructions if either is missing
2. Detects host architecture via `uname -m` and selects the appropriate tarball naming convention
3. Fetches `version.json` from the official Plex API to identify the current latest
4. If a version argument was passed, attempts to download it and exits
5. Otherwise, spawns a background subshell for every `major.minor.patch` combination in the configured range — each shell sends a HEAD request for both `headless` and `arm64` URLs
6. After all probes complete (`wait`), results are collected from a temp directory, sorted, printed as a table, and written to `available_versions.txt`

---

## License

MIT — use freely, modify as needed.
