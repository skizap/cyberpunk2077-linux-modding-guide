# Cyberpunk 2077 Linux Modding Guide: CET, RED4ext & Proton

Install **Cyber Engine Tweaks (CET)** and **RED4ext** for Cyberpunk 2077 on Linux with Steam Proton. This walkthrough covers Linux Mint, Flatpak Protontricks, required Windows components, DLL overrides, prefix backups, and the first CET overlay launch.

Looking for **“Unable to load cyber_engine_tweaks.asi. Error: 998”**, **“SyntaxError: Invalid file magic number”**, or a missing CET console? Start with [troubleshooting](docs/troubleshooting.md).

**Version scope:** Cyberpunk 2077 **2.5**, CET **1.38.0**, and RED4ext **1.31.0**. Proton **11.0-2** is an example compatibility-tool version, not a requirement or a guarantee for every Linux distribution. See [version scope and validation limits](docs/tested-setup.md).

**Documentation checked:** 25 October 2026. Game and mod updates can change compatibility. This guide is independently maintained and is not affiliated with CD PROJEKT RED, Valve, or the mod developers.

## What this guide does—and does not do

The instructions target the **Steam copy of Cyberpunk 2077**, whose app ID is `1091500`. They configure its existing Proton prefix and install two modding frameworks manually. They do not install every Nexus mod or cover a game launched directly through Heroic, Lutris, Bottles, or GOG. Non-Steam shortcuts can have a different app ID; do not apply `1091500` to an unrelated prefix. The CET Linux guide describes those alternative launcher cases. [1]

This repository contains original text and configuration examples only. **No game files, mod binaries, redistributable installers, third-party images, or user logs are hosted here.** Download software from the official sources linked below. There is no one-click installer or `curl | bash` command.

If CET already works, do not install extra runtimes or reset a prefix just to match this guide.

## Before making changes

Launch the unmodified game through Steam at least once and confirm it reaches the menu. Close it before proceeding. Record the game version, selected Proton version, and the versions of any already-installed core mods. The game should work under Proton before modding begins. [1]

In **Steam → Cyberpunk 2077 → Properties → Compatibility**, note the selected compatibility tool. Proton **11.0-2** is an example version; do not replace a different working Proton version solely to match it. The CET guide treats Proton Experimental as optional. Do not switch Proton and install components in the same troubleshooting test. [1]

### Match the game and framework versions

CET **1.38.0** release notes explicitly support game patch **2.5**, with game build `3.0.88.46235`, and say earlier patches are unsupported. Its versioned README also requires RED4ext. [2] [3]

Use **release-specific compatibility notes**, not just a generic description or the word “latest.” During preparation, the Nexus description still listed patch 2.31 while CET 1.38.0's release notes listed patch 2.5. That discrepancy is a reason to check the notes for the archive you actually downloaded, not a reason to mix incompatible releases.

RED4ext **1.31.0** release notes set patch 2.5 as the minimum supported game version. Check the official release page again when installing on a newer game patch. [4]

## 1. Install or update Flatpak Protontricks

Protontricks runs Winetricks actions against a Steam game's Proton prefix. Distribution packages can lag behind Steam metadata changes; the official Protontricks documentation recommends Flatpak when a distribution's package is outdated. This guide uses an explicit Flatpak invocation so an older `/usr/bin/protontricks` does not get selected accidentally. [5]

### If Flatpak is missing on Linux Mint or Ubuntu

Check first:

```bash
flatpak --version
```

If the command is not found, run these commands individually:

```bash
sudo apt update
sudo apt install flatpak
```

These package-manager commands need administrator privileges. **Protontricks and Wine commands below do not.** Review the installation prompt. Other distributions should use their own official Flatpak setup instructions rather than these `apt` commands. [6]

Add Flathub for your user account:

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

Restart your session or computer after first installing Flatpak, as the official setup guide recommends. This also addresses desktop-menu warnings about missing Flatpak export directories. [6]

### Install the application

```bash
flatpak install --user flathub com.github.Matoking.protontricks
```

If that user installation already exists, update it instead:

```bash
flatpak update --user com.github.Matoking.protontricks
```

An existing system-wide Flatpak installation can also work. Do not install a second copy solely because this example uses `--user`; update the installation you use. The application ID comes from the official Protontricks project. [5]

Confirm the selected application responds:

```bash
flatpak run com.github.Matoking.protontricks --version
```

Keep using the full `flatpak run` command in this guide. Adding a shell alias is optional; leaving the old native package installed does not make the explicit Flatpak command use it.

**Official downloads:** [Protontricks project](https://github.com/Matoking/protontricks) and [Protontricks on Flathub](https://flathub.org/en/apps/com.github.Matoking.protontricks). The project's README identifies its GitHub repository as the official project and warns about unaffiliated lookalike sites. [5]

## 2. Locate the game folder and back up its prefix

The **game folder** and the **Proton prefix** are different locations.

Open **Steam → Cyberpunk 2077 → Properties → Installed Files → Browse** to locate the game folder. This is where mod archives are extracted. Do not assume the game is installed in the default Steam library.

The existing game prefix is a `pfx` directory inside `steamapps/compatdata/1091500`. It contains Windows-style configuration and may contain saves. Steam libraries, Flatpak Steam, and custom prefix settings can change the absolute location. Use the prefix belonging to the installation you actually launch. Do not create a separate Wine prefix for this tutorial. [7]

A common native-Steam compatibility-folder location is:

```text
$HOME/.local/share/Steam/steamapps/compatdata/1091500
```

That is an example, **not a universal path**. A library on another drive may use a different `steamapps/compatdata` location. If Protontricks prints a prefix path, use that actual path rather than blindly copying the example.

### Make a backup before installing Windows components

Close Cyberpunk and any open Protontricks/Wine windows. Ensure the destination drive has enough free space. Set `COMPATDATA` to your actual compatibility folder; it is the folder **containing** `pfx`, not `pfx` itself.

```bash
# Change this value if your prefix is elsewhere.
COMPATDATA="$HOME/.local/share/Steam/steamapps/compatdata/1091500"

if [ ! -d "$COMPATDATA/pfx" ]; then
    printf 'Prefix not found. Stop and correct COMPATDATA before continuing.\n'
else
    BACKUP="${COMPATDATA}.before-cet-$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$COMPATDATA" "$BACKUP" && printf 'Backup completed: %s\n' "$BACKUP"
fi
```

Only continue after **“Backup completed”** is printed without errors. Save the printed path. This copies the compatibility folder without deleting or replacing the original. It is not a backup of all game files, so separately preserve any mod files you plan to overwrite.

Steam Cloud is not a substitute for checking your local backup. A non-destructive recovery procedure is in [backup and recovery](docs/backup-and-recovery.md).

## 3. Supply the documented Windows components

The Redmodding Linux guide lists **`d3dcompiler_47`** and **`vcrun2022`**. RED4ext's complete installation documentation explicitly requires the **Visual C++ Redistributable 2022**. Read the actual installation page, including its callout, rather than relying on a short search preview. [8] [9]

These commands target Cyberpunk's **existing** Steam prefix:

```bash
flatpak run com.github.Matoking.protontricks 1091500 d3dcompiler_47
```

Wait for it to finish, then run:

```bash
flatpak run com.github.Matoking.protontricks 1091500 vcrun2022
```

Complete any Microsoft installer prompts and wait for the command to return. Winetricks obtains the runtime from Microsoft; this repository does not distribute it. The runtime action can run both x86 and x64 installers for a 64-bit prefix; let it complete its applicable installer steps.

**Important:** the CET-specific Linux guide warns that installing `vcrun2022` has broken some existing setups. This is why the prefix backup comes first. An already-working CET setup does not need a speculative runtime replacement. If an installer aborts, reports a checksum mismatch, or says an incompatible/newer runtime is already present, stop and inspect the full output. Do not repeat it with `--force` as a blanket fix. [1]

Do not run Protontricks with `sudo`. Do not create a 32-bit replacement prefix for this game; the generic 64-bit-prefix warning alone is not a failure. [10]

### Check what Winetricks recorded

```bash
flatpak run com.github.Matoking.protontricks 1091500 list-installed
```

After successful installation, look for:

```text
d3dcompiler_47
vcrun2022
```

This command reads Winetricks' installation log. It does **not** inventory every DLL installed by Steam, another installer, or Proton itself. Conversely, an absent `winetricks.log` does not prove the prefix has no runtimes. [11]

## 4. Download RED4ext and CET from their official sources

Open the release pages and select versions that support your game:

- **RED4ext:** [official GitHub releases](https://github.com/WopsS/RED4ext/releases). The normal 1.31.0 binary archive is `red4ext-1.31.0.zip`, not the symbols archive or RED4ext.SDK source.
- **CET:** [official GitHub releases](https://github.com/maximegmd/CyberEngineTweaks/releases) or the [official Nexus listing](https://www.nexusmods.com/cyberpunk2077/mods/107). Select the built release archive for your game version, not GitHub's source-code archive.

Follow the download site's terms and verify any published checksums for the exact selected release. This guide intentionally links to the original distributions instead of hosting copies.

### Extract into the game root

Close the game. Extract **the contents** of each release archive into the game folder from Steam's **Browse** button. Merge the archive's `bin` directory with the existing `bin` directory. Back up existing files before replacing them. Do not place the whole extracted archive inside another extra folder. [9] [12]

For the versions covered here, key files should end up at:

```text
Cyberpunk 2077/
├── bin/
│   └── x64/
│       ├── version.dll
│       ├── winmm.dll
│       └── plugins/
│           ├── cyber_engine_tweaks.asi
│           └── cyber_engine_tweaks/
└── red4ext/
    └── RED4ext.dll
```

The `winmm.dll` and `red4ext/RED4ext.dll` locations were checked in the official RED4ext 1.31.0 archive. The CET locations are documented in the installation guide. These are key locations, not a complete list of every release file. [12]

RED4ext.Loader and RED4ext.SDK are different projects. Installing the SDK or a symbols archive is not a replacement for the loader required by the CET 1.38.0 README. [3]

## 5. Set Steam's DLL overrides

Open **Steam → Cyberpunk 2077 → Properties → General → Launch Options**. If the field is empty, paste:

```text
WINEDLLOVERRIDES="winmm,version=n,b" %command%
```

This is a **Steam launch option**, not a command to run on its own in a terminal. The Redmodding Linux guide supplies this exact line. It allows the native RED4ext `winmm` loader and CET `version` loader to be used before Wine's built-in versions. [8]

If you already have launch options, save their original text before editing. Preserve unrelated environment settings, launchers, and arguments. Use one combined `WINEDLLOVERRIDES` definition; do not add two conflicting definitions. Preserve Steam's `%command%` placeholder rather than replacing it with a guessed executable path.

The alternative Wine configuration method described by the CET guide is:

```bash
flatpak run com.github.Matoking.protontricks 1091500 --gui
```

Select **Select the default wineprefix → Run winecfg → Libraries**, then inspect the `version` override. For CET it should use native before builtin. This opens the existing game's configuration; **do not choose a new prefix**. With both frameworks installed, the combined Steam launch option above also covers `winmm`. Avoid changing both methods repeatedly during diagnosis. [1] [8]

## 6. Launch and bind the CET overlay key

Launch the game using the same selected Proton version. When CET loads successfully for the first time, it should show its overlay keybinding prompt. Click **Hotkey** beside **Overlay Key**, then press your chosen key when the button shows **BINDING…**. F8 is one possible choice; it is **not** a universal default. Use the key you actually bind to open and close the overlay. [13]

If an ASI Loader error appears but Cyberpunk continues to its menu, that does not prove CET loaded. Trying random keys is not a substitute for fixing a loading failure. See [Error 998 and no CET overlay](docs/troubleshooting.md#asi-loader-error-998-and-no-cet-overlay).

If loading succeeds but the overlay remains invisible, the CET installation guide recommends Windowed Borderless mode and disabling conflicting overlays. Distinguish an overlay-display problem from an ASI loading error. [12]

## 7. Add other mods carefully

Once the base frameworks work, follow each mod author's installation instructions and requirements. Install one mod at a time and test. Some mods need redscript, ArchiveXL, TweakXL, Codeware, or other frameworks; this guide does not install those or establish their compatibility with every game patch.

A Windows-specific installer or mod manager is not automatically usable just because the game runs through Proton. Prefer the author's documented manual archive layout when available. Do not copy all downloaded mods into one guessed folder.

After a game update, check every core framework's release notes before reusing the old setup. Keeping a working Proton version fixed helps troubleshooting, but it does not make an incompatible mod release compatible.

## Troubleshooting and recovery

The [troubleshooting guide](docs/troubleshooting.md) covers:

- `SyntaxError: Invalid file magic number` before Protontricks opens.
- `Command 'flatpak' not found` and desktop export-path warnings.
- ASI Loader **Error 998**, no CET keybinding prompt, and empty RED4ext logs.
- Runtime-installation errors, external Steam library permissions, and non-Steam app IDs.
- Collecting a Proton log without resetting the prefix.

Use [backup and recovery](docs/backup-and-recovery.md) if a component change breaks the previously working game. Keep the original backup until the game and overlay work reliably. Do not delete `compatdata/1091500` as a first-line fix.

## Contribute or report a problem

Read [CONTRIBUTING.md](CONTRIBUTING.md), then use the repository's issue forms. Include exact versions and the failing command. **Redact credentials, account details, usernames, and private paths from logs before posting them publicly.** Do not upload game files, mod binaries, or copied third-party assets.

Corrections should link to primary documentation and distinguish a reported success from an independently reproduced test. The guide's original text is shared under [CC BY 4.0](LICENSE); third-party software and linked material remain under their respective owners' terms.

## References

[1]: https://wiki.redmodding.org/cyber-engine-tweaks/getting-started/installing/linux-proton.md "CET Linux and Proton installation guide"
[2]: https://github.com/maximegmd/CyberEngineTweaks/releases/tag/v1.38.0 "CET 1.38.0 release notes"
[3]: https://github.com/maximegmd/CyberEngineTweaks/blob/v1.38.0/README.md "CET 1.38.0 README and RED4ext prerequisite"
[4]: https://github.com/WopsS/RED4ext/releases/latest "Official RED4ext latest release"
[5]: https://github.com/Matoking/protontricks/blob/master/README.md "Official Protontricks installation and usage"
[6]: https://flathub.org/en/setup/Ubuntu "Official Ubuntu Flatpak setup"
[7]: https://github.com/ValveSoftware/Proton/wiki/Proton-FAQ "Valve Proton FAQ and per-game prefixes"
[8]: https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-users/users-modding-cyberpunk-2077/the-cyberpunk-2077-game-directory/modding-on-linux.md "Redmodding Linux modding and launch options"
[9]: https://docs.red4ext.com/getting-started/installing-red4ext.md "RED4ext installation and Visual C++ 2022 prerequisite"
[10]: https://github.com/Matoking/protontricks/blob/master/TROUBLESHOOTING.md "Official Protontricks troubleshooting"
[11]: https://github.com/Winetricks/winetricks/blob/master/src/winetricks "Winetricks implementation of list-installed"
[12]: https://wiki.redmodding.org/cyber-engine-tweaks/getting-started/installing.md "CET binary installation and first launch"
[13]: https://wiki.redmodding.org/cyber-engine-tweaks/console/usage.md "CET overlay keybinding instructions"
