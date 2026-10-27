# Changelog

## 1.1.0 — 26 October 2026

Added the guided installer `cyberpunk-linux-modder.sh`: phased execution with resumable state, offline self-tests, a dry-run plan mode, a verified prefix backup before any runtime change, checksum-pinned downloads from official release pages, overwrite-file backups, launch-option detection with an opt-in Steam configuration patch, redacted crash reports with per-phase next-step hints, and a separate, confirmed `--rollback`.

Added the installer architecture reference (`docs/installer.md`) documenting every layer, phase, exit code, configuration knob, and extension point. Updated the contribution policy and issue forms for script reports. The script is MIT-licensed; the documentation remains CC BY 4.0. The script has passed `bash -n`, ShellCheck (style), and its offline self-tests; it has not been executed against a live game installation by the tooling, and it contains no personal data.

## 1.0.0 — 25 October 2026

Initial documentation release covering a version-specific Linux modding setup and official prerequisites.

The guide covers Cyberpunk 2077 2.5, CET 1.38.0, RED4ext 1.31.0, and Proton 11.0-2 on Linux Mint. It includes explicit Flatpak Protontricks commands, prefix backup before runtime changes, official download links, the Visual C++ 2022 prerequisite, the combined DLL override, and CET's first-run overlay binding.

Troubleshooting covers the Steam metadata parser's “Invalid file magic number” failure, ASI Loader Error 998, absent overlay prompts, empty logs, installation warnings, and scoped Flatpak access to extra Steam libraries. Separate recovery instructions preserve the current prefix rather than deleting it.

Original text only: no game or mod binaries, third-party images, or raw user logs. Issue forms request reproducible version information and redacted diagnostics. Version scope and validation limits are explicitly documented; no universal compatibility claim is made.
