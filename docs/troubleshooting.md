# Cyberpunk 2077 Linux troubleshooting: Protontricks, CET and RED4ext

Use this page when the main [installation guide](../README.md) does not produce a working CET overlay. Record the exact failing step before changing the setup. An error in Protontricks, an error loading a framework, and an invisible overlay are different problems.

Read the [version scope and validation limits](tested-setup.md) before applying version-specific instructions. Error 998 does not have one established universal cause. Documentation checked: 25 October 2026.

## SyntaxError: Invalid file magic number

Typical terminal ending:

```text
SyntaxError: Invalid file magic number
```

If the traceback is inside Protontricks' `iter_appinfo_sections` or Steam metadata parser, the failure occurs before Wine configuration and before CET loads. An old Protontricks version may not understand Steam's `appinfo.vdf` format. The official project has reports of this failure after Steam metadata changes. [1]

Check the selected native command:

```bash
protontricks --version
command -v protontricks
```

A path such as `/usr/bin/protontricks` identifies the executable, not its exact package age. Do not infer the version solely from the path.

Install or update Flatpak Protontricks using [the main guide](../README.md#1-install-or-update-flatpak-protontricks), then invoke it explicitly:

```bash
flatpak run com.github.Matoking.protontricks 1091500 --gui
```

Using a current Flatpak copy is a targeted test for an outdated native package. Not all metadata errors come from outdated packages. If a current Flatpak copy fails in the same parser, record its version and full traceback and consult the [official Protontricks issue tracker](https://github.com/Matoking/protontricks/issues). Do not delete the game prefix or Steam metadata as the first experiment. [2]

## Command 'flatpak' not found

Flatpak itself is unavailable; the command has not installed or launched Protontricks yet.

On Linux Mint or Ubuntu, follow the package-manager and Flathub steps in [the main guide](../README.md#if-flatpak-is-missing-on-linux-mint-or-ubuntu). Other distributions need their own package-manager instructions. Do not run a Windows installer merely to solve a missing Linux command.

## XDG_DATA_DIRS or deprecated --socket warnings

Flatpak's export-path warning says applications may not appear in the desktop menu until the session restarts. It is about desktop integration. The Steam runtime's deprecated `--socket` message is a warning about its invocation.

Neither warning, by itself, establishes the cause of CET's Error 998. A warning is not a reason to ignore a later actual abort: inspect the command's final result.

Restart after first setting up Flatpak as the official setup guide recommends, but do not rewrite environment files or change DLL overrides solely to silence these warnings. [3]

## You are using a 64-bit WINEPREFIX

Proton uses 64-bit prefixes. The official Protontricks troubleshooting page says this warning can be ignored **if the command otherwise works**. Do not turn Cyberpunk's prefix into a new 32-bit prefix to suppress it. A traceback, failed download, or installer abort still needs attention. [4]

## ASI Loader Error 998 and no CET overlay

Typical dialog:

```text
Unable to load cyber_engine_tweaks.asi. Error: 998
```

The dialog reports that CET's ASI module did not load. Microsoft defines error 998 as `ERROR_NOACCESS`, meaning invalid access to a memory location. The number alone does not identify a missing runtime, a permissions problem, bad RAM, or a particular incompatible mod. [5]

The base game can continue to its menu after the ASI error. That is not evidence that CET loaded. F8 or the tilde key cannot open an overlay that failed to initialize; F8 is only an example of a key you may choose after CET's binding prompt appears. [6]

### Check these facts before another installation change

1. **Version compatibility.** Read the notes for the installed CET and RED4ext releases. CET 1.38.0 supports Cyberpunk 2.5; its release notes reject earlier game patches. Do not mix that release with an older game based on a stale generic description. [7]
2. **Required loader.** CET 1.38.0's versioned README requires RED4ext first. The official loader archive is not the SDK or symbols package. Confirm `bin/x64/winmm.dll` and `red4ext/RED4ext.dll` were extracted into the game root. [8]
3. **Documented components.** RED4ext's installation page explicitly requires Visual C++ Redistributable 2022, and the Linux guide lists `d3dcompiler_47` as well as `vcrun2022`. Back up the actual prefix before a runtime change. [9] [10]
4. **Launch options.** Preserve other arguments and use one combined definition: `WINEDLLOVERRIDES="winmm,version=n,b" %command%`. Check spelling, quoting, and whether the edited Steam entry is the one you launch. [10]
5. **Current logs.** Read logs from the latest failed attempt, not an old successful run. Their contents may point to an incompatible release or another plugin. A missing or empty file is not a complete diagnosis.

Run this to inspect Winetricks' records:

```bash
flatpak run com.github.Matoking.protontricks 1091500 list-installed
```

It reads `winetricks.log`; it is not an inventory of every runtime DLL. Steam or another installer may have supplied components not recorded there. [11]

**When the runtime requirement is unmet:** back up the prefix and supply RED4ext's documented Visual C++ 2022 prerequisite before assuming the framework is fully installed. This is a requirement check, not proof of the exact failing DLL or a reason to replace runtimes in an already-working installation. [9]

If your prerequisites already match, stop adding components at random. Capture the Proton log below. Do not start with a new prefix, DLL renaming tricks, `chmod 777`, or a full game reinstall.

## RED4ext log is empty or CET log is missing

The RED4ext docs give `red4ext/logs/red4ext.log` as an example. A release may instead use a timestamped name such as `red4ext-YYYY-MM-DD-HH-MM-SS.log`. Look in the **logs directory**, not only for one exact basename. The logging configuration also describes rotation at game start. [12]

Close the game, inspect the newest file, and confirm it actually contains text. An empty file can show that a file was created without providing evidence of successful initialization. Do not call it a successful RED4ext launch just because the filename exists.

CET's documented log location, relative to the game root, is:

```text
bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.log
```

Its troubleshooting guide explains that a missing CET log means CET is not starting normally. Inspect installation and loader errors before treating the issue as a forgotten keybind. [13]

### Capture a Proton log

Save the original Steam launch options. If you use the guide's simple override line, temporarily change it to:

```text
PROTON_LOG=1 WINEDLLOVERRIDES="winmm,version=n,b" %command%
```

If you have additional arguments, preserve them and add only `PROTON_LOG=1` before the existing command. Keep the same Proton version and existing prefix for the test.

Launch until the problem occurs, then exit the game completely. By default Valve's logging option writes a file named `steam-1091500.log` in the home directory. A custom `PROTON_LOG_DIR` or sandboxed launch environment can change where it appears. [14]

Typical default location:

```text
$HOME/steam-1091500.log
```

After the diagnostic run, remove **only** `PROTON_LOG=1` to stop logging. Keep the loader overrides. Redact credentials, account information, usernames and private paths before sharing any log publicly. Do not upload unreviewed complete logs to an issue just because a form accepts attachments.

## vcrun2022 installation warns, fails, or appears already installed

Wine may print `fixme`, stub, or warning messages while an installer continues. Downloads and installer steps may continue despite these messages. That does not make every warning harmless.

A download completing is not the same as the runtime installer succeeding. Look for an actual abort, checksum mismatch, installer failure message, or return to the terminal after successful completion. Verify the Winetricks record and then test the game.

If installation fails, save the full output and any Microsoft installer log. Do **not** automatically use `--force`, delete runtime DLLs, downgrade to `vcrun2019`, or repeatedly reinstall components. The CET Linux guide warns about runtime changes breaking setups, so maintain the backup. [15]

If the previously working game stops launching, use [non-destructive recovery](backup-and-recovery.md), then recheck the game without the failed runtime change. Restoring a prefix backup does not undo separately changed files in the game folder.

## Steam library on another drive or Flatpak access denied

Flatpak Protontricks may lack access to an additional Steam library. The official project documents adding filesystem permission for the **specific library path**. Do not grant access to the entire filesystem when a scoped library permission is enough. [2]

For a user-installed Flatpak application, replace the example path with your actual library:

```bash
flatpak override --user --filesystem="/path/to/SteamLibrary" com.github.Matoking.protontricks
```

This is an optional permission change for an access problem, not a fix for every missing game or Error 998. It does not create a prefix. If you installed the application system-wide or use custom prefix paths, consult the official instructions for that installation rather than assuming this example fits it.

## Protontricks cannot find the game or the prefix

Confirm the Steam copy has been launched at least once under Proton and that you selected the correct installation. The Steam store app ID for Cyberpunk is `1091500`; a non-Steam shortcut can have a different ID. The CET guide describes searching for the shortcut instead. [15]

Do not use the system's generic `~/.wine` prefix for a Steam game. Do not create a new prefix from a dropdown to make the error disappear; that new prefix would not be the game's existing configuration.

For games launched directly through Heroic, Lutris, or Bottles, use the launcher-specific prefix and its tooling. The Steam commands in this repository are not a complete tutorial for those launchers.

## Frameworks load, but the overlay is invisible

If the ASI loading error is gone and CET has initialized, use the **key you actually bound**, not a presumed default. The first-run prompt lets you choose the key. [6]

For display conflicts, try Windowed Borderless mode and disable interfering overlays as CET's installation guide recommends. Do not reinstall runtimes solely because you forgot a working overlay key. [16]

## Ask for help with useful evidence

Use the repository's installation-problem issue form. Include the distribution and version, Steam packaging, Proton version, exact game/CET/RED4ext versions, Protontricks packaging/version, the failing command or dialog, and what changed immediately before the failure. Review logs for private data before attaching them.

Report an upstream bug to the appropriate official project with its requested evidence. A result on one machine should not be reported as a verified universal Linux fix.

## References

[1]: https://github.com/Matoking/protontricks/issues/340 "Official report of Steam metadata format and Protontricks failure"
[2]: https://github.com/Matoking/protontricks/blob/master/README.md "Official Protontricks installation and Flatpak access guidance"
[3]: https://flathub.org/en/setup/Ubuntu "Official Flatpak setup and session restart"
[4]: https://github.com/Matoking/protontricks/blob/master/TROUBLESHOOTING.md "Protontricks 64-bit prefix warning"
[5]: https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--500-999- "Microsoft definition of error 998"
[6]: https://wiki.redmodding.org/cyber-engine-tweaks/console/usage.md "CET overlay keybinding"
[7]: https://github.com/maximegmd/CyberEngineTweaks/releases/tag/v1.38.0 "CET 1.38.0 game compatibility"
[8]: https://github.com/maximegmd/CyberEngineTweaks/blob/v1.38.0/README.md "CET 1.38.0 RED4ext prerequisite"
[9]: https://docs.red4ext.com/getting-started/installing-red4ext.md "RED4ext Visual C++ 2022 prerequisite"
[10]: https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-users/users-modding-cyberpunk-2077/the-cyberpunk-2077-game-directory/modding-on-linux.md "Redmodding Linux components and launch options"
[11]: https://github.com/Winetricks/winetricks/blob/master/src/winetricks "Winetricks list-installed implementation"
[12]: https://docs.red4ext.com/getting-started/configuration.md "RED4ext logging configuration and rotation"
[13]: https://wiki.redmodding.org/cyber-engine-tweaks/getting-started/installing/troubleshooting.md "CET logs and loading troubleshooting"
[14]: https://github.com/ValveSoftware/Proton#runtime-config-options "Valve Proton logging options"
[15]: https://wiki.redmodding.org/cyber-engine-tweaks/getting-started/installing/linux-proton.md "CET prefix selection and runtime cautions"
[16]: https://wiki.redmodding.org/cyber-engine-tweaks/getting-started/installing.md "CET installation and overlay prerequisites"
