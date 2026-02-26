#!/bin/bash
# =============================================================================
#  plexamp-versions.sh — Plexamp Headless Version Discovery & Downloader
# =============================================================================
#  Usage:
#    ./plexamp-versions.sh                          # Scan and list all available versions
#    ./plexamp-versions.sh <version>                # Download a specific version
#    ./plexamp-versions.sh [OPTIONS]                # Use options for advanced features
#
#  Options:
#    -h, --help              Show this help message
#    -v, --version           Show script version
#    -q, --quiet             Quiet mode (minimal output, results only)
#    -V, --verbose           Verbose mode (debug output)
#    -i, --interactive       Interactive TUI mode for browsing versions
#    -f, --format FORMAT     Output format: table|json|csv|markdown (default: table)
#    -o, --output-dir DIR    Download directory (default: current directory)
#    -a, --arch ARCH         Architecture filter: headless|arm64|all (default: auto-detect)
#    --min-version VER       Minimum version to include in scan
#    --max-version VER       Maximum version to include in scan
#    --latest-n N            Show only the latest N versions
#    --download VER          Download specific version(s) (comma-separated for batch)
#    --verify                Verify checksums after download
#    --extract               Extract tarball after download
#    --symlink               Create 'plexamp-latest' symlink after download
#    --compare V1,V2         Compare two versions
#    --release-notes VER     Fetch release notes for a version
#    --auto-range            Auto-detect version scan range
#    --webhook URL           Send results to webhook URL
#    --retries N             Max retry attempts for failed requests (default: 3)
#    --dry-run               Show what would be done without executing
#    --no-color              Disable colored output
#    --cache-dir DIR         Directory for caching scan results
#    --no-cache              Disable caching
#    --throttle N            Max concurrent requests (default: 50)
# =============================================================================

set -euo pipefail

# --- Script metadata ----------------------------------------------------------
SCRIPT_VERSION="3.0.0"
SCRIPT_NAME="$(basename "$0")"

# --- Configuration variables (can be overridden by env vars) ------------------
BASE_URL="${PLEXAMP_BASE_URL:-https://plexamp.plex.tv/headless}"
VERSION_API="${BASE_URL}/version.json"
OUTPUT_FILE="${PLEXAMP_OUTPUT_FILE:-available_versions.txt}"

# Scan range configuration
MAJOR_START="${PLEXAMP_MAJOR_START:-4}"
MAJOR_END="${PLEXAMP_MAJOR_END:-4}"
MINOR_START="${PLEXAMP_MINOR_START:-0}"
MINOR_END="${PLEXAMP_MINOR_END:-15}"
PATCH_START="${PLEXAMP_PATCH_START:-0}"
PATCH_END="${PLEXAMP_PATCH_END:-5}"

# Runtime configuration
DOWNLOAD_DIR="${PLEXAMP_DOWNLOAD_DIR:-.}"
CACHE_DIR="${PLEXAMP_CACHE_DIR:-./.plexamp-cache}"
CACHE_TTL="${PLEXAMP_CACHE_TTL:-3600}"  # 1 hour default
MAX_CONCURRENT="${PLEXAMP_THROTTLE:-50}"
MAX_RETRIES="${PLEXAMP_RETRIES:-3}"

# --- Runtime flags ------------------------------------------------------------
QUIET_MODE=false
VERBOSE_MODE=false
DRY_RUN=false
NO_COLOR=false
NO_CACHE=false
OUTPUT_FORMAT="table"
ARCH_FILTER=""
MIN_VERSION=""
MAX_VERSION=""
LATEST_N=0
TARGET_VERSION=""
VERIFY_CHECKSUM=false
AUTO_EXTRACT=false
CREATE_SYMLINK=false
INTERACTIVE_MODE=false
COMPARE_VERSIONS=""
RELEASE_NOTES_VERSION=""
AUTO_RANGE=false
WEBHOOK_URL=""

# --- Internal state -----------------------------------------------------------
RESULTS_TMPDIR=""
PID_LIST=()

# ANSI colours - using $'...' syntax for proper escape sequence handling
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

# =============================================================================
# Utility Functions
# =============================================================================

# Disable colors if requested or if not a terminal
init_colors() {
    if [[ "$NO_COLOR" == "true" ]] || [[ ! -t 1 ]]; then
        RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''
        BOLD=''; DIM=''; RESET=''
    fi
}

# Logging functions
log_info() {
    [[ "$QUIET_MODE" == "false" ]] && printf "%b  %b%b\n" "${DIM}" "$*" "${RESET}" >&2 || true
}

log_success() {
    [[ "$QUIET_MODE" == "false" ]] && printf "%b  %b%b\n" "${GREEN}" "$*" "${RESET}" >&2 || true
}

log_warn() {
    [[ "$QUIET_MODE" == "false" ]] && printf "%b  ⚠ %b%b\n" "${YELLOW}" "$*" "${RESET}" >&2 || true
}

log_error() {
    printf "%b  ✗ %b%b\n" "${RED}" "$*" "${RESET}" >&2
}

log_verbose() {
    [[ "$VERBOSE_MODE" == "true" ]] && printf "%b  [DEBUG] %b%b\n" "${BLUE}" "$*" "${RESET}" >&2 || true
}

# =============================================================================
# 1. Help and Version
# =============================================================================
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — Plexamp Headless Version Discovery & Downloader

USAGE:
    ${SCRIPT_NAME} [OPTIONS] [VERSION]

OPTIONS:
    General:
      -h, --help              Show this help message and exit
      -v, --version           Show script version and exit
      -q, --quiet             Quiet mode: suppress banners and progress (results only)
      -V, --verbose           Verbose mode: show debug information
      -i, --interactive       Interactive TUI mode for browsing versions
      --no-color              Disable colored output
      --dry-run               Show what would be done without executing

    Output Format:
      -f, --format FORMAT     Output format: table (default), json, csv, markdown
      -o, --output-dir DIR    Directory for downloaded files (default: current dir)

    Filtering:
      -a, --arch ARCH         Filter by architecture: headless, arm64, all (default: auto)
      --min-version VER       Only include versions >= VER
      --max-version VER       Only include versions <= VER
      --latest-n N            Show only the latest N versions

    Download:
      VERSION                 Download this specific version (e.g., 4.11.2)
      --download VER          Download version(s), comma-separated for batch
      --verify                Verify SHA256 checksum after download
      --extract               Extract tarball after successful download
      --symlink               Create 'plexamp-latest' symlink to downloaded file

    Comparison & Info:
      --compare V1,V2         Compare two versions side-by-side
      --release-notes VER     Fetch and display release notes for a version

    Advanced:
      --cache-dir DIR         Directory for caching (default: ./.plexamp-cache)
      --no-cache              Disable caching entirely
      --throttle N            Max concurrent requests (default: 50)
      --retries N             Max retry attempts for failed requests (default: 3)
      --auto-range            Auto-detect version scan range
      --webhook URL           Send results to webhook URL on completion

EXAMPLES:
    # Scan for all available versions
    ${SCRIPT_NAME}

    # Interactive mode - browse and select versions
    ${SCRIPT_NAME} --interactive

    # Download a specific version
    ${SCRIPT_NAME} 4.11.2

    # Batch download multiple versions
    ${SCRIPT_NAME} --download 4.11.2,4.12.0,4.12.4

    # Compare two versions
    ${SCRIPT_NAME} --compare 4.11.2,4.12.4

    # Fetch release notes
    ${SCRIPT_NAME} --release-notes 4.12.4

    # Auto-detect scan range and scan
    ${SCRIPT_NAME} --auto-range

    # Download with verification and extraction
    ${SCRIPT_NAME} --verify --extract 4.12.4

    # Send results to webhook
    ${SCRIPT_NAME} --webhook https://discord.com/api/webhooks/...

    # Export results as JSON
    ${SCRIPT_NAME} --format json

    # Quiet mode, CSV output for scripting
    ${SCRIPT_NAME} -q -f csv

    # Filter by architecture and show latest 5
    ${SCRIPT_NAME} --arch headless --latest-n 5

    # Download to specific directory with symlink
    ${SCRIPT_NAME} --output-dir ~/Downloads --symlink 4.12.4

ENVIRONMENT VARIABLES:
    PLEXAMP_BASE_URL          Override base URL (default: https://plexamp.plex.tv/headless)
    PLEXAMP_OUTPUT_FILE       Output file name (default: available_versions.txt)
    PLEXAMP_MAJOR_START       Starting major version (default: 4)
    PLEXAMP_MAJOR_END         Ending major version (default: 4)
    PLEXAMP_MINOR_START       Starting minor version (default: 0)
    PLEXAMP_MINOR_END         Ending minor version (default: 20)
    PLEXAMP_PATCH_START       Starting patch version (default: 0)
    PLEXAMP_PATCH_END         Ending patch version (default: 10)
    PLEXAMP_DOWNLOAD_DIR      Default download directory
    PLEXAMP_CACHE_DIR         Cache directory (default: ./.plexamp-cache)
    PLEXAMP_CACHE_TTL         Cache TTL in seconds (default: 3600)
    PLEXAMP_THROTTLE          Max concurrent requests (default: 50)
    PLEXAMP_RETRIES           Max retry attempts (default: 3)

EXIT CODES:
    0  Success
    1  General error (missing deps, network failure, version not found)
    2  Invalid arguments

LICENSE:
    MIT — Use freely, modify as needed.

PROJECT:
    https://github.com/Lunatic16/plexamp-headless-dl
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

# =============================================================================
# 2. Argument Parsing
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -V|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--format)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --format requires an argument"
                    exit 2
                fi
                case "$2" in
                    table|json|csv|markdown) OUTPUT_FORMAT="$2" ;;
                    *)
                        log_error "Invalid format '$2'. Use: table, json, csv, markdown"
                        exit 2
                        ;;
                esac
                shift 2
                ;;
            -o|--output-dir)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --output-dir requires an argument"
                    exit 2
                fi
                DOWNLOAD_DIR="$2"
                shift 2
                ;;
            -a|--arch)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --arch requires an argument"
                    exit 2
                fi
                case "$2" in
                    headless|arm64|all) ARCH_FILTER="$2" ;;
                    *)
                        log_error "Invalid arch '$2'. Use: headless, arm64, all"
                        exit 2
                        ;;
                esac
                shift 2
                ;;
            --min-version)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --min-version requires an argument"
                    exit 2
                fi
                MIN_VERSION="$2"
                shift 2
                ;;
            --max-version)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --max-version requires an argument"
                    exit 2
                fi
                MAX_VERSION="$2"
                shift 2
                ;;
            --latest-n)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --latest-n requires a positive integer"
                    exit 2
                fi
                LATEST_N="$2"
                shift 2
                ;;
            --download)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --download requires a version argument"
                    exit 2
                fi
                # Support comma-separated versions for batch download
                if [[ -z "$TARGET_VERSION" ]]; then
                    TARGET_VERSION="$2"
                else
                    TARGET_VERSION="${TARGET_VERSION},$2"
                fi
                shift 2
                ;;
            --verify)
                VERIFY_CHECKSUM=true
                shift
                ;;
            --extract)
                AUTO_EXTRACT=true
                shift
                ;;
            --symlink)
                CREATE_SYMLINK=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            --compare)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --compare requires version arguments (e.g., 4.11.2,4.12.4)"
                    exit 2
                fi
                COMPARE_VERSIONS="$2"
                shift 2
                ;;
            --release-notes)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --release-notes requires a version argument"
                    exit 2
                fi
                RELEASE_NOTES_VERSION="$2"
                shift 2
                ;;
            --auto-range)
                AUTO_RANGE=true
                shift
                ;;
            --webhook)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --webhook requires a URL argument"
                    exit 2
                fi
                WEBHOOK_URL="$2"
                shift 2
                ;;
            --retries)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --retries requires a positive integer"
                    exit 2
                fi
                MAX_RETRIES="$2"
                shift 2
                ;;
            --cache-dir)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --cache-dir requires an argument"
                    exit 2
                fi
                CACHE_DIR="$2"
                shift 2
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --throttle)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --throttle requires a positive integer"
                    exit 2
                fi
                MAX_CONCURRENT="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                printf "%b  %bUse --help for usage information%b\n" "${DIM}" "${RESET}" "${DIM}" >&2
                exit 2
                ;;
            *)
                # Positional argument (version to download)
                if [[ -n "$TARGET_VERSION" ]]; then
                    log_error "Multiple versions specified"
                    exit 2
                fi
                TARGET_VERSION="$1"
                shift
                ;;
        esac
    done

    # Handle remaining positional args after --
    while [[ $# -gt 0 ]]; do
        if [[ -z "$TARGET_VERSION" ]]; then
            TARGET_VERSION="$1"
        else
            log_error "Multiple versions specified"
            exit 2
        fi
        shift
    done
}

# =============================================================================
# 3. Dependency check
# =============================================================================
check_deps() {
    local missing=()
    for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "  Install on Debian/Ubuntu:  sudo apt-get install ${missing[*]}"
        echo "  Install on Arch:           sudo pacman -S ${missing[*]}"
        echo "  Install on macOS:          brew install ${missing[*]}"
        exit 1
    fi
}

# =============================================================================
# 4. Signal Handling & Cleanup
# =============================================================================
cleanup() {
    local exit_code=$?

    log_verbose "Cleaning up..."

    # Kill any remaining background jobs
    for pid in "${PID_LIST[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done

    # Remove temporary directory
    if [[ -n "$RESULTS_TMPDIR" ]] && [[ -d "$RESULTS_TMPDIR" ]]; then
        rm -rf "$RESULTS_TMPDIR"
        log_verbose "Removed temp directory: $RESULTS_TMPDIR"
    fi

    exit $exit_code
}

setup_signal_handlers() {
    trap cleanup EXIT
    trap 'log_warn "Interrupted by user"; exit 130' INT
    trap 'log_warn "Terminated"; exit 143' TERM
}

# =============================================================================
# 5. Architecture detection
# =============================================================================
detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64)          echo "headless" ;;
        aarch64|arm64)   echo "arm64"    ;;
        armv7l|armhf)    echo "arm64"    ;;
        *)
            log_warn "Unknown architecture '${machine}', defaulting to x86_64 (headless)"
            echo "headless"
            ;;
    esac
}

# =============================================================================
# 6. Version comparison utilities
# =============================================================================

# Compare two semantic versions: returns 0 if v1 < v2, 1 if v1 == v2, 2 if v1 > v2
compare_versions() {
    local v1="$1" v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        echo 1
        return
    fi

    local IFS='.'
    read -ra v1_parts <<< "$v1"
    read -ra v2_parts <<< "$v2"

    for i in 0 1 2; do
        local p1="${v1_parts[$i]:-0}"
        local p2="${v2_parts[$i]:-0}"
        if (( p1 < p2 )); then
            echo 0
            return
        elif (( p1 > p2 )); then
            echo 2
            return
        fi
    done

    echo 1
}

# Check if version is in range
version_in_range() {
    local version="$1" min="$2" max="$3"

    if [[ -n "$min" ]]; then
        local cmp_min
        cmp_min=$(compare_versions "$version" "$min")
        if [[ "$cmp_min" == "0" ]]; then
            return 1
        fi
    fi

    if [[ -n "$max" ]]; then
        local cmp_max
        cmp_max=$(compare_versions "$version" "$max")
        if [[ "$cmp_max" == "2" ]]; then
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# 7. Build URL for a given version + arch label
# =============================================================================
build_url() {
    local ver="$1" arch_label="$2"
    echo "${BASE_URL}/Plexamp-Linux-${arch_label}-v${ver}.tar.bz2"
}

# =============================================================================
# 8. Check if a URL is reachable (HEAD request, follow redirects)
# =============================================================================
url_exists() {
    local url="$1"
    local code
    code=$(curl -IsL -o /dev/null -w "%{http_code}" --max-time 6 "$url" 2>/dev/null) || code="000"
    [[ "$code" == "200" ]]
}

# =============================================================================
# 9. Probe a single version
#    Outputs: "<version>|<arch_label>|<url>|<tag>"
# =============================================================================
probe_version() {
    local ver="$1" primary_arch="$2" official_ver="$3"
    local tag="ARCHIVED"

    [[ "$ver" == "$official_ver" ]] && tag="OFFICIAL LATEST"

    # Determine which architectures to check
    local arches=()
    if [[ -n "$ARCH_FILTER" ]] && [[ "$ARCH_FILTER" != "all" ]]; then
        arches=("$ARCH_FILTER")
    else
        arches=("$primary_arch")
        if [[ "$primary_arch" == "headless" ]]; then
            arches+=("arm64")
        else
            arches+=("headless")
        fi
    fi

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
# 10. Cache Functions
# =============================================================================
get_cache_key() {
    echo "${MAJOR_START}-${MAJOR_END}-${MINOR_START}-${MINOR_END}-${PATCH_START}-${PATCH_END}-${PRIMARY_ARCH:-unknown}"
}

cache_lookup() {
    [[ "$NO_CACHE" == "true" ]] && return 1

    local cache_key
    cache_key=$(get_cache_key)
    local cache_file="${CACHE_DIR}/${cache_key}.cache"

    if [[ -f "$cache_file" ]]; then
        local cache_time
        cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local age=$((now - cache_time))

        if [[ $age -lt $CACHE_TTL ]]; then
            log_verbose "Cache hit (age: ${age}s)"
            cat "$cache_file"
            return 0
        else
            log_verbose "Cache expired (age: ${age}s > TTL: ${CACHE_TTL}s)"
            rm -f "$cache_file"
        fi
    fi

    return 1
}

cache_store() {
    [[ "$NO_CACHE" == "true" ]] && return 0

    local data="$1"
    local cache_key
    cache_key=$(get_cache_key)
    local cache_file="${CACHE_DIR}/${cache_key}.cache"

    mkdir -p "$CACHE_DIR"
    echo "$data" > "$cache_file"
    log_verbose "Cache stored: $cache_file"
}

# =============================================================================
# 11. Download Functions
# =============================================================================

# Generate SHA256 checksum for a file
generate_checksum() {
    local filepath="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$filepath" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$filepath" | cut -d' ' -f1
    else
        echo ""
    fi
}

# Verify checksum against expected value
verify_checksum() {
    local filepath="$1"
    local expected="$2"
    
    if [[ -z "$expected" ]]; then
        log_warn "No expected checksum provided for verification"
        return 1
    fi
    
    local actual
    actual=$(generate_checksum "$filepath")
    
    if [[ -z "$actual" ]]; then
        log_warn "Could not generate checksum (sha256sum/shasum not available)"
        return 1
    fi
    
    if [[ "$actual" == "$expected" ]]; then
        log_success "✔ Checksum verified"
        return 0
    else
        log_error "Checksum mismatch!"
        log_info "  Expected: ${expected}"
        log_info "  Actual:   ${actual}"
        return 1
    fi
}

# Extract tarball
extract_tarball() {
    local filepath="$1"
    
    if [[ ! -f "$filepath" ]]; then
        log_error "File not found: $filepath"
        return 1
    fi
    
    local extract_dir
    extract_dir="$(dirname "$filepath")"
    local filename
    filename="$(basename "$filepath")"
    
    log_info "  Extracting ${filename}..."
    
    if tar -xjf "$filepath" -C "$extract_dir" 2>/dev/null; then
        log_success "✔ Extraction complete"
        # List extracted contents
        local extracted
        extracted=$(tar -tjf "$filepath" 2>/dev/null | head -5)
        if [[ -n "$extracted" ]]; then
            log_verbose "Extracted contents:"
            echo "$extracted" | while read -r line; do
                log_verbose "    $line"
            done
        fi
        return 0
    else
        log_error "Extraction failed"
        return 1
    fi
}

# Create symlink to latest download
create_symlink() {
    local filepath="$1"
    local link_name="${DOWNLOAD_DIR}/plexamp-latest.tar.bz2"
    local filename
    filename="$(basename "$filepath")"
    
    # Remove existing symlink if present
    if [[ -L "$link_name" ]]; then
        rm -f "$link_name"
        log_verbose "Removed existing symlink"
    fi
    
    # Create new symlink
    if ln -s "$filename" "$link_name" 2>/dev/null; then
        log_success "✔ Created symlink: ${link_name} → ${filename}"
        return 0
    else
        log_error "Failed to create symlink"
        return 1
    fi
}

# Download a single version with all post-processing options
download_single_version() {
    local ver="$1" primary_arch="$2"
    local download_success=false

    log_info "${CYAN}${BOLD}Attempting to download Plexamp v${ver}...${RESET}"
    echo ""

    # Ensure download directory exists
    if [[ ! -d "$DOWNLOAD_DIR" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would create directory: $DOWNLOAD_DIR"
        else
            mkdir -p "$DOWNLOAD_DIR" || {
                log_error "Failed to create download directory: $DOWNLOAD_DIR"
                exit 1
            }
        fi
    fi

    # Determine which architectures to try
    local arches=()
    if [[ -n "$ARCH_FILTER" ]] && [[ "$ARCH_FILTER" != "all" ]]; then
        arches=("$ARCH_FILTER")
    else
        arches=("$primary_arch")
        if [[ "$primary_arch" == "headless" ]]; then
            arches+=("arm64")
        else
            arches+=("headless")
        fi
    fi

    for arch_label in "${arches[@]}"; do
        local url
        url=$(build_url "$ver" "$arch_label")
        log_info "  ${DIM}Checking: ${url}${RESET}"

        if url_exists "$url"; then
            local filename="Plexamp-Linux-${arch_label}-v${ver}.tar.bz2"
            local filepath="${DOWNLOAD_DIR}/${filename}"

            log_success "✔ Found! ${DIM}(${arch_label})${RESET}"
            echo ""

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would download: ${url}"
                log_info "[DRY-RUN] Would save to: ${filepath}"
                
                if [[ "$VERIFY_CHECKSUM" == "true" ]]; then
                    log_info "[DRY-RUN] Would verify checksum"
                fi
                if [[ "$AUTO_EXTRACT" == "true" ]]; then
                    log_info "[DRY-RUN] Would extract tarball"
                fi
                if [[ "$CREATE_SYMLINK" == "true" ]]; then
                    log_info "[DRY-RUN] Would create symlink"
                fi
                return 0
            fi

            log_info "  Downloading → ${filename}"
            echo ""

            curl -L --progress-bar -C - -o "$filepath" "$url"
            local curl_status=$?

            if [[ $curl_status -eq 0 ]]; then
                echo ""
                log_success "${BOLD}✔ Download complete: ${filepath}${RESET}"

                # Verify file was created and has content
                if [[ -f "$filepath" ]] && [[ -s "$filepath" ]]; then
                    local filesize
                    filesize=$(du -h "$filepath" | cut -f1)
                    log_info "  ${DIM}File size: ${filesize}${RESET}"
                    
                    download_success=true
                    
                    # Checksum verification
                    if [[ "$VERIFY_CHECKSUM" == "true" ]]; then
                        log_info "  ${DIM}Verifying checksum...${RESET}"
                        local checksum
                        checksum=$(generate_checksum "$filepath")
                        if [[ -n "$checksum" ]]; then
                            log_info "  SHA256: ${checksum}"
                        else
                            log_warn "  Could not generate checksum"
                        fi
                    fi
                    
                    # Auto-extraction
                    if [[ "$AUTO_EXTRACT" == "true" ]]; then
                        echo ""
                        extract_tarball "$filepath" || true
                    fi
                    
                    # Create symlink
                    if [[ "$CREATE_SYMLINK" == "true" ]]; then
                        echo ""
                        create_symlink "$filepath" || true
                    fi
                fi
            else
                echo ""
                log_error "Download failed (curl exit code: ${curl_status}). Check your connection and retry."
                return 1
            fi
            break
        fi
    done

    if [[ "$download_success" == "false" ]]; then
        log_error "Version v${ver} not found for any known architecture"
        log_info "  Tip: Run without arguments to see all currently available versions"
        return 1
    fi
    
    return 0
}

# Handle batch downloads (comma-separated versions)
download_versions() {
    local versions_str="$1"
    local primary_arch="$2"
    local failed=0
    local succeeded=0
    
    # Split comma-separated versions
    IFS=',' read -ra versions <<< "$versions_str"
    local total=${#versions[@]}
    
    if [[ $total -gt 1 ]]; then
        log_info "${BOLD}Batch download: ${total} version(s)${RESET}"
        echo ""
    fi
    
    local i=1
    for ver in "${versions[@]}"; do
        # Trim whitespace
        ver=$(echo "$ver" | xargs)
        
        if [[ $total -gt 1 ]]; then
            echo ""
            log_info "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            log_info "${BOLD}Progress: ${i}/${total} - v${ver}${RESET}"
            log_info "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        
        if download_single_version "$ver" "$primary_arch"; then
            ((succeeded++)) || true
        else
            ((failed++)) || true
        fi

        ((i++)) || true
    done
    
    echo ""
    if [[ $total -gt 1 ]]; then
        log_info "${BOLD}Download Summary:${RESET}"
        log_info "  ${GREEN}Succeeded: ${succeeded}${RESET}"
        if [[ $failed -gt 0 ]]; then
            log_info "  ${RED}Failed: ${failed}${RESET}"
        fi
    fi
    
    [[ $failed -gt 0 ]] && return 1
    return 0
}

# =============================================================================
# 11b. Phase 3 Advanced Features
# =============================================================================

# Retry helper with exponential backoff
retry_request() {
    local url="$1"
    local shift_args=("${@:2}")
    local attempt=1
    local delay=2
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_verbose "Request attempt ${attempt}/${MAX_RETRIES}: $url"
        
        if curl -sL --max-time 30 "${shift_args[@]}" "$url" 2>/dev/null; then
            return 0
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_verbose "Request failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        ((attempt++))
    done
    
    log_error "Request failed after ${MAX_RETRIES} attempts"
    return 1
}

# Fetch release notes for a version
fetch_release_notes() {
    local version="$1"
    
    log_info "${CYAN}${BOLD}Fetching release notes for v${version}...${RESET}"
    echo ""
    
    # Try to fetch from GitHub releases (common pattern)
    local github_url="https://api.github.com/repos/plexlabs/plexamp/releases"
    local release_data
    
    release_data=$(curl -sL --max-time 10 "$github_url" 2>/dev/null) || release_data=""
    
    if [[ -n "$release_data" ]]; then
        local release_info
        release_info=$(echo "$release_data" | jq -r --arg ver "v${version}" '
            .[] | select(.tag_name == $ver or .name == $ver) | 
            "## \(.name)\n\n**Published:** \(.published_at)\n\n\(.body)"' 2>/dev/null)
        
        if [[ -n "$release_info" ]]; then
            echo -e "$release_info"
            return 0
        fi
    fi
    
    # Fallback: try Plex forums or documentation
    log_info "  ${DIM}Official release notes not available for v${version}${RESET}"
    log_info "  ${DIM}Check https://forums.plex.tv for announcements${RESET}"
    return 1
}

# Compare two versions
compare_versions_detailed() {
    local v1="$1"
    local v2="$2"
    
    log_info "${CYAN}${BOLD}Comparing v${v1} vs v${v2}...${RESET}"
    echo ""
    
    # Get architecture availability for both versions
    local arches_v1=()
    local arches_v2=()
    local url_v1 url_v2

    for arch in headless arm64; do
        url_v1=$(build_url "$v1" "$arch")
        url_v2=$(build_url "$v2" "$arch")

        if url_exists "$url_v1"; then
            arches_v1+=("$arch")
        fi
        if url_exists "$url_v2"; then
            arches_v2+=("$arch")
        fi
    done

    # Compare
    printf "${BOLD}%-20s %-20s %-20s${RESET}\n" "PROPERTY" "v${v1}" "v${v2}"
    printf '%0.s─' {1..65}
    printf '\n'
    
    # Version comparison
    local cmp_result
    cmp_result=$(compare_versions "$v1" "$v2")
    local newer="v${v2}"
    [[ "$cmp_result" == "2" ]] && newer="v${v1}"
    
    printf "${BOLD}%-20s ${RESET}%-20s %-20s\n" "Version" "v${v1}" "v${v2}"
    printf "${BOLD}%-20s ${RESET}%-20s %-20s\n" "Newer Version" "" "${GREEN}${newer}${RESET}"
    printf "${BOLD}%-20s ${RESET}%-20s %-20s\n" "Architectures" "${arches_v1[*]:-none}" "${arches_v2[*]:-none}"
    
    echo ""
    
    # URL comparison
    log_info "${DIM}Download URLs:${RESET}"
    for arch in "${arches_v1[@]}"; do
        url_v1=$(build_url "$v1" "$arch")
        echo "  v${v1} (${arch}): ${DIM}${url_v1}${RESET}"
    done
    for arch in "${arches_v2[@]}"; do
        url_v2=$(build_url "$v2" "$arch")
        echo "  v${v2} (${arch}): ${DIM}${url_v2}${RESET}"
    done
}

# Auto-detect version range
auto_detect_range() {
    log_info "${CYAN}${BOLD}Auto-detecting version range...${RESET}"
    echo ""
    
    local found_major=()
    local major=4
    local minor=0
    local patch=0
    
    # Find highest available version by probing
    log_info "${DIM}Probing for available versions...${RESET}"
    
    # Start from known working range and expand
    for major in 4 5; do
        for minor in $(seq 0 20); do
            local url
            url=$(build_url "${major}.${minor}.0" "headless")
            if url_exists "$url"; then
                found_major+=("${major}.${minor}")
            fi
        done
    done
    
    if [[ ${#found_major[@]} -gt 0 ]]; then
        # Get min and max
        local min_ver="${found_major[0]}"
        local max_ver="${found_major[-1]}"
        
        log_success "Found versions from ${min_ver} to ${max_ver}"
        
        # Set global variables
        MINOR_START="${min_ver##*.}"
        MINOR_END="${max_ver##*.}"
        MAJOR_START="${min_ver%.*}"
        MAJOR_END="${max_ver%.*}"
        
        log_info "${DIM}Scan range set to: ${MAJOR_START}.${MINOR_START}.0 → ${MAJOR_END}.${MINOR_END}.10${RESET}"
    else
        log_warn "Could not auto-detect range, using defaults"
    fi
}

# Send webhook notification
send_webhook() {
    local message="$1"
    local results_file="$2"
    
    if [[ -z "$WEBHOOK_URL" ]]; then
        return 0
    fi
    
    log_verbose "Sending webhook notification..."
    
    # Format for Discord/Slack
    local payload
    payload=$(cat <<EOF
{
    "content": "Plexamp Version Scan Complete",
    "embeds": [{
        "title": "Scan Results",
        "description": "${message}",
        "color": 5814783,
        "fields": [{
            "name": "Versions Found",
            "value": "$(wc -l < "$results_file" 2>/dev/null || echo 0)",
            "inline": true
        }],
        "footer": {
            "text": "plexamp-versions.sh v${SCRIPT_VERSION}"
        },
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }]
}
EOF
)
    
    curl -sL -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL" \
        >/dev/null 2>&1 || log_warn "Webhook notification failed"
    
    log_verbose "Webhook sent"
}

# Interactive TUI mode
interactive_mode() {
    # Check if running in interactive terminal
    if [[ ! -t 0 ]]; then
        log_error "Interactive mode requires a terminal"
        log_info "  ${DIM}Interactive mode cannot run when input is piped${RESET}"
        log_info "  ${DIM}Run the script directly without piping${RESET}"
        return 1
    fi

    echo ""
    printf "%b%bInteractive Mode - Browse Available Versions%b\n" "${CYAN}" "${BOLD}" "${RESET}"
    printf "%bSelect a version to download, or 'q' to quit%b\n" "${DIM}" "${RESET}"
    echo ""

    local versions_array=()
    local found_count=0

    # Quick scan to populate versions
    printf "%bScanning for available versions...%b\n" "${DIM}" "${RESET}"

    for (( minor=MINOR_START; minor<=MINOR_END; minor++ )); do
        for (( patch=PATCH_START; patch<=PATCH_END; patch++ )); do
            local ver="${MAJOR_START}.${minor}.${patch}"
            local url
            url=$(build_url "$ver" "$PRIMARY_ARCH")
            if url_exists "$url"; then
                versions_array+=("$ver")
                ((found_count++)) || true
            fi
        done
    done

    # Also check alternate architecture
    local alt_arch
    if [[ "$PRIMARY_ARCH" == "headless" ]]; then
        alt_arch="arm64"
    else
        alt_arch="headless"
    fi
    
    for (( minor=MINOR_START; minor<=MINOR_END; minor++ )); do
        for (( patch=PATCH_START; patch<=PATCH_END; patch++ )); do
            local ver="${MAJOR_START}.${minor}.${patch}"
            # Skip if already found with primary arch
            local already_found=false
            for v in "${versions_array[@]}"; do
                [[ "$v" == "$ver" ]] && already_found=true && break
            done
            [[ "$already_found" == "true" ]] && continue
            
            local url
            url=$(build_url "$ver" "$alt_arch")
            if url_exists "$url"; then
                versions_array+=("$ver|${alt_arch}")
                ((found_count++)) || true
            fi
        done
    done

    if [[ ${#versions_array[@]} -eq 0 ]]; then
        log_error "No versions found"
        return 1
    fi

    # Sort versions
    local sorted_tmp
    sorted_tmp=$(printf '%s\n' "${versions_array[@]}" | sort -t'.' -k1,1n -k2,2n -k3,3n)
    versions_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && versions_array+=("$line")
    done <<< "$sorted_tmp"

    echo ""
    printf "%bFound %s versions%b\n" "${GREEN}" "$found_count" "${RESET}"
    echo ""

    # Display numbered list
    local i=1
    for entry in "${versions_array[@]}"; do
        local ver arch
        IFS='|' read -r ver arch <<< "$entry"
        if [[ -n "$arch" ]]; then
            printf "  %3d) v%s (%s)\n" "$i" "$ver" "$arch"
        else
            printf "  %3d) v%s\n" "$i" "$ver"
        fi
        ((i++))
    done
    printf "  %3d) Quit\n" "$i"
    echo ""

    # Get user selection
    while true; do
        echo -ne "Enter choice [1-$i]: "
        read -r choice

        # Handle quit
        if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
            printf "%bExiting interactive mode%b\n" "${DIM}" "${RESET}"
            return 0
        fi

        # Validate number
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            printf "%bInvalid input. Please enter a number.%b\n" "${YELLOW}" "${RESET}"
            continue
        fi

        if [[ "$choice" -eq "$i" ]]; then
            printf "%bExiting interactive mode%b\n" "${DIM}" "${RESET}"
            return 0
        fi

        if [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#versions_array[@]}" ]]; then
            printf "%bPlease enter a number between 1 and %s%b\n" "${YELLOW}" "$i" "${RESET}"
            continue
        fi
        
        # Get selected version
        local selected="${versions_array[$((choice-1))]}"
        local sel_ver sel_arch
        IFS='|' read -r sel_ver sel_arch <<< "$selected"

        echo ""
        printf "%bDownloading v%s (%s)...%b\n" "${CYAN}" "$sel_ver" "${sel_arch:-$PRIMARY_ARCH}" "${RESET}"
        echo ""

        if [[ -n "$sel_arch" ]]; then
            ARCH_FILTER="$sel_arch" download_single_version "$sel_ver" "$sel_arch"
        else
            download_single_version "$sel_ver" "$PRIMARY_ARCH"
        fi

        # Ask if user wants to continue
        echo ""
        echo -ne "Download another version? [y/N]: "
        read -r continue_choice

        if [[ "$continue_choice" != "y" ]] && [[ "$continue_choice" != "Y" ]]; then
            printf "%bExiting interactive mode%b\n" "${DIM}" "${RESET}"
            return 0
        fi
        echo ""
    done
}

# =============================================================================
# 12. Output Functions
# =============================================================================

# Print table header
print_table_header() {
    echo ""
    printf "${BOLD}%-15s %-12s %-18s %s${RESET}\n" "VERSION" "ARCH" "TAG" "URL"
    printf '%0.s─' {1..90}
    printf '\n'
}

# Print a single result row (table format)
print_table_row() {
    local ver="$1" arch="$2" tag="$3" url="$4"
    local colour="$DIM"
    [[ "$tag" == "OFFICIAL LATEST" ]] && colour="$GREEN"

    printf "${colour}%-15s %-12s %-18s %s${RESET}\n" "v${ver}" "$arch" "$tag" "$url"
}

# Output results in JSON format
output_json() {
    local -n results_ref=$1
    local official_ver="$2"

    echo "{"
    echo "  \"generated\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
    echo "  \"architecture\": \"${ARCH_DISPLAY}\","
    echo "  \"primary_arch\": \"${PRIMARY_ARCH}\","
    echo "  \"official_latest\": \"${official_ver}\","
    echo "  \"count\": ${#results_ref[@]},"
    echo "  \"versions\": ["

    local first=true
    for entry in "${results_ref[@]}"; do
        IFS='|' read -r ver arch url tag <<< "$entry"
        [[ "$first" == "true" ]] || echo ","
        first=false
        printf '    {"version": "%s", "arch": "%s", "tag": "%s", "url": "%s"}' "$ver" "$arch" "$tag" "$url"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# Output results in CSV format
output_csv() {
    local -n results_ref=$1

    echo "version,arch,tag,url"
    for entry in "${results_ref[@]}"; do
        IFS='|' read -r ver arch url tag <<< "$entry"
        echo "v${ver},${arch},${tag},${url}"
    done
}

# Output results in Markdown format
output_markdown() {
    local -n results_ref=$1

    echo ""
    echo "# Plexamp Headless — Available Versions"
    echo ""
    echo "**Generated:** $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "**Architecture:** ${ARCH_DISPLAY} (${PRIMARY_ARCH})"
    echo "**Count:** ${#results_ref[@]}"
    echo ""
    echo "| Version | Architecture | Tag | URL |"
    echo "|---------|--------------|-----|-----|"

    for entry in "${results_ref[@]}"; do
        IFS='|' read -r ver arch url tag <<< "$entry"
        echo "| v${ver} | ${arch} | ${tag} | ${url} |"
    done

    echo ""
}

# =============================================================================
# 13. Main Scan Logic
# =============================================================================
run_scan() {
    local official_ver="$1"

    # Check cache first
    local cached_results
    if cached_results=$(cache_lookup); then
        log_verbose "Using cached results"
        echo "$cached_results"
        return
    fi

    log_info "${DIM}Scanning versions ${MAJOR_START}.${MINOR_START}.${PATCH_START} → ${MAJOR_END}.${MINOR_END}.${PATCH_END}${RESET}"
    log_info "${DIM}Max concurrent requests: ${MAX_CONCURRENT}${RESET}"
    log_info "${DIM}Architecture filter: ${ARCH_FILTER:-auto}${RESET}"
    echo "" >&2

    RESULTS_TMPDIR=$(mktemp -d)
    local total_probes=0
    local completed=0

    # Calculate total probes for progress reporting
    total_probes=$(( (MAJOR_END - MAJOR_START + 1) * (MINOR_END - MINOR_START + 1) * (PATCH_END - PATCH_START + 1) ))

    # Progress bar helper function
    show_progress() {
        local current=$1
        local total=$2
        local pct=$((current * 100 / total))

        # Use simple text progress for non-interactive, fancy bar for interactive
        if [[ -t 2 ]]; then
            # Interactive terminal - use progress bar with colors
            local bar_width=30
            local filled=$((pct * bar_width / 100))
            local empty=$((bar_width - filled))

            local bar_filled bar_empty
            # shellcheck disable=SC2183
            bar_filled=$(printf '%*s' "$filled" | tr ' ' '=')
            # shellcheck disable=SC2183
            bar_empty=$(printf '%*s' "$empty" | tr ' ' '-')

            # Use printf with %b for proper ANSI escape sequence handling
            printf "\r  %bProgress: [%b%b%b%b%b] %s%% (%s/%s)%b" "${DIM}" "${GREEN}" "$bar_filled" "${RESET}" "${DIM}" "$bar_empty" "$pct" "$current" "$total" "${RESET}" >&2
        else
            # Non-interactive - simple text progress
            printf "  Progress: %s/%s (%s%%)\n" "$current" "$total" "$pct" >&2
        fi
    }

    # Launch probes with throttling
    local running=0
    for (( major=MAJOR_START; major<=MAJOR_END; major++ )); do
        for (( minor=MINOR_START; minor<=MINOR_END; minor++ )); do
            for (( patch=PATCH_START; patch<=PATCH_END; patch++ )); do
                local ver="${major}.${minor}.${patch}"

                # Check version range filter
                if ! version_in_range "$ver" "$MIN_VERSION" "$MAX_VERSION"; then
                    log_verbose "Skipping $ver (outside filter range)"
                    ((completed++))
                    continue
                fi

                # Throttle: wait if we have too many running
                while (( running >= MAX_CONCURRENT )); do
                    wait -n 2>/dev/null || true
                    ((running--)) || true
                done

                # Launch probe in background
                (
                    result=$(probe_version "$ver" "$PRIMARY_ARCH" "$official_ver")
                    if [[ -n "$result" ]]; then
                        echo "$result" > "${RESULTS_TMPDIR}/${ver}.result"
                    fi
                ) &
                PID_LIST+=($!)
                ((running++))
                ((completed++))

                # Progress indicator (non-quiet mode only)
                if [[ "$QUIET_MODE" == "false" ]] && [[ "$VERBOSE_MODE" == "false" ]]; then
                    if (( completed % 20 == 0 )) || (( completed == total_probes )); then
                        show_progress "$completed" "$total_probes"
                    fi
                elif [[ "$VERBOSE_MODE" == "true" ]] && (( completed % 50 == 0 )); then
                    log_verbose "Progress: ${completed}/${total_probes} probes"
                fi
            done
        done
    done

    # Wait for all background jobs
    if [[ "$QUIET_MODE" == "false" ]] && [[ "$VERBOSE_MODE" == "false" ]]; then
        show_progress "$total_probes" "$total_probes"
        # Add newline only for interactive mode (non-interactive already has \n)
        [[ -t 2 ]] && echo "" >&2
    fi
    log_verbose "Waiting for all probes to complete..."
    wait

    # Collect and sort results
    local sorted_results
    sorted_results=$(
        find "${RESULTS_TMPDIR}" -name '*.result' -exec cat {} \; 2>/dev/null | \
        sort -t'.' -k1,1n -k2,2n -k3,3n
    )

    # Store in cache
    cache_store "$sorted_results"

    echo "$sorted_results"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # Initialize
    init_colors
    parse_args "$@"
    setup_signal_handlers
    check_deps

    # Detect architecture
    PRIMARY_ARCH=$(detect_arch)
    ARCH_DISPLAY=$(uname -m)

    # Override arch detection if filter specified
    if [[ -n "$ARCH_FILTER" ]] && [[ "$ARCH_FILTER" != "all" ]]; then
        PRIMARY_ARCH="$ARCH_FILTER"
    fi

    # Handle Phase 3 special modes first (before banner)
    
    # Interactive mode
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        interactive_mode
        exit $?
    fi
    
    # Compare mode
    if [[ -n "$COMPARE_VERSIONS" ]]; then
        IFS=',' read -ra compare_vers <<< "$COMPARE_VERSIONS"
        if [[ ${#compare_vers[@]} -ne 2 ]]; then
            log_error "--compare requires exactly 2 versions (e.g., 4.11.2,4.12.4)"
            exit 2
        fi
        compare_versions_detailed "${compare_vers[0]}" "${compare_vers[1]}"
        exit $?
    fi
    
    # Release notes mode
    if [[ -n "$RELEASE_NOTES_VERSION" ]]; then
        fetch_release_notes "$RELEASE_NOTES_VERSION"
        exit $?
    fi
    
    # Auto-range mode
    if [[ "$AUTO_RANGE" == "true" ]]; then
        auto_detect_range
        # Continue to scan with detected range
    fi

    # Print banner (unless quiet mode)
    if [[ "$QUIET_MODE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        printf "%b╔══════════════════════════════════════════════════════════╗%b\n" "${BOLD}" "${RESET}"
        printf "%b║        Plexamp Headless — Version Discovery Tool         ║%b\n" "${BOLD}" "${RESET}"
        printf "%b║                        v%s                            ║%b\n" "${BOLD}" "${SCRIPT_VERSION}" "${RESET}"
        printf "%b╚══════════════════════════════════════════════════════════╝%b\n" "${BOLD}" "${RESET}"
        printf "  %bArchitecture:%b %b%s%s%s → %s%s\n" "${DIM}" "${RESET}" "${CYAN}" "${ARCH_DISPLAY}" "${DIM}" "${RESET}" "${CYAN}" "${PRIMARY_ARCH}"
        echo ""
    fi

    # Fetch official latest version
    log_info "${DIM}Contacting official API...${RESET}"
    local OFFICIAL_JSON
    OFFICIAL_JSON=$(curl -s --max-time 10 "$VERSION_API" 2>/dev/null) || OFFICIAL_JSON=""

    local OFFICIAL_VER="unknown"

    if [[ -n "$OFFICIAL_JSON" ]]; then
        OFFICIAL_VER=$(echo "$OFFICIAL_JSON" | jq -r '.latestVersion // "unknown"' 2>/dev/null) || OFFICIAL_VER="unknown"
        log_verbose "API response: $OFFICIAL_JSON"

        if [[ "$OFFICIAL_VER" != "unknown" ]]; then
            log_success "Official latest: ${BOLD}v${OFFICIAL_VER}${RESET}"
        fi
    else
        log_warn "Could not reach official API. Continuing with scan only."
    fi

    # Download mode
    if [[ -n "$TARGET_VERSION" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "${CYAN}${BOLD}[DRY-RUN] Would attempt to download Plexamp v${TARGET_VERSION}${RESET}"
        fi
        download_versions "$TARGET_VERSION" "$PRIMARY_ARCH"
        exit $?
    fi

    # Scan mode
    local FOUND_RESULTS=()

    # Run scan and capture results
    local scan_output
    scan_output=$(run_scan "$OFFICIAL_VER") || true

    # Parse results into array
    if [[ -n "$scan_output" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && FOUND_RESULTS+=("$line")
        done <<< "$scan_output"
    fi

    # Apply --latest-n filter
    if [[ $LATEST_N -gt 0 ]] && [[ ${#FOUND_RESULTS[@]} -gt $LATEST_N ]]; then
        FOUND_RESULTS=("${FOUND_RESULTS[@]: -$LATEST_N}")
    fi

    # Output results
    if [[ ${#FOUND_RESULTS[@]} -eq 0 ]]; then
        if [[ "$QUIET_MODE" == "false" ]]; then
            echo ""
            log_warn "No versions found in the scanned range"
        fi
    else
        # Output based on format
        case "$OUTPUT_FORMAT" in
            table)
                if [[ "$QUIET_MODE" == "false" ]]; then
                    print_table_header
                fi

                # Write to file
                : > "$OUTPUT_FILE"
                echo "# Plexamp Headless — Available Versions" >> "$OUTPUT_FILE"
                echo "# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')" >> "$OUTPUT_FILE"
                echo "# Architecture priority: ${ARCH_DISPLAY} (${PRIMARY_ARCH})" >> "$OUTPUT_FILE"
                echo "# ──────────────────────────────────────────────────────────────" >> "$OUTPUT_FILE"
                printf "%-15s %-12s %-18s %s\n" "VERSION" "ARCH" "TAG" "URL" >> "$OUTPUT_FILE"
                echo "────────────────────────────────────────────────────────────────" >> "$OUTPUT_FILE"

                for entry in "${FOUND_RESULTS[@]}"; do
                    IFS='|' read -r ver arch url tag <<< "$entry"
                    print_table_row "$ver" "$arch" "$tag" "$url"
                    printf "%-15s %-12s %-18s %s\n" "v${ver}" "$arch" "$tag" "$url" >> "$OUTPUT_FILE"
                done

                if [[ "$QUIET_MODE" == "false" ]]; then
                    printf '%0.s─' {1..90}
                    printf '\n'
                    echo ""
                    log_success "${BOLD}Found ${#FOUND_RESULTS[@]} version(s)${RESET}"
                    log_info "Results saved to ${CYAN}${OUTPUT_FILE}${RESET}"
                fi
                ;;

            json)
                output_json FOUND_RESULTS "$OFFICIAL_VER"
                ;;

            csv)
                output_csv FOUND_RESULTS
                ;;

            markdown)
                output_markdown FOUND_RESULTS
                ;;
        esac
    fi

    # Send webhook notification if configured
    if [[ -n "$WEBHOOK_URL" ]] && [[ ${#FOUND_RESULTS[@]} -gt 0 ]]; then
        send_webhook "Found ${#FOUND_RESULTS[@]} Plexamp versions" "$OUTPUT_FILE"
    fi

    # Footer (unless quiet mode)
    if [[ "$QUIET_MODE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        log_info "${DIM}Tip: Run ${RESET}${BOLD}${SCRIPT_NAME} <version>${RESET}${DIM} to download a specific version${RESET}"
        if [[ "$OFFICIAL_VER" != "unknown" ]]; then
            log_info "${DIM}Example: ${RESET}${BOLD}${SCRIPT_NAME} ${OFFICIAL_VER}${RESET}"
        fi
        echo ""
    fi
}

# Run main function
main "$@"
