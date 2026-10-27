# The installer script: how it works

`cyberpunk-linux-modder.sh` is a guided installer for Cyber Engine Tweaks (CET) and RED4ext on the Steam/Proton version of Cyberpunk 2077. This document explains every layer, how the pieces interconnect, how to configure it, how failures are handled, and how to extend it. For what the error messages mean once a mod is installed, see [troubleshooting](troubleshooting.md).

## Quick start

```sh
# from a copy of this repository
./cyberpunk-linux-modder.sh --help        # read the options
./cyberpunk-linux-modder.sh --self-test   # offline unit checks
./cyberpunk-linux-modder.sh --dry-run     # see the plan for your machine
./cyberpunk-linux-modder.sh               # guided installation
./cyberpunk-linux-modder.sh --rollback    # undo a failed experiment
```

The script never downloads from mirrors or this repository. It fetches only from the official release pages of each project and verifies pinned SHA-256 checksums. It never deletes your prefix; restoration is a separate, confirmed `--rollback`.

## What it does, end to end

- Finds your Steam libraries, the Cyberpunk 2077 folder, and the game's existing Proton prefix.
- Installs Flatpak Protontricks if needed (one clearly prompted `sudo apt-get` on apt distributions).
- Backs up the entire prefix before touching runtime components.
- Installs `d3dcompiler_47` and `vcrun2022` into that prefix through Protontricks, skipping what is already recorded.
- Downloads the pinned CET and RED4ext archives from GitHub, verifies checksums, stages them, backs up any file it is about to overwrite, and merges them into the game folder.
- Detects (and, only with `--set-launch-options`, patches) the Steam launch-option environment variable.
- Verifies everything and writes a resumable state file so re-runs skip completed work.

What it does **not** do: install mods from Nexus (those require your logged-in account, so grab them manually into the game folder as usual), touch driver or Proton versions, delete or "repair" prefixes, or run anything as root without showing the exact command first.

## Layered architecture

The script is organized as seven layers. Lower layers never call upward; each higher layer composes the ones below it.

```text
┌──────────────────────────────────────────────────────────────┐
│ 6. Entry point          parse_args · init_runtime · main     │
│    flags → config → phase loop → cleanup                     │
├──────────────────────────────────────────────────────────────┤
│ 5. Phase pipeline       preflight · dependencies · backup    │
│                         components · download · extract      │
│                         launch_options · verify · rollback   │
├──────────────────────────────────────────────────────────────┤
│ 4. Domain helpers       steam_roots · libraries_in_root      │
│                         locate_installation · pt()/protontricks │
│                         vdf_python · list_zip_entries        │
│                         cet_url · red4ext_url · verify_sha256│
├──────────────────────────────────────────────────────────────┤
│ 3. Execution helpers    run()      mutating, dry-run aware   │
│                         capture()  read-only, returns output │
│                         confirm()  prompts, --yes/--dry-run  │
├──────────────────────────────────────────────────────────────┤
│ 2. Observability        log() · section() · redact()         │
│                         write_crash_report() · traps         │
├──────────────────────────────────────────────────────────────┤
│ 1. State machine        state_set/get · phase markers        │
│                         PHASES array · resume logic          │
├──────────────────────────────────────────────────────────────┤
│ 0. Foundation           set -Eeuo pipefail · strict IFS      │
│    config constants     versions, checksums, paths           │
└──────────────────────────────────────────────────────────────┘
```

### Layer 0: foundation and configuration

Strict mode (`set -Eeuo pipefail`, `IFS=$'\n\t'`) makes unexpected failures loud: any unhandled nonzero status raises the `ERR` trap, which is the hook for crash reporting. All user-tunable constants live at the top of the file: default app id `1091500`, game folder name, pinned CET/RED4ext versions, the `WINETRICKS_COMPONENTS` array, the `LAUNCH_ENVIRONMENT` string, the pinned `CHECKSUMS` map, and the `PHASES` order. Everything else derives from flags or detection. If you only ever edit one place, edit this block.

### Layer 1: state machine

Progress is stored as simple `key=value` lines in `state.ini` under the state directory (default `~/.local/state/cyberpunk-linux-modder/`, override with `CYBERPUNK_MODDER_STATE_DIR` or `XDG_STATE_HOME`). `state_set`/`state_get` are deliberately dumb so the file stays human-readable. Each phase ends with `complete_phase`, which sets `phase_<name>=1`. On the next run, `main` skips any marked phase unless you pass `--force`. Failure during a phase leaves its marker unset, so a re-run resumes exactly there — for example after fixing a connectivity problem during `download`.

### Layer 2: observability and crash handling

`log` writes every line, timestamped and leveled, both to the console and to `logs/run-<timestamp>.log`. `section` renders the bold phase banner. `redact` rewrites `/home/<user>/` to `~/` for anything destined to be shared.

Three traps cooperate:

- `trap 'on_crash $?' ERR` — on any unexpected failure, `on_crash` captures the failing command and status, calls `write_crash_report`, prints a short explanation with a phase-specific hint, and exits with the original status.
- `trap 'on_exit' EXIT` — on success prints the log location; if the exit status is nonzero and neither a crash report nor an expected exit already handled it, it routes through `on_crash` as a safety net.
- `INT`/`TERM` — Ctrl-C marks the run as user-interrupted (`EXPECTED_FAIL=1`), so you get a clean exit 130 instead of a scary crash report.

`die` is the *expected*-failure path (bad input, missing prerequisite, declined confirmation): it prints a clear message, sets `EXPECTED_FAIL=1`, and exits with the phase's exit code — no crash report, because there is nothing mysterious to investigate.

A crash report (`logs/crash-<timestamp>.log`) contains: timestamp, script version, failed phase, failing command, exit status, options used, Bash/kernel/OS identification, the last 40 log lines with home paths redacted, the suggested next step for that phase, and — if a prefix backup exists — its location plus rollback instructions. It ends with a reminder to review before posting anywhere.

### Layer 3: execution helpers

Every mutating action goes through `run`, and every read-only probe goes through `capture`. This separation is what makes `--dry-run` trustworthy: `run` prints `Would run: …` and does nothing, while `capture` still executes because listing installed components or parsing a VDF changes nothing.

`run` tees the command's output into the run log, and `pipefail` propagates a child's failure through the pipeline into the `ERR` trap. `capture` stores output in the global `CAPTURED` and returns the child's status; callers decide whether a nonzero status is fatal.

`confirm` is the consent gate. With `--yes` it logs the assumption; with `--dry-run` it logs what it would ask; otherwise it reads an answer from the terminal (falling back to stdin when no tty exists, and failing safely when it can neither prompt nor assume).

### Layer 4: domain helpers

- **Steam discovery.** `steam_roots` collects plausible Steam data roots (native `~/.local/share/Steam`, the `~/.steam` symlinks, Flatpak's `~/.var/app/com.valvesoftware.Steam/...`, Snap's library, plus an explicit `STEAM_ROOT` override). `libraries_in_root` extracts `"path"` entries from each root's `steamapps/libraryfolders.vdf` — with python3 when present, a `sed` fallback otherwise. `locate_installation` walks those libraries to find `steamapps/common/Cyberpunk 2077` and `steamapps/compatdata/<appid>/pfx`. `--game-dir` and `--compatdata` override either half. If the prefix is missing, the message tells you to launch the game once under Proton first, because Proton creates the prefix on first run.
- **Protontricks selection.** `flatpak_app_installed` checks the user and system Flatpak installations; `select_protontricks` prefers the Flatpak app (the officially recommended packaging), falls back to a native `protontricks` with a warning when Flatpak is absent, and reports failure otherwise. `pt` invokes whichever was selected; `pt_list_installed` wraps the `list-installed` probe used by the components and verify phases.
- **VDF editing.** `vdf_python` embeds a small Python worker that, in `detect` mode, prints the stored `LaunchOptions` string for your app id (human-readable, with VFD quote-escapes decoded). In `patch` mode it scans brace depth to find the app's block, prepends the override environment if `WINEDLLOVERRIDES` is not already present, escapes quotes for the VDF format, writes to a temporary file, and atomically replaces the original. It is idempotent (`ALREADY_PRESENT`) and never invents an app block: if Steam has never stored settings for the game, it reports that so you can launch once or set the option manually.
- **Archives and integrity.** `list_zip_entries` enumerates archive members (unzip, or python3's zipfile as fallback); `extract_zip` extracts with whichever engine exists; `verify_sha256` compares a computed digest to the pinned one. `cet_url`/`red4ext_url` build the official download URLs for a version — CET's asset naming (`cet_1_38_0.zip`) is derived from the dotted version programmatically.

### Layer 5: the phase pipeline

`PHASES` is the single source of truth for ordering: `preflight dependencies backup components download extract launch_options verify`. `main` iterates it, calls `begin_phase` (banner + `CURRENT_PHASE`), dispatches to `phase_<name>` by name, and expects each phase to call `complete_phase` on success. Adding a phase means adding one function and one array entry.

- **preflight** — validates bash version, refuses root, checks required commands, notes the distribution, locates game + prefix, ensures the game is closed, and probes Protontricks. Failures here are `die`-grade: nothing has been changed.
- **dependencies** — only runs when Protontricks is not yet usable. Installs Flatpak on apt distributions after showing the command and asking; adds the Flathub remote for your user; installs (or updates) `com.github.Matoking.protontricks`; then re-selects and records the working invocation. Non-apt distributions get manual instructions instead of blind package-manager guesses.
- **backup** — measures the prefix, checks free space (with margin), and copies the whole `compatdata/<appid>` tree to a sibling `compatdata/<appid>.before-cet-<timestamp>` after you confirm. The copy is verified by requiring `pfx/` inside it, and the path is recorded in state for `--rollback` and crash reports. Without a backup the script refuses to continue into runtime changes.
- **components** — for each entry of `WINETRICKS_COMPONENTS`: skip if `list-installed` already records it; otherwise run the verb through Protontricks. `vcrun2022` carries an explicit warning plus a confirmation because the official Linux guide notes it can break some existing setups — the backup from the previous phase is the safety net. A component that does not appear in `list-installed` afterwards is a hard stop, not a silent continuation.
- **download** — resolves both official URLs, downloads with curl retries, and verifies pinned checksums. Overriding a version without a pinned checksum requires `--allow-unverified-checksum`, and even then the script refuses to pretend the risk away: it warns in plain language. Staged archives land in the per-run work directory.
- **extract** — re-checks the game is closed, validates the staged layout (the four files that must exist: CET's `version.dll` and `cyber_engine_tweaks.asi`, RED4ext's `winmm.dll` and `RED4ext.dll`), backs up every existing game file that is about to be overwritten into the persistent state directory (`overwritten-<timestamp>/`, deliberately outside the cleaned temp area), merges both trees into the game folder, and verifies the four key files.
- **launch_options** — reads the stored launch options. Three outcomes: already contains the override (nothing to do), patch requested via `--set-launch-options` (backs up `localconfig.vdf` into the state directory, requires Steam to be fully closed, applies the atomic patch, verifies), or instructs you to paste `WINEDLLOVERRIDES="winmm,version=n,b" %command%` into Steam yourself. Launch options are only ever *added to*, never replaced, and a manual path is always available.
- **verify** — re-runs `list-installed` and file checks, tallies failures, and prints the final summary: backup path, launch-option status, next steps (bind the overlay key on first load, where logs live, where to get help). Respect `--skip-components` by warning instead of failing.

### Rollback mode

`--rollback` is intentionally separate from normal operation. It refuses to act without a recorded backup that is distinct from the live prefix, requires the game to be closed, moves the current prefix aside to `compatdata/<appid>.after-failed-change-<timestamp>` (rather than deleting it), copies the backup into place, verifies, and prints the preserved path. It does not revert Steam launch options automatically; if a configuration backup was made, its path is printed.

### Exit codes

- `0` success; `1` unexpected failure (crash report written); `2` usage error
- `3` preflight; `4` dependencies; `5` backup; `6` components; `7` download; `8` extract; `9` launch options; `10` verify; `11` rollback

Shell users can branch on these; the mapping is also printed into crash reports via the failing phase.

## How a run flows, start to finish

1. `main` parses flags into `OPT_*`, `init_runtime` derives versions, work directory, and archive paths, and the traps are installed.
2. The phase loop marks `CURRENT_PHASE` and dispatches; resume markers short-circuit completed phases.
3. `preflight` populates `ROOTS`, `GAME_DIR`, `COMPATDATA`, `PT_MODE`; later phases consume those globals — this is the principal way the phases interlock.
4. `backup` records `backup_path` in state; `components` relies on it for its safety story; crash reports surface it; `--rollback` acts on it.
5. `download` pins archives and checksums into `WORK_DIR`; `extract` consumes them, records `overwritten-<ts>`; `launch_options` reads Steam's config and optionally records `vdf_backup`; `verify` reads everything and stamps `last_success`.
6. Cleanup removes the per-run temp directory (honoring `KEEP_WORKDIR=1` for debugging), and the `EXIT` trap prints the success banner and log path.

Failure anywhere re-enters at the failed phase on the next run thanks to the state markers, and the crash report's hint matches the phase that failed.

## Configuration reference

Flags: `--help`, `--version`, `--dry-run`, `--yes`, `--quiet`, `--no-color`, `--force`, `--self-test`, `--appid=`, `--game-dir=`, `--compatdata=`, `--cet-version=`, `--red4ext-version=`, `--skip-components`, `--skip-launch-options`, `--set-launch-options`, `--allow-unverified-checksum`, `--rollback`.

Environment: `STEAM_ROOT` (explicit Steam data dir), `CYBERPUNK_MODDER_STATE_DIR` (state/logs root), `XDG_STATE_HOME` (standard base), `KEEP_WORKDIR=1` (retain staged downloads for inspection), `NO_COLOR` (respected automatically).

Editable constants (top of script): app id, folder name, versions, `WINETRICKS_COMPONENTS`, `LAUNCH_ENVIRONMENT`, `PHASES`, `CHECKSUMS`.

## Version overrides and checksums

The pinned pairs cover exactly the versions this guide documents (CET 1.38.0 for patch 2.5, RED4ext 1.31.0). Override versions only when a release's own notes say it supports your game build; the script will demand `--allow-unverified-checksum` for any version without a pinned digest. After verifying a new archive yourself, add its digest to `CHECKSUMS` so future runs are protected.

## Extending the script

- **Add a Winetricks component** (for example for a different framework's requirement): append the verb to `WINETRICKS_COMPONENTS`. The components, verify, and hint layers pick it up automatically. Check the component's upstream documentation first, and remember the prefix backup exists because components can clash.
- **Add another framework**: extend `PHASES` only if ordering demands it; otherwise teach the `download`/`extract` loop about the new archive (URL builder, checksum key, staged-layout check, key-file verification). Keep every check — the script's trustworthiness comes from refusing assumptions.
- **Add a verification file**: append the game-relative path to the list in `phase_extract` and `phase_verify`.

## Testing and verification

- `--self-test` runs offline: URL construction, state round-trips, checksum acceptance/rejection, redaction, and the full VDF detect/patch/idempotency cycle on a fixture — no Steam, no network, no game files.
- `--dry-run` executes all read-only discovery against your real machine and prints the plan; it never mutates anything.
- `bash -n` and ShellCheck (style level) must stay clean; the continuous health of these layers is documented in [CONTRIBUTING](../CONTRIBUTING.md).
- What has *not* been automated here: the script's happy path against a live Steam installation. Real-world reports (including the issue tracker) are the evidence base for that.

## Known limitations

- Nexus-hosted mods and gated downloads cannot be scripted; the frameworks above are the automatable part. Manual mod folders still follow [the ordinary mod installation steps](../README.md#7-add-other-mods-carefully).
- The `localconfig.vdf` patcher covers the common Steam schema; exotic setups should use the manual instructions the script prints.
- Resume across sessions expects the previous run's temp directory to exist; after cleanup, use `--force` to redo `download` + `extract`.
- Windows-specific mod managers are out of scope on purpose.

## Design rationale

Backups before runtime changes, checksums before extraction, confirmations before irreversible-looking actions, and explicit fallbacks instead of silent substitutions all come from the same incident this guide grew out of: an Error 998 that had several plausible causes and one reliable order of operations. The script encodes that order, documents every assumption, and when something unexpected happens it stops, explains, and hands you the evidence instead of improvising.
