#!/usr/bin/env bash
#
# cyberpunk-linux-modder.sh — guided installer for Cyberpunk 2077 modding on
# Linux (Steam Proton): Cyber Engine Tweaks (CET) + RED4ext.
#
#   Documentation:      docs/installer.md (architecture) and docs/troubleshooting.md
#   Supported game:     Steam store copy of Cyberpunk 2077 (default app id 1091500)
#   Official sources:   https://github.com/maximegmd/CyberEngineTweaks/releases
#                       https://github.com/WopsS/RED4ext/releases
#                       https://github.com/Matoking/protontricks (Flatpak recommended)
#
# Design rules honored by this script:
#   * Downloads only from the official release URLs above; never redistributes
#     game or mod files, and never hosts installers inside this repository.
#   * Backs up the game's Proton prefix before touching runtime components.
#   * Verifies pinned downloads with SHA-256; refuses unverified overrides
#     unless you pass --allow-unverified-checksum explicitly.
#   * Never deletes the prefix; recovery is a separate, confirmed --rollback.
#   * Never uses sudo except for one clearly prompted Flatpak installation.
#   * Resumable: completed phases are recorded and skipped on re-run.
#   * Failures produce a redacted crash report with next-step guidance.
#
# SPDX-License-Identifier: MIT   (script; repository documentation is CC BY 4.0)

# ---------------------------------------------------------------------------
# 0. Strict mode and globals
# ---------------------------------------------------------------------------
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="1.1.0"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (overridable by flags or environment; see docs/installer.md).
readonly APP_ID_DEFAULT="1091500"
readonly GAME_DIR_NAME_DEFAULT="Cyberpunk 2077"
readonly CET_VERSION_DEFAULT="1.38.0"
readonly RED4EXT_VERSION_DEFAULT="1.31.0"
readonly PROTONTRICKS_APP_ID="com.github.Matoking.protontricks"

# Framework components installed into the game's Proton prefix, in order.
# Add or reorder entries here to extend the script (see docs/installer.md).
readonly WINETRICKS_COMPONENTS=(d3dcompiler_47 vcrun2022)

# Steam launch-option environment required by the two loaders.
readonly LAUNCH_ENVIRONMENT='WINEDLLOVERRIDES="winmm,version=n,b"'

# Phases run in this order; each one records completion for resume.
readonly PHASES=(preflight dependencies backup components download extract launch_options verify)

# Pinpoint checksums for the pinned default versions (computed from the
# official release assets on 2026-10-26). Keys: "cet:<version>",
# "red4ext:<version>". If you override a version and no checksum is known,
# the script stops unless --allow-unverified-checksum is supplied.
declare -A CHECKSUMS=(
  ["cet:1.38.0"]="6da2e91b07d5ea9dd4aa32145b2c2920a976abee481854976e2ae82169b612e1"
  ["red4ext:1.31.0"]="b9ae4351f547f90af58dfbf7445d45c55cd5ba24fbee27fb16fb5d91e9df621e"
)

# Exit codes (also listed in docs/installer.md).
readonly EXIT_OK=0 EXIT_GENERAL=1 EXIT_USAGE=2 EXIT_PREFLIGHT=3 EXIT_DEPS=4
readonly EXIT_BACKUP=5 EXIT_COMPONENTS=6 EXIT_DOWNLOAD=7 EXIT_EXTRACT=8
readonly EXIT_LAUNCH_OPTIONS=9 EXIT_VERIFY=10 EXIT_ROLLBACK=11

# ---------------------------------------------------------------------------
# 1. Parsed configuration (filled by parse_args; edit defaults above, not here)
# ---------------------------------------------------------------------------
FLAG_DRY_RUN=0 FLAG_ASSUME_YES=0 FLAG_FORCE=0 FLAG_QUIET=0 FLAG_NO_COLOR=0
FLAG_SKIP_LAUNCH=0 FLAG_SET_LAUNCH=0 FLAG_ROLLBACK=0 FLAG_SELF_TEST=0
FLAG_ALLOW_UNVERIFIED=0 FLAG_SKIP_COMPONENTS=0
OPT_APP_ID="" OPT_GAME_DIR="" OPT_COMPATDATA=""
OPT_CET_VERSION="" OPT_RED4EXT_VERSION=""

APP_ID="" GAME_DIR="" COMPATDATA="" CET_VERSION="" RED4EXT_VERSION=""
CET_ZIP="" RED4EXT_ZIP="" LIBRARY_DIR=""

PT_MODE=""   # "flatpak" or "native"
HAVE_PYTHON3=0 HAVE_UNZIP=0

STATE_DIR="" LOG_DIR="" WORK_DIR="" OVERWRITE_BACKUP_DIR=""
STATE_FILE="" RUN_LOG="" CRASH_LOG=""
RUN_ID="$(date +%Y%m%d-%H%M%S)"

CURRENT_PHASE="startup"
CRASH_HANDLED=0 EXPECTED_FAIL=0
CAPTURED=""
ROOTS=()
SCRIPT_ARGS=()

# ---------------------------------------------------------------------------
# 2. Presentation and logging layer
# ---------------------------------------------------------------------------
init_colors() {
  COLOR_RESET="" COLOR_BOLD="" COLOR_DIM="" COLOR_RED="" COLOR_GREEN=""
  COLOR_YELLOW="" COLOR_BLUE="" COLOR_CYAN=""
  if (( ! FLAG_NO_COLOR )) && [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_RESET=$'\e[0m'   COLOR_BOLD=$'\e[1m'    COLOR_DIM=$'\e[2m'
    COLOR_RED=$'\e[1;31m'  COLOR_GREEN=$'\e[1;32m' COLOR_YELLOW=$'\e[1;33m'
    COLOR_BLUE=$'\e[1;34m' COLOR_CYAN=$'\e[1;36m'
  fi
}

redact() { # Make a path safe for shareable reports: /home/<user>/... -> ~/...
  sed -E 's|/home/[^/[:space:]"'"'"']+|~|g'
}

log() { # log <LEVEL> <message...>: console + run log
  local level="$1"; shift
  local stamp line
  stamp="$(date '+%Y-%m-%d %H:%M:%S')"
  line="[$stamp] [$level] $*"
  printf '%s\n' "$line" >> "$RUN_LOG"
  (( FLAG_QUIET )) && return 0
  case "$level" in
    INFO)    printf '%s%s%s\n' "$COLOR_CYAN" "$line" "$COLOR_RESET" ;;
    TITLE)   printf '%s%s%s\n' "$COLOR_BOLD" "$line" "$COLOR_RESET" ;;
    DIM)     printf '%s%s%s\n' "$COLOR_DIM" "$line" "$COLOR_RESET" ;;
    WARN)    printf '%s%s%s\n' "$COLOR_YELLOW" "$line" "$COLOR_RESET" ;;
    ERROR)   printf '%s%s%s\n' "$COLOR_RED" "$line" "$COLOR_RESET" ;;
    SUCCESS) printf '%s%s%s\n' "$COLOR_GREEN" "$line" "$COLOR_RESET" ;;
    DEBUG)   printf '%s%s%s\n' "$COLOR_BLUE" "$line" "$COLOR_RESET" ;;
    *)       printf '%s\n' "$line" ;;
  esac
}

section() { # section "<title>": prominent phase banner
  local title="$1"
  local bar="======================================================================"
  log INFO "$bar"
  log TITLE "-- $title"
  log INFO "$bar"
}

confirm() { # confirm "<question>"; honors --yes, --dry-run; answers via tty/stdin
  local question="$1" answer=""
  if (( FLAG_ASSUME_YES )); then
    log INFO "[--yes] Assumed yes: $question"
    return 0
  fi
  if (( FLAG_DRY_RUN )); then
    log INFO "[dry-run] Would ask: $question"
    return 0
  fi
  printf '%b[y/N] ' "$question" >&2
  if [[ -r /dev/tty ]]; then
    IFS= read -r answer < /dev/tty || return 1
  else
    IFS= read -r answer || return 1
  fi
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# ---------------------------------------------------------------------------
# 3. Execution helpers: run() (mutating, dry-run aware) and capture() (read-only)
# ---------------------------------------------------------------------------
run() { # run <cmd...>: execute a mutating command, teeing output into the log
  if (( FLAG_DRY_RUN )); then
    log DIM "[dry-run] Would run: $*"
    return 0
  fi
  log DEBUG "RUN: $*"
  "$@" 2>&1 | tee -a "$RUN_LOG"
}

capture() { # capture <cmd...>: run read-only command; result in $CAPTURED
  CAPTURED=""
  log DEBUG "RUN: $*"
  local out status
  if out="$("$@" 2>&1)"; then status=0; else status=$?; fi
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" >> "$RUN_LOG"
  fi
  CAPTURED="$out"
  return "$status"
}

die() { # die <message> [exit_code]: expected failure; no crash report
  local message="$1" code="${2:-$EXIT_GENERAL}"
  EXPECTED_FAIL=1
  log ERROR "$message"
  log ERROR "Exiting with code $code. Run log: $RUN_LOG"
  exit "$code"
}

usage_error() { # usage_error <message>: bad invocation
  printf '%s: %s\n' "$SCRIPT_NAME" "$1" >&2
  printf 'Try '"'"'%s --help'"'"' for usage.\n' "$SCRIPT_NAME" >&2
  exit "$EXIT_USAGE"
}

# ---------------------------------------------------------------------------
# 4. State store (simple key=value file) and resume markers
# ---------------------------------------------------------------------------
state_set() { # state_set <key> <value>
  local key="$1" value="$2"
  mkdir -p "$(dirname -- "$STATE_FILE")"
  touch -- "$STATE_FILE"
  if grep -q "^${key}=" -- "$STATE_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" -- "$STATE_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$STATE_FILE"
  fi
}

state_get() { # state_get <key> [default]; result echoed
  local key="$1" fallback="${2:-}"
  if [[ -f "$STATE_FILE" ]]; then
    local line
    line="$(grep -m1 "^${key}=" -- "$STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$line" ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  fi
  printf '%s\n' "$fallback"
}

phase_is_done() { [[ "$(state_get "phase_$1" 0)" == "1" ]]; }
begin_phase()   { CURRENT_PHASE="$1"; section "Phase: $1"; }
complete_phase(){ state_set "phase_$1" 1; log SUCCESS "Phase '$1' completed."; }

# ---------------------------------------------------------------------------
# 5. Crash handling: ERR trap -> redacted crash report + guidance
# ---------------------------------------------------------------------------
phase_hint() { # phase_hint <phase>: what to try next, per failing phase
  case "$1" in
    preflight)      echo "Check that Steam and the Steam version of Cyberpunk 2077 are installed and that the game was launched at least once under Proton. Re-run with --game-dir=/path/to/Cyberpunk\\ 2077 if it lives in an unusual library." ;;
    dependencies)   echo "Install Flatpak and Protontricks manually (see README section 1), then re-run this script." ;;
    backup)         echo "Free up disk space or set COMPATDATA correctly. Do NOT delete the existing prefix; see docs/backup-and-recovery.md." ;;
    components)     echo "A Winetricks component failed. Inspect the log above. If vcrun2022 reports an existing incompatible runtime, stop there and consult docs/troubleshooting.md. Do NOT use --force blindly." ;;
    download)       echo "A download failed or its checksum did not match. Check your connection and the official release page. Never bypass checksums without understanding the risk (--allow-unverified-checksum)." ;;
    extract)        echo "Extraction into the game folder failed. Ensure the game is closed and the folder is writable. Your overwritten-file backups are kept in the state directory." ;;
    launch_options) echo "Steam launch options could not be set automatically. Apply them by hand in Steam (see README section 5), or re-run with --skip-launch-options." ;;
    verify)         echo "Verification failed after installation. Compare against docs/troubleshooting.md before removing anything." ;;
    *)              echo "Re-run with --dry-run to inspect what would happen, and read docs/troubleshooting.md." ;;
  esac
}

write_crash_report() { # write_crash_report <exit_status> <command>
  local status="$1" command="$2"
  mkdir -p "$LOG_DIR"
  CRASH_LOG="$LOG_DIR/crash-${RUN_ID}.log"
  {
    printf 'Cyberpunk Linux Modder — crash report\n'
    printf '====================================\n'
    printf 'Timestamp        : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'Script version   : %s\n' "$SCRIPT_VERSION"
    printf 'Failed phase     : %s\n' "$CURRENT_PHASE"
    printf 'Exit status      : %s\n' "$status"
    printf 'Failing command  : %s\n' "$command"
    printf 'Options used     : %s\n' "${SCRIPT_ARGS[*]:-<(none)>}"
    printf 'Bash             : %s\n' "$BASH_VERSION"
    printf 'Kernel           : %s\n' "$(uname -sr 2>/dev/null || echo unknown)"
    printf 'OS               : %s\n' "$( (grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null || echo 'PRETTY_NAME=unknown') | cut -d= -f2- | tr -d '"')"
    printf 'Dry-run          : %s\n' "$([[ $FLAG_DRY_RUN == 1 ]] && echo yes || echo no)"
    printf '\n--- last 40 log lines (paths redacted) ---\n'
    tail -n 40 -- "$RUN_LOG" 2>/dev/null | redact || true
    printf '\n--- suggested next step ---\n%s\n' "$(phase_hint "$CURRENT_PHASE")"
    local backup
    backup="$(state_get backup_path "")"
    if [[ -n "$backup" && -d "$backup" ]]; then
      printf '\n--- prefix backup available ---\n%s\n' "$(printf '%s' "$backup" | redact)"
      printf 'Recovery: re-run this script with --rollback (interactive), or follow docs/backup-and-recovery.md.\n'
    fi
    printf '\nPrivacy: this report redacts /home/<user> paths. Review it before posting anywhere.\n'
  } > "$CRASH_LOG"
}

on_crash() { # ERR trap entry point
  local status="$1"
  CRASH_HANDLED=1
  trap - ERR
  local command_line="${BASH_COMMAND:-unknown}"
  write_crash_report "$status" "$command_line"
  printf '\n%s=== UNEXPECTED FAILURE ===%s\n' "$COLOR_RED" "$COLOR_RESET" >&2
  printf 'Phase   : %s\n' "$CURRENT_PHASE" >&2
  printf 'Command : %s\n' "$command_line" >&2
  printf 'Status  : %s\n' "$status" >&2
  printf 'A full crash report was written to:\n  %s\n' "$CRASH_LOG" >&2
  printf 'Next step: %s\n' "$(phase_hint "$CURRENT_PHASE")" >&2
  exit "$status"
}

on_exit() { # EXIT trap: friendly success banner or crash passthrough
  local status="$?"
  if (( status == 0 )); then
    printf '\n%sAll requested phases completed.%s\n' "$COLOR_GREEN" "$COLOR_RESET" >&2
    printf 'Run log: %s\n' "$RUN_LOG" >&2
    return 0
  fi
  if (( CRASH_HANDLED == 0 )) && (( EXPECTED_FAIL == 0 )); then
    on_crash "$status"
  fi
}

cleanup_workdir() { # temp downloads are removed unless debugging requested
  if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" && "${KEEP_WORKDIR:-0}" != "1" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

# ---------------------------------------------------------------------------
# 6. Version/URL helpers and checksum verification
# ---------------------------------------------------------------------------
cet_url() { # CET release asset follows the cet_<major>_<minor>_<patch>.zip pattern
  local version="$1"
  printf 'https://github.com/maximegmd/CyberEngineTweaks/releases/download/v%s/cet_%s.zip\n' \
    "$version" "${version//./_}"
}

red4ext_url() {
  local version="$1"
  printf 'https://github.com/wopss/RED4ext/releases/download/v%s/red4ext-%s.zip\n' "$version" "$version"
}

verify_sha256() { # verify_sha256 <file> <expected_hex>
  local file="$1" expected="$2" actual
  actual="$(sha256sum -- "$file" 2>/dev/null | awk '{print $1}')"
  if [[ -z "$actual" ]]; then
    log ERROR "Could not compute checksum for $file"
    return 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    log ERROR "Checksum mismatch for $(basename -- "$file")"
    log ERROR "  expected: $expected"
    log ERROR "  actual:   $actual"
    return 1
  fi
  log SUCCESS "Checksum OK: $(basename -- "$file")"
}

# ---------------------------------------------------------------------------
# 7. Steam discovery: roots, libraries, game folder, prefix
# ---------------------------------------------------------------------------
steam_roots() { # populate ROOTS with plausible Steam data roots
  ROOTS=()
  local candidate
  local -a candidates=(
    "${STEAM_ROOT:-}"
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    "$HOME/snap/steam/common/.local/share/Steam"
  )
  declare -A seen=()
  for candidate in "${candidates[@]}"; do
    [[ -z "$candidate" ]] && continue
    candidate="$(readlink -f -- "$candidate" 2>/dev/null || true)"
    [[ -d "$candidate" ]] || continue
    [[ -n "${seen[$candidate]:-}" ]] && continue
    seen["$candidate"]=1
    ROOTS+=("$candidate")
  done
}

libraries_in_root() { # libraries_in_root <steam_root>; echoes library paths
  local root="$1" vdf="$1/steamapps/libraryfolders.vdf"
  [[ -f "$vdf" ]] || return 0
  if (( HAVE_PYTHON3 )); then
    python3 - "$vdf" <<'PY' 2>/dev/null || true
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
for m in re.finditer(r'^\s*"path"\s*"([^"]+)"\s*$', text, re.M):
    print(m.group(1).replace("\\\\", "\\"))
PY
  else
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' -- "$vdf" | sed 's/\\\\/\\/g'
  fi
}

locate_installation() { # sets GAME_DIR, COMPATDATA, LIBRARY_DIR
  steam_roots
  (( ${#ROOTS[@]} )) || die "No Steam data directory found. Is Steam installed? Set STEAM_ROOT=/path/to/steam and re-run." "$EXIT_PREFLIGHT"

  if [[ -n "$OPT_GAME_DIR" ]]; then
    GAME_DIR="$OPT_GAME_DIR"
    [[ -d "$GAME_DIR" ]] || die "--game-dir does not exist: $GAME_DIR" "$EXIT_PREFLIGHT"
  fi

  local root library game_prefix="steamapps/common/$GAME_DIR_NAME_DEFAULT"
  local -a libraries=()
  declare -A seen_lib=()
  for root in "${ROOTS[@]}"; do
    while IFS= read -r library; do
      [[ -z "$library" || -n "${seen_lib[$library]:-}" ]] && continue
      seen_lib["$library"]=1
      libraries+=("$library")
    done < <(libraries_in_root "$root")
    # Some installs keep the default library inside the root itself.
    [[ -d "$root/steamapps/common" ]] && libraries+=("$root")
  done

  if [[ -z "$GAME_DIR" ]]; then
    for library in "${libraries[@]}"; do
      if [[ -d "$library/$game_prefix" ]]; then
        GAME_DIR="$library/$game_prefix"
        LIBRARY_DIR="$library"
        break
      fi
    done
    [[ -n "$GAME_DIR" ]] || die "Cyberpunk 2077 was not found in any Steam library. Is it installed via Steam? If it lives elsewhere, re-run with --game-dir=/path/to/Cyberpunk\\ 2077." "$EXIT_PREFLIGHT"
  else
    LIBRARY_DIR="$(dirname -- "$(dirname -- "$GAME_DIR")")"  # .../steamapps/common
  fi
  log INFO "Game folder   : $GAME_DIR"

  if [[ -n "$OPT_COMPATDATA" ]]; then
    COMPATDATA="$OPT_COMPATDATA"
    [[ -d "$COMPATDATA/pfx" ]] || die "--compatdata does not contain a pfx directory: $COMPATDATA" "$EXIT_PREFLIGHT"
  else
    local compat_candidate="$LIBRARY_DIR/steamapps/compatdata/$APP_ID"
    [[ -d "$compat_candidate/pfx" ]] || die "The Proton prefix for app $APP_ID was not found under $LIBRARY_DIR/steamapps/compatdata. Launch the game once through Steam (until you reach the main menu), close it, then re-run this script." "$EXIT_PREFLIGHT"
    COMPATDATA="$compat_candidate"
  fi
  log INFO "Proton prefix : $COMPATDATA/pfx"

  [[ -w "$GAME_DIR" ]] || die "The game folder is not writable by this user: $GAME_DIR" "$EXIT_PREFLIGHT"
  [[ -w "$(dirname -- "$COMPATDATA")" ]] || die "The compatibility folder is not writable: $(dirname -- "$COMPATDATA")" "$EXIT_PREFLIGHT"
}

ensure_game_closed() {
  if pgrep -f 'Cyberpunk2077\.exe' >/dev/null 2>&1; then
    die "Cyberpunk 2077 is running. Close the game completely, then re-run this script." "$EXIT_PREFLIGHT"
  fi
}

ensure_steam_closed() {
  if pgrep -x steam >/dev/null 2>&1 || pgrep -f steamwebhelper >/dev/null 2>&1; then
    die "Steam is running. Fully quit Steam ( tray icon -> Exit ), then re-run this step. Steam rewrites its configuration while running." "$EXIT_LAUNCH_OPTIONS"
  fi
}

# ---------------------------------------------------------------------------
# 8. Protontricks selection and wrappers
# ---------------------------------------------------------------------------
flatpak_app_installed() { # true if the app is installed for --user or --system
  command -v flatpak >/dev/null 2>&1 || return 1
  if flatpak list --user --columns=application 2>/dev/null | grep -qx "$PROTONTRICKS_APP_ID"; then return 0; fi
  if flatpak list --system --columns=application 2>/dev/null | grep -qx "$PROTONTRICKS_APP_ID"; then return 0; fi
  return 1
}

select_protontricks() { # sets PT_MODE; prefers the explicit Flatpak invocation
  PT_MODE=""
  if command -v flatpak >/dev/null 2>&1; then
    if flatpak_app_installed; then
      PT_MODE="flatpak"
    else
      return 1   # Flatpak exists but the Protontricks app is not installed yet
    fi
  elif command -v protontricks >/dev/null 2>&1; then
    PT_MODE="native"
    log WARN "Using the native 'protontricks' package. The official project recommends the Flatpak build, which tracks Steam metadata changes faster."
  fi
  [[ -n "$PT_MODE" ]] || return 1
  local -a probe=()
  if [[ "$PT_MODE" == "flatpak" ]]; then probe=(flatpak run "$PROTONTRICKS_APP_ID" --version); else probe=(protontricks --version); fi
  capture "${probe[@]}" || return 1
  log INFO "Protontricks  : $CAPTURED ($PT_MODE)"
  return 0
}

pt() { # pt <args...>: invoke the selected Protontricks
  if [[ "$PT_MODE" == "flatpak" ]]; then
    flatpak run "$PROTONTRICKS_APP_ID" "$@"
  else
    protontricks "$@"
  fi
}

pt_list_installed() { # populates CAPTURED with recorded winetricks verbs
  capture pt "$APP_ID" list-installed
}

# ---------------------------------------------------------------------------
# 9. VDF helpers (python3 required for patching; detection has a grep fallback)
# ---------------------------------------------------------------------------
vdf_python() { # shared python worker; mode: detect|patch
  local mode="$1" file="$2" appid="$3" prepend="${4:-}"
  python3 - "$mode" "$file" "$appid" "$prepend" <<'PY'
import os, re, sys, tempfile

mode, path, appid, prepend = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
    text = fh.read()

app_match = re.search(r'"%s"\s*\{' % re.escape(appid), text)
if not app_match:
    print("APP_BLOCK_MISSING"); sys.exit(3)

start = text.index("{", app_match.start())
depth, i = 0, start
while i < len(text):
    if text[i] == "{":
        depth += 1
    elif text[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
block = text[start:i + 1]

opts = re.search(r'"LaunchOptions"\s*"((?:[^"\\]|\\.)*)"', block)
if mode == "detect":
    if opts:
        print(re.sub(r'\\(["\\])', r"\1", opts.group(1)))
    sys.exit(0)

current = opts.group(1) if opts else ""
current_plain = re.sub(r'\\(["\\])', r"\1", current)
if "WINEDLLOVERRIDES" in current_plain:
    print("ALREADY_PRESENT"); sys.exit(2)

plain_new = (prepend + " " + current_plain).strip() if current_plain else prepend
escaped_new = plain_new.replace("\\", "\\\\").replace('"', '\\"')
if opts:
    new_block = block[:opts.start()] + '"LaunchOptions"' + " " + '"' + escaped_new + '"' + block[opts.end():]
else:
    insertion = '\t\t\t"LaunchOptions"\t\t"%s"\n' % escaped_new
    new_block = block[:-1] + insertion + "\n}"
new_text = text[:start] + new_block + text[i + 1:]

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".localconfig.", suffix=".vdf")
try:
    with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(new_text)
    os.replace(tmp_path, path)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
print("PATCHED")
PY
}

vdf_current_launch_options() { # echoes stored LaunchOptions string (possibly empty)
  local file="$1"
  if (( HAVE_PYTHON3 )); then
    vdf_python detect "$file" "$APP_ID" "" || return 1
  else
    # Best-effort fallback: print the value on the line following the app id.
    grep -A3 "\"$APP_ID\"" -- "$file" 2>/dev/null | grep -o '"LaunchOptions"[^"]*"[^"]*"' | head -n1 | sed 's/.*"\(.*\)"$/\1/' || true
  fi
}

vdf_apply_override() { # returns 0 patched, 2 already present, 3 app block missing
  local file="$1"
  vdf_python patch "$file" "$APP_ID" "$LAUNCH_ENVIRONMENT"
}

# ---------------------------------------------------------------------------
# 10. Zip helpers with fallback extraction engines
# ---------------------------------------------------------------------------
list_zip_entries() { # echo the file entries of a zip archive
  local zip_file="$1"
  if (( HAVE_UNZIP )); then
    unzip -Z1 -- "$zip_file" 2>/dev/null | grep -v '/$' || true
  elif (( HAVE_PYTHON3 )); then
    python3 - "$zip_file" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in archive.namelist():
        if not name.endswith("/"):
            print(name)
PY
  else
    return 1
  fi
}

extract_zip() { # extract_zip <archive> <destination>
  local archive="$1" destination="$2"
  if (( HAVE_UNZIP )); then
    run unzip -q -o -- "$archive" -d "$destination"
  elif (( HAVE_PYTHON3 )); then
    log WARN "unzip not found; falling back to python3 zipfile extraction."
    run python3 -m zipfile -e "$archive" "$destination"
  else
    die "Neither unzip nor python3 is available to extract $archive. Install unzip and re-run." "$EXIT_DOWNLOAD"
  fi
}

# ---------------------------------------------------------------------------
# 11. Phase: preflight
# ---------------------------------------------------------------------------
phase_preflight() {
  (( BASH_VERSINFO[0] >= 4 )) || die "Bash 4 or newer is required." "$EXIT_PREFLIGHT"
  (( EUID != 0 )) || die "Do not run this script as root. It operates on your user's Steam files." "$EXIT_PREFLIGHT"

  if [[ -r /etc/os-release ]]; then
    local pretty
    pretty="$(grep -m1 PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')"
    log INFO "Distribution : $pretty"
    case "$pretty" in
      *Mint*|*Ubuntu*|*Debian*) : ;;
      *) log WARN "Untested distribution. The Flatpak/Protontricks steps may need adjustments; component and framework steps should still apply." ;;
    esac
  fi

  for dependency in curl sha256sum df du pgrep readlink awk sed tee; do
    command -v "$dependency" >/dev/null 2>&1 || die "Required command '$dependency' is missing." "$EXIT_PREFLIGHT"
  done
  if command -v python3 >/dev/null 2>&1; then HAVE_PYTHON3=1; else log WARN "python3 not found; VDF patching and some fallbacks will be limited."; fi
  if command -v unzip >/dev/null 2>&1; then HAVE_UNZIP=1; else log WARN "unzip not found; will try python3 zipfile extraction instead."; fi

  locate_installation
  ensure_game_closed

  select_protontricks || log WARN "Protontricks not detected yet; the dependencies phase will set it up."

  log SUCCESS "Preflight checks passed."
  complete_phase "preflight"
}

# ---------------------------------------------------------------------------
# 12. Phase: dependencies (Flatpak + Protontricks)
# ---------------------------------------------------------------------------
phase_dependencies() {
  if select_protontricks; then
    log INFO "Protontricks already available; nothing to do."
    complete_phase "dependencies"
    return 0
  fi

  if ! command -v flatpak >/dev/null 2>&1; then
    log WARN "Flatpak is not installed. It is required for the recommended Protontricks setup."
    case "$(grep -m1 ^ID= /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')" in
      mint|ubuntu|debian|linuxmint)
        if confirm "Install Flatpak now with 'sudo apt-get install -y flatpak'? (administrator privileges required)"; then
          run sudo apt-get update -qq
          run sudo apt-get install -y flatpak
        else
          die "Flatpak is required. Install it manually (see README section 1) and re-run this script." "$EXIT_DEPS"
        fi
        ;;
      *)
        die "Flatpak is missing and this distribution is not apt-based. Install Flatpak with your system package manager, add Flathub, and re-run." "$EXIT_DEPS"
        ;;
    esac
  fi

  if ! flatpak remotes --user 2>/dev/null | grep -q '^flathub'; then
    if confirm "Add the Flathub repository for your user account?"; then
      run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    else
      die "Flathub is required to install Protontricks. Add it manually and re-run." "$EXIT_DEPS"
    fi
  fi

  if flatpak_app_installed; then
    log INFO "Updating existing Protontricks installation."
    run flatpak update --noninteractive --user "$PROTONTRICKS_APP_ID" || run flatpak update --noninteractive "$PROTONTRICKS_APP_ID"
  else
    log INFO "Installing Protontricks from Flathub (user installation)."
    run flatpak install --user --noninteractive flathub "$PROTONTRICKS_APP_ID" \
      || run flatpak install --noninteractive flathub "$PROTONTRICKS_APP_ID"
  fi

  select_protontricks || die "Protontricks was installed but did not respond to --version. Inspect the run log and consult docs/troubleshooting.md." "$EXIT_DEPS"
  complete_phase "dependencies"
}

# ---------------------------------------------------------------------------
# 13. Phase: backup (prefix snapshot before any component installation)
# ---------------------------------------------------------------------------
phase_backup() {
  ensure_game_closed
  local size_kb avail_kb backup_target

  size_kb="$(du -sk -- "$COMPATDATA" | cut -f1)"
  avail_kb="$(df -Pk -- "$(dirname -- "$COMPATDATA")" | awk 'NR==2{print $4}')"
  log INFO "Prefix size: ${size_kb} KiB; free space: ${avail_kb} KiB."
  (( avail_kb > size_kb + 262144 )) || die "Not enough free space to back up the prefix (need ~$(( (size_kb + 262144) / 1024 )) MiB). Free space or set --compatdata to another location. Nothing was changed." "$EXIT_BACKUP"

  backup_target="${COMPATDATA}.before-cet-${RUN_ID}"
  if confirm "Create a full backup copy of the prefix now?\n  from: $COMPATDATA\n  to:   $backup_target"; then
    run cp -a -- "$COMPATDATA" "$backup_target"
    [[ -d "$backup_target/pfx" ]] || die "Backup copy finished without an error, but $backup_target/pfx is missing. Do NOT continue; inspect manually." "$EXIT_BACKUP"
    state_set backup_path "$backup_target"
    log SUCCESS "Backup completed: $backup_target"
  else
    die "Refusing to install runtime components without a prefix backup. Re-run and accept the backup, or use --skip-components if you only want the frameworks." "$EXIT_BACKUP"
  fi
  complete_phase "backup"
}

# ---------------------------------------------------------------------------
# 14. Phase: components (winetricks verbs inside the existing prefix)
# ---------------------------------------------------------------------------
phase_components() {
  if (( FLAG_SKIP_COMPONENTS )); then
    log WARN "Skipping runtime components by request (--skip-components)."
    complete_phase "components"
    return 0
  fi

  local component installed_before
  pt_list_installed || true
  installed_before="$CAPTURED"

  for component in "${WINETRICKS_COMPONENTS[@]}"; do
    if grep -qx "$component" <<< "$installed_before"; then
      log INFO "Component already recorded in this prefix: $component (skipping)."
      continue
    fi
    log INFO "Installing Winetricks component: $component"
    if [[ "$component" == "vcrun2022" ]]; then
      log WARN "Note: the CET Linux guide warns that vcrun2022 can break some existing setups. Your prefix backup (created earlier by this script) protects you."
    fi
    if [[ "$component" == "vcrun2022" ]] && ! confirm "Proceed with installing $component into the game prefix?"; then
      die "User declined $component. You can install it later, e.g. with: flatpak run $PROTONTRICKS_APP_ID $APP_ID $component" "$EXIT_COMPONENTS"
    fi
    run pt "$APP_ID" "$component"
    pt_list_installed || true
    if ! grep -qx "$component" <<< "$CAPTURED"; then
      die "Component '$component' did not get recorded after installation. Do NOT retry with --force blindly; see docs/troubleshooting.md." "$EXIT_COMPONENTS"
    fi
    log SUCCESS "Component installed: $component"
  done
  complete_phase "components"
}

# ---------------------------------------------------------------------------
# 15. Phase: download (official archives + SHA-256 verification)
# ---------------------------------------------------------------------------
phase_download() {
  mkdir -p "$WORK_DIR/cet" "$WORK_DIR/red4ext"

  local label url target key
  local cet_download_url red4ext_download_url cet_key red4ext_key expected
  cet_download_url="$(cet_url "$CET_VERSION")"
  red4ext_download_url="$(red4ext_url "$RED4EXT_VERSION")"
  cet_key="cet:$CET_VERSION"
  red4ext_key="red4ext:$RED4EXT_VERSION"

  for pair in "CET|$cet_download_url|$CET_ZIP|$cet_key" "RED4ext|$red4ext_download_url|$RED4EXT_ZIP|$red4ext_key"; do
    IFS='|' read -r label url target key <<< "$pair"
    log INFO "Downloading $label $([[ $label == CET ]] && echo "$CET_VERSION" || echo "$RED4EXT_VERSION") from the official release page:"
    log INFO "  $url"
    if (( FLAG_DRY_RUN )); then
      log INFO "[dry-run] Would download to $target"
      continue
    fi
    run curl -fsSL --retry 3 --retry-delay 2 -o "$target" "$url"
    [[ -s "$target" ]] || die "Download produced an empty file: $target" "$EXIT_DOWNLOAD"

    expected="${CHECKSUMS[$key]:-}"
    if [[ -n "$expected" ]]; then
      verify_sha256 "$target" "$expected" || die "Downloaded archive failed verification. Delete it and investigate; do not install unverified game tools." "$EXIT_DOWNLOAD"
    elif (( FLAG_ALLOW_UNVERIFIED )); then
      log WARN "No pinned checksum known for this version; continuing because --allow-unverified-checksum was supplied."
      log WARN "Verify the archive yourself against the official release page before trusting it."
    else
      die "No pinned checksum for '$key'. Verify the release manually, or pass --allow-unverified-checksum at your own risk." "$EXIT_DOWNLOAD"
    fi
  done
  state_set download_dir "$WORK_DIR"
  complete_phase "download"
}

# ---------------------------------------------------------------------------
# 16. Phase: extract (stage, back up overwritten files, merge into game root)
# ---------------------------------------------------------------------------
phase_extract() {
  ensure_game_closed
  if (( FLAG_DRY_RUN )); then
    log INFO "[dry-run] Would stage and merge $CET_ZIP and $RED4EXT_ZIP into $GAME_DIR"
    complete_phase "extract"
    return 0
  fi
  [[ -f "$CET_ZIP" && -f "$RED4EXT_ZIP" ]] || die "The staged downloads from a previous run are no longer present (temporary directories are cleaned after successful runs). Re-run with --force to download and install again." "$EXIT_EXTRACT"

  local staging="$WORK_DIR/staging"
  mkdir -p "$staging/cet" "$staging/red4ext"

  extract_zip "$CET_ZIP" "$staging/cet"
  extract_zip "$RED4EXT_ZIP" "$staging/red4ext"

  # Sanity-check the staged layout before touching the game folder.
  local required
  for required in cet/bin/x64/plugins/cyber_engine_tweaks.asi cet/bin/x64/version.dll red4ext/bin/x64/winmm.dll red4ext/red4ext/RED4ext.dll; do
    [[ -f "$staging/$required" ]] || die "The staged archive is missing an expected file ($required). The download may be corrupt or a different layout than expected. Nothing was written to your game folder." "$EXIT_EXTRACT"
  done

  # Back up any existing game file that this installation will overwrite.
  OVERWRITE_BACKUP_DIR="$STATE_DIR/overwritten-${RUN_ID}"
  mkdir -p "$OVERWRITE_BACKUP_DIR"
  local entry zip_archive
  for framework in cet red4ext; do
    if [[ "$framework" == "cet" ]]; then zip_archive="$CET_ZIP"; else zip_archive="$RED4EXT_ZIP"; fi
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      [[ -f "$staging/$framework/$entry" ]] || continue
      if [[ -e "$GAME_DIR/$entry" ]]; then
        ( cd -- "$staging/$framework" && cp -a --parents -- "$entry" "$OVERWRITE_BACKUP_DIR/" ) \
          || die "Could not back up the existing file that would be overwritten: $entry" "$EXIT_EXTRACT"
        log INFO "Backed up existing file before overwrite: $entry"
      fi
    done < <( ( cd -- "$staging/$framework" && list_zip_entries "$zip_archive" ) )
  done

  run cp -a -- "$staging/cet/." "$GAME_DIR/"
  run cp -a -- "$staging/red4ext/." "$GAME_DIR/"

  for required in bin/x64/version.dll bin/x64/winmm.dll bin/x64/plugins/cyber_engine_tweaks.asi red4ext/RED4ext.dll; do
    [[ -f "$GAME_DIR/$required" ]] || die "Post-installation verification failed: $required is missing from the game folder." "$EXIT_EXTRACT"
  done
  log SUCCESS "Frameworks extracted and merged into the game folder."
  complete_phase "extract"
}

# ---------------------------------------------------------------------------
# 17. Phase: launch_options (detect by default; patch only with --set-launch-option)
# ---------------------------------------------------------------------------
find_localconfig() { # prints first existing config/localconfig.vdf among Steam roots
  local root
  for root in "${ROOTS[@]:-}"; do
    [[ -z "$root" ]] && continue
    if [[ -f "$root/config/localconfig.vdf" ]]; then
      printf '%s\n' "$root/config/localconfig.vdf"
      return 0
    fi
  done
  return 1
}

phase_launch_options() {
  if (( FLAG_SKIP_LAUNCH )); then
    log INFO "Skipping launch-option handling (--skip-launch-options)."
    complete_phase "launch_options"
    return 0
  fi

  local vdf current
  vdf="$(find_localconfig)" || { log WARN "Steam localconfig.vdf not found; set launch options manually in Steam (README section 5)."; complete_phase "launch_options"; return 0; }
  current="$(vdf_current_launch_options "$vdf")"

  if printf '%s' "$current" | grep -q 'WINEDLLOVERRIDES'; then
    log SUCCESS "Launch options already contain WINEDLLOVERRIDES; nothing to change."
    state_set launch_options "present"
    complete_phase "launch_options"
    return 0
  fi

  if (( ! FLAG_SET_LAUNCH )); then
    cat >&2 <<EOF

${COLOR_YELLOW}Manual step required:${COLOR_RESET}
Open Steam -> Cyberpunk 2077 -> Properties -> General -> Launch Options and set:
  ${LAUNCH_ENVIRONMENT} %command%
Or re-run this script with --set-launch-options to let it patch Steam's
localconfig.vdf automatically (with a backup; Steam must be closed).
EOF
    state_set launch_options "manual"
    complete_phase "launch_options"
    return 0
  fi

  (( HAVE_PYTHON3 )) || die "Patching Steam launch options requires python3. Install python3 or set the options manually in Steam." "$EXIT_LAUNCH_OPTIONS"
  ensure_steam_closed
  local vdf_backup="$STATE_DIR/localconfig.vdf.bak-${RUN_ID}"
  cp -a -- "$vdf" "$vdf_backup" || die "Could not back up $vdf before patching." "$EXIT_LAUNCH_OPTIONS"
  state_set vdf_backup "$vdf_backup"
  log INFO "Backed up Steam configuration to: $vdf_backup"

  local result
  result="$(vdf_apply_override "$vdf")" || result="PATCH_FAILED"
  case "$result" in
    PATCHED)
      state_set launch_options "patched"
      log SUCCESS "Launch options patched. Start Steam afterwards; it will reload the configuration."
      ;;
    ALREADY_PRESENT)
      state_set launch_options "present"
      log INFO "Launch options already contain the override."
      ;;
    APP_BLOCK_MISSING)
      log WARN "Steam has no settings block for app $APP_ID yet. Launch the game once via Steam, then re-run --set-launch-options, or set the options manually."
      state_set launch_options "manual"
      ;;
    *)
      die "Unexpected result while patching launch options: $result (backup kept at $vdf_backup)." "$EXIT_LAUNCH_OPTIONS"
      ;;
  esac
  complete_phase "launch_options"
}

# ---------------------------------------------------------------------------
# 18. Phase: verify (records + files + final guidance)
# ---------------------------------------------------------------------------
phase_verify() {
  local failures=0
  pt_list_installed || true
  local recorded="$CAPTURED"
  local component
  if (( FLAG_SKIP_COMPONENTS )); then
    log WARN "Component verification skipped (--skip-components)."
  else
    for component in "${WINETRICKS_COMPONENTS[@]}"; do
      if grep -qx "$component" <<< "$recorded"; then
        log SUCCESS "Verified component record: $component"
      else
        log ERROR "Component not recorded in this prefix: $component"
        failures=$(( failures + 1 ))
      fi
    done
  fi

  local required
  for required in bin/x64/version.dll bin/x64/winmm.dll bin/x64/plugins/cyber_engine_tweaks.asi red4ext/RED4ext.dll; do
    if [[ -f "$GAME_DIR/$required" ]]; then
      log SUCCESS "Verified game file: $required"
    else
      log ERROR "Missing game file: $required"
      failures=$(( failures + 1 ))
    fi
  done

  (( failures == 0 )) || die "Verification found $failures problem(s) listed above. Consult docs/troubleshooting.md before changing anything else." "$EXIT_VERIFY"

  state_set last_success "$(date '+%Y-%m-%d %H:%M:%S')"
  complete_phase "verify"
  cat <<EOF

${COLOR_GREEN}Installation complete.${COLOR_RESET}
  Prefix backup : $(state_get backup_path unknown)
  Launch options: $(state_get launch_options unknown)

Next steps:
  1. Start Cyberpunk 2077 through Steam with your usual Proton version.
  2. On CET's first successful load, bind the overlay key when prompted
     (there is no universal default key; F8 is just an example choice).
  3. If anything fails, see docs/troubleshooting.md and keep the backup.
     A Proton log can be captured per docs/troubleshooting.md#capture-a-proton-log.
EOF
}

# ---------------------------------------------------------------------------
# 19. Rollback mode (explicit, confirmed prefix restoration)
# ---------------------------------------------------------------------------
do_rollback() {
  local backup current failed_target
  backup="$(state_get backup_path "")"
  [[ -n "$backup" && -d "$backup" && -d "$backup/pfx" ]] || die "No usable prefix backup recorded in $STATE_FILE. Nothing was changed." "$EXIT_ROLLBACK"
  [[ -n "$COMPATDATA" && -d "$COMPATDATA" ]] || die "Live prefix path is unknown; pass --compatdata=/path/to/compatdata-$APP_ID." "$EXIT_ROLLBACK"
  [[ "$(realpath -- "$COMPATDATA")" != "$(realpath -- "$backup")" ]] || die "The recorded backup points at the live prefix; refusing to roll back onto itself." "$EXIT_ROLLBACK"

  ensure_game_closed
  echo "About to restore the prefix from:"; printf '  %s\n' "$backup"
  echo "The current prefix will first be preserved at <compatdata>.after-failed-change-<timestamp>."
  confirm "Proceed with rollback?" || die "Rollback declined; nothing was changed." "$EXIT_ROLLBACK"

  failed_target="${COMPATDATA}.after-failed-change-$(date +%Y%m%d-%H%M%S)"
  run mv -- "$COMPATDATA" "$failed_target"
  run cp -a -- "$backup" "$COMPATDATA"
  [[ -d "$COMPATDATA/pfx" ]] || die "Restore finished without an error but the prefix is missing; the previous live prefix is preserved at $failed_target." "$EXIT_ROLLBACK"
  log SUCCESS "Rollback completed. Previous prefix preserved at: $failed_target"
  log INFO "Note: Steam launch options are not reverted automatically. See $(state_get vdf_backup 'no configuration backup') if one was made."
}

# ---------------------------------------------------------------------------
# 20. Self-test (offline unit checks of internal helpers)
# ---------------------------------------------------------------------------
self_test() {
  command -v python3 >/dev/null 2>&1 && HAVE_PYTHON3=1
  command -v unzip >/dev/null 2>&1 && HAVE_UNZIP=1
  local failures=0
  pass() { printf 'PASS  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }

  # URL builders
  if [[ "$(cet_url 1.38.0)" == *"cet_1_38_0.zip" ]]; then
    pass "cet_url builds official asset name"
  else
    fail "cet_url"
  fi
  if [[ "$(red4ext_url 1.31.0)" == *"red4ext-1.31.0.zip" ]]; then
    pass "red4ext_url builds official asset name"
  else
    fail "red4ext_url"
  fi

  # State store round-trip
  local tmp; tmp="$(mktemp -d)"; STATE_FILE="$tmp/state.ini"
  state_set alpha one; state_set beta "two words"; state_set alpha "one-again"
  if [[ "$(state_get alpha)" == "one-again" && "$(state_get beta)" == "two words" && "$(state_get missing default)" == "default" ]]; then
    pass "state store round-trip"
  else
    fail "state store"
  fi

  # Checksum verification (good and tampered)
  printf 'hello\n' > "$tmp/f"
  local good; good="$(sha256sum "$tmp/f" | awk '{print $1}')"
  if verify_sha256 "$tmp/f" "$good"; then
    pass "checksum accepts matching file"
  else
    fail "checksum good"
  fi
  if verify_sha256 "$tmp/f" "${good%?}0" 2>/dev/null; then fail "checksum rejects mismatch"; else pass "checksum rejects mismatch"; fi

  # Redaction
  # shellcheck disable=SC2088  # the tilde is the literal expected output here
  local expected_redacted='~/.secret'
  if [[ "$(printf '/home/alice/.secret\n' | redact)" == "$expected_redacted" ]]; then
    pass "redaction masks home paths"
  else
    fail "redaction"
  fi

  # VDF detect/patch round-trip
  if command -v python3 >/dev/null 2>&1; then
    cat > "$tmp/localconfig.vdf" <<'VDF'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"1091500"
					{
						"LaunchOptions"		"-skipIntro -other"
					}
				}
			}
		}
	}
}
VDF
    if [[ "$(vdf_current_launch_options "$tmp/localconfig.vdf")" == *'-skipIntro'* ]]; then
      pass "vdf detect reads existing options"
    else
      fail "vdf detect"
    fi
    vdf_apply_override "$tmp/localconfig.vdf" >/dev/null
    local patched; patched="$(vdf_current_launch_options "$tmp/localconfig.vdf")"
    if [[ "$patched" == 'WINEDLLOVERRIDES="winmm,version=n,b" -skipIntro -other' ]]; then
      pass "vdf patch prepends override, escapes quotes, preserves options"
    else
      fail "vdf patch merge (got: $patched)"
    fi
    local again; again="$(vdf_apply_override "$tmp/localconfig.vdf" 2>/dev/null || true)"
    if [[ "$again" == "ALREADY_PRESENT" ]]; then
      pass "vdf patch is idempotent"
    else
      fail "vdf idempotency (got: $again)"
    fi
  else
    printf 'SKIP  vdf tests (python3 unavailable)\n'
  fi

  rm -rf -- "$tmp"
  if (( failures == 0 )); then
    printf '%sAll self-tests passed.%s\n' "$COLOR_GREEN" "$COLOR_RESET"
    return 0
  fi
  printf '%s%s self-test failure(s).%s\n' "$COLOR_RED" "$failures" "$COLOR_RESET" >&2
  return 1
}

# ---------------------------------------------------------------------------
# 21. CLI parsing and entry point
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
$SCRIPT_NAME $SCRIPT_VERSION — guided Cyberpunk 2077 (Steam/Proton) modding installer
Installs RED4ext + Cyber Engine Tweaks into the game's existing Proton prefix.

Usage: $SCRIPT_NAME [options]

General options:
  -h, --help                     Show this help and exit.
  -V, --version                  Print version and exit.
  -n, --dry-run                  Show what would happen without changing anything.
  -y, --yes                      Answer "yes" to every confirmation prompt.
  -q, --quiet                    Less console output (everything still logged).
      --no-color                 Disable colored output.
      --force                    Replay all phases even if previously completed.
      --self-test                Run offline unit tests of the script's helpers.

Selection options:
      --appid=N                  Steam app id (default: $APP_ID_DEFAULT).
      --game-dir=PATH            Explicit path to the "Cyberpunk 2077" folder.
      --compatdata=PATH          Explicit path to the compatdata folder (contains pfx).
      --cet-version=V            CET version to download (default: $CET_VERSION_DEFAULT).
      --red4ext-version=V        RED4ext version to download (default: $RED4EXT_VERSION_DEFAULT).

Behavior options:
      --skip-components          Skip winetricks components (d3dcompiler_47/vcrun2022).
      --set-launch-options       Patch Steam's localconfig.vdf (backup made; Steam must be closed).
      --skip-launch-options      Do not check or mention launch options.
      --allow-unverified-checksum Permit versions without a pinned SHA-256 (risk!).
      --rollback                 Restore the prefix from the recorded backup (interactive).

Typical usage:
  $SCRIPT_NAME --dry-run          # inspect the plan
  $SCRIPT_NAME                    # guided installation (backs up first)
  $SCRIPT_NAME --rollback         # undo a failed experiment
EOF
}

parse_args() {
  SCRIPT_ARGS=("$@")
  while (( $# )); do
    case "$1" in
      -h|--help)         usage; exit "$EXIT_OK" ;;
      -V|--version)      printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit "$EXIT_OK" ;;
      -n|--dry-run)      FLAG_DRY_RUN=1 ;;
      -y|--yes)          FLAG_ASSUME_YES=1 ;;
      -q|--quiet)        FLAG_QUIET=1 ;;
      --no-color)        FLAG_NO_COLOR=1 ;;
      --force)           FLAG_FORCE=1 ;;
      --self-test)       FLAG_SELF_TEST=1 ;;
      --skip-components) FLAG_SKIP_COMPONENTS=1 ;;
      --skip-launch-options) FLAG_SKIP_LAUNCH=1 ;;
      --set-launch-options)  FLAG_SET_LAUNCH=1 ;;
      --allow-unverified-checksum) FLAG_ALLOW_UNVERIFIED=1 ;;
      --rollback)        FLAG_ROLLBACK=1 ;;
      --appid=*)         OPT_APP_ID="${1#*=}" ;;
      --game-dir=*)      OPT_GAME_DIR="${1#*=}" ;;
      --compatdata=*)    OPT_COMPATDATA="${1#*=}" ;;
      --cet-version=*)   OPT_CET_VERSION="${1#*=}" ;;
      --red4ext-version=*) OPT_RED4EXT_VERSION="${1#*=}" ;;
      *) usage_error "Unknown option: $1" ;;
    esac
    shift
  done
}

init_runtime() {
  STATE_DIR="${CYBERPUNK_MODDER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/cyberpunk-linux-modder}"
  LOG_DIR="$STATE_DIR/logs"
  STATE_FILE="$STATE_DIR/state.ini"
  mkdir -p "$LOG_DIR"
  RUN_LOG="$LOG_DIR/run-${RUN_ID}.log"
  : > "$RUN_LOG"
  WORK_DIR="$STATE_DIR/tmp/run-${RUN_ID}"
  CET_ZIP="$WORK_DIR/cet/cet_${CET_VERSION//./_}.zip"
  RED4EXT_ZIP="$WORK_DIR/red4ext/red4ext-${RED4EXT_VERSION}.zip"

  APP_ID="${OPT_APP_ID:-$APP_ID_DEFAULT}"
  [[ "$APP_ID" =~ ^[0-9]+$ ]] || die "--appid must be numeric (Steam app ids are numbers)." "$EXIT_USAGE"
  CET_VERSION="${OPT_CET_VERSION:-$CET_VERSION_DEFAULT}"
  RED4EXT_VERSION="${OPT_RED4EXT_VERSION:-$RED4EXT_VERSION_DEFAULT}"
  [[ "$CET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$RED4EXT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "Version arguments must look like 1.38.0." "$EXIT_USAGE"

  local mode_label="live"
  (( FLAG_DRY_RUN )) && mode_label="dry-run"
  log INFO "$SCRIPT_NAME $SCRIPT_VERSION starting ($mode_label mode)"
  log INFO "State directory: $STATE_DIR"
  log DEBUG "Script location : $SCRIPT_DIR"
}

main() {
  parse_args "$@"
  init_colors
  init_runtime
  trap 'on_crash $?' ERR
  trap 'on_exit' EXIT
  trap 'EXPECTED_FAIL=1; log WARN "Interrupted."; exit 130' INT TERM

  if (( FLAG_SELF_TEST )); then
    local st=0
    self_test || st=$?
    exit "$st"
  fi

  if (( FLAG_ROLLBACK )); then
    do_rollback
    exit "$EXIT_OK"
  fi

  for phase in "${PHASES[@]}"; do
    if phase_is_done "$phase" && (( ! FLAG_FORCE )); then
      log INFO "Phase '$phase' already completed in a previous run; skipping (--force to redo)."
      CURRENT_PHASE="$phase"
      continue
    fi
    begin_phase "$phase"
    "phase_${phase}"
  done

  cleanup_workdir
}

main "$@"
