#!/bin/bash
# =============================================================================
#  plexamp-versions.sh — Plexamp Headless Version Discovery & Downloader
# =============================================================================
#  Usage:
#    ./plexamp-versions.sh              # Scan and list all available versions
#    ./plexamp-versions.sh <version>    # Download a specific version directly
#                                       # e.g.: ./plexamp-versions.sh 4.11.2
# =============================================================================

BASE_URL="https://plexamp.plex.tv/headless"
VERSION_API="${BASE_URL}/version.json"
OUTPUT_FILE="available_versions.txt"

# --- Scan range configuration -------------------------------------------------
MAJOR_START=4; MAJOR_END=4         # Expand upper bound as new majors release
MINOR_START=0; MINOR_END=15        # Reasonable forward-looking range
PATCH_START=0; PATCH_END=5         # Most releases stay at .0–.3
# ------------------------------------------------------------------------------

# ANSI colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# =============================================================================
# 1. Dependency check
# =============================================================================
check_deps() {
    local missing=()
    for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing required dependencies: ${missing[*]}${RESET}"
        echo ""
        echo "  Install on Debian/Ubuntu:  sudo apt-get install ${missing[*]}"
        echo "  Install on Arch:           sudo pacman -S ${missing[*]}"
        echo "  Install on macOS:          brew install ${missing[*]}"
        exit 1
    fi
}

# =============================================================================
# 2. Architecture detection
# =============================================================================
detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64)          echo "headless" ;;   # standard x86 tarball name
        aarch64|arm64)   echo "arm64"    ;;
        armv7l|armhf)    echo "arm64"    ;;   # fallback to arm64 build
        *)
            echo -e "${YELLOW}⚠ Unknown architecture '${machine}', defaulting to x86_64 (headless).${RESET}" >&2
            echo "headless"
            ;;
    esac
}

# =============================================================================
# 3. Build URL for a given version + arch label
# =============================================================================
build_url() {
    local ver="$1" arch_label="$2"
    echo "${BASE_URL}/Plexamp-Linux-${arch_label}-v${ver}.tar.bz2"
}

# =============================================================================
# 4. Check if a URL is reachable (HEAD request, follow redirects)
# =============================================================================
url_exists() {
    local url="$1"
    local code
    code=$(curl -IsL -o /dev/null -w "%{http_code}" --max-time 6 "$url")
    [[ "$code" == "200" ]]
}

# =============================================================================
# 5. Probe a single version — returns "found" info or nothing
#    Outputs: "<version>|<arch_label>|<url>|<tag>"
# =============================================================================
probe_version() {
    local ver="$1" primary_arch="$2" official_ver="$3"
    local tag="ARCHIVED"

    [[ "$ver" == "$official_ver" ]] && tag="OFFICIAL LATEST"

    # Try primary arch first, then the other one
    local arches=("$primary_arch")
    [[ "$primary_arch" == "headless" ]] && arches+=("arm64") || arches+=("headless")

    for arch_label in "${arches[@]}"; do
        local url
        url=$(build_url "$ver" "$arch_label")
        if url_exists "$url"; then
            echo "${ver}|${arch_label}|${url}|${tag}"
            return
        fi
    done
}

# =============================================================================
# 6. Download a specific version
# =============================================================================
download_version() {
    local ver="$1" primary_arch="$2"
    local arches=("$primary_arch")
    [[ "$primary_arch" == "headless" ]] && arches+=("arm64") || arches+=("headless")

    echo -e "${CYAN}${BOLD}Attempting to download Plexamp v${ver}...${RESET}"
    echo ""

    for arch_label in "${arches[@]}"; do
        local url
        url=$(build_url "$ver" "$arch_label")
        echo -e "  ${DIM}Checking: ${url}${RESET}"
        if url_exists "$url"; then
            local filename="Plexamp-Linux-${arch_label}-v${ver}.tar.bz2"
            echo -e "  ${GREEN}✔ Found! Downloading → ${filename}${RESET}"
            echo ""
            curl -L --progress-bar -o "$filename" "$url"
            if [ $? -eq 0 ]; then
                echo -e "\n  ${GREEN}${BOLD}✔ Download complete: ${filename}${RESET}"
            else
                echo -e "\n  ${RED}✗ Download failed. Check your connection and retry.${RESET}"
                exit 1
            fi
            return 0
        fi
    done

    echo -e "  ${RED}✗ Version v${ver} not found for any known architecture.${RESET}"
    echo "    Tip: Run without arguments to see all currently available versions."
    exit 1
}

# =============================================================================
# 7. Print table header
# =============================================================================
print_header() {
    printf "\n"
    printf "${BOLD}%-15s %-12s %-18s %s${RESET}\n" "VERSION" "ARCH" "TAG" "URL"
    printf '%0.s─' {1..90}; printf '\n'
}

# =============================================================================
# 8. Print a single result row
# =============================================================================
print_row() {
    local ver="$1" arch="$2" url="$3" tag="$4"
    local colour="$DIM"
    [[ "$tag" == "OFFICIAL LATEST" ]] && colour="$GREEN"

    printf "${colour}%-15s %-12s %-18s %s${RESET}\n" "v${ver}" "$arch" "$tag" "$url"
}

# =============================================================================
# MAIN
# =============================================================================
check_deps

TARGET_VERSION="${1:-}"         # Optional CLI argument
PRIMARY_ARCH=$(detect_arch)
ARCH_DISPLAY=$(uname -m)

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║        Plexamp Headless — Version Discovery Tool         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e "  Detected architecture : ${CYAN}${ARCH_DISPLAY}${RESET} → prioritising ${CYAN}${PRIMARY_ARCH}${RESET} builds"
echo ""

# ── Fetch official latest ─────────────────────────────────────────────────────
echo -e "  ${DIM}Contacting official API...${RESET}"
OFFICIAL_JSON=$(curl -s --max-time 10 "$VERSION_API")

if [[ -z "$OFFICIAL_JSON" ]]; then
    echo -e "  ${YELLOW}⚠  Could not reach the official API. Continuing with scan only.${RESET}"
    OFFICIAL_VER="unknown"
    OFFICIAL_URL="N/A"
else
    OFFICIAL_VER=$(echo "$OFFICIAL_JSON" | jq -r '.latestVersion // "unknown"')
    OFFICIAL_URL=$(echo "$OFFICIAL_JSON" | jq -r '.updateUrl // "N/A"')
    echo -e "  Official latest        : ${GREEN}${BOLD}v${OFFICIAL_VER}${RESET}"
    echo -e "  Official URL           : ${DIM}${OFFICIAL_URL}${RESET}"
fi

# ── Download mode ─────────────────────────────────────────────────────────────
if [[ -n "$TARGET_VERSION" ]]; then
    echo ""
    download_version "$TARGET_VERSION" "$PRIMARY_ARCH"
    exit 0
fi

# ── Scan mode ─────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${DIM}Scanning versions ${MAJOR_START}.${MINOR_START}.${PATCH_START} → ${MAJOR_END}.${MINOR_END}.${PATCH_END} (parallel HEAD requests)...${RESET}"

FOUND_RESULTS=()
TMPDIR_RESULTS=$(mktemp -d)

# Launch all probes in parallel
for (( major=MAJOR_START; major<=MAJOR_END; major++ )); do
  for (( minor=MINOR_START; minor<=MINOR_END; minor++ )); do
    for (( patch=PATCH_START; patch<=PATCH_END; patch++ )); do
      ver="${major}.${minor}.${patch}"
      (
        result=$(probe_version "$ver" "$PRIMARY_ARCH" "$OFFICIAL_VER")
        if [[ -n "$result" ]]; then
            echo "$result" > "${TMPDIR_RESULTS}/${ver}.result"
        fi
      ) &
    done
  done
done

# Wait for all background jobs
wait

# Collect and sort results
FOUND_RESULTS=()
_sorted_results=$(
    find "${TMPDIR_RESULTS}" -name '*.result' -exec cat {} \; 2>/dev/null \
    | sort -t'.' -k1,1n -k2,2n -k3,3n
)
rm -rf "$TMPDIR_RESULTS"

while IFS= read -r line; do
    [[ -n "$line" ]] && FOUND_RESULTS+=("$line")
done <<< "$_sorted_results"

# ── Output table ──────────────────────────────────────────────────────────────
if [[ ${#FOUND_RESULTS[@]} -eq 0 ]]; then
    echo -e "\n  ${YELLOW}No versions found in the scanned range.${RESET}"
else
    print_header

    # Clear and write output file
    > "$OUTPUT_FILE"
    echo "# Plexamp Headless — Available Versions" >> "$OUTPUT_FILE"
    echo "# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')" >> "$OUTPUT_FILE"
    echo "# Architecture priority: ${ARCH_DISPLAY} (${PRIMARY_ARCH})" >> "$OUTPUT_FILE"
    echo "# ──────────────────────────────────────────────────────────────" >> "$OUTPUT_FILE"
    printf "%-15s %-12s %-18s %s\n" "VERSION" "ARCH" "TAG" "URL" >> "$OUTPUT_FILE"
    echo "────────────────────────────────────────────────────────────────" >> "$OUTPUT_FILE"

    for entry in "${FOUND_RESULTS[@]}"; do
        IFS='|' read -r ver arch url tag <<< "$entry"
        print_row "$ver" "$arch" "$tag" "$url"
        printf "%-15s %-12s %-18s %s\n" "v${ver}" "$arch" "$tag" "$url" >> "$OUTPUT_FILE"
    done

    printf '%0.s─' {1..90}; printf '\n'
    echo ""
    echo -e "  ${GREEN}${BOLD}Found ${#FOUND_RESULTS[@]} version(s).${RESET} Results saved to ${CYAN}${OUTPUT_FILE}${RESET}"
fi

echo ""
echo -e "  ${DIM}Tip: Run ${RESET}${BOLD}./plexamp-versions.sh <version>${RESET}${DIM} to download a specific version.${RESET}"
echo -e "  ${DIM}Example: ./plexamp-versions.sh ${OFFICIAL_VER}${RESET}"
echo ""
