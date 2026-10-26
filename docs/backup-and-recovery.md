# Back up and recover Cyberpunk's Proton prefix without deleting it

A Proton prefix contains Windows-style state for a game and may contain its saves. Replacing runtimes or recreating the prefix can affect a previously working installation. Valve documents game prefixes under `steamapps/compatdata/<appid>/pfx`; for the Steam store copy of Cyberpunk, the app ID used in this guide is `1091500`. [1]

Make a backup before installing `vcrun2022` or replacing runtime components. The recovery procedure below is not an independently game-tested restore for every possible prefix state; inspect every path before using it.

## What needs backing up

Back up the **entire compatibility folder containing `pfx`**, not just one DLL. This preserves its prefix and supporting state. It does not back up the game directory or undo mod files you extracted there. Separately preserve any game-folder files you overwrite and save the original Steam launch options.

The example below uses a default native-Steam location. A different Steam library, Flatpak Steam, or a custom prefix may use another path. Change `COMPATDATA` to the directory for the game you actually launch. Do not copy a path from a different user's log.

## Make a timestamped copy

Close Cyberpunk and any open Protontricks/Wine windows. Do not perform the copy while the game is writing saves or an installer is changing the prefix. Ensure enough free space exists on the destination drive.

```bash
# Replace this example if your actual prefix is elsewhere.
COMPATDATA="$HOME/.local/share/Steam/steamapps/compatdata/1091500"

if [ ! -d "$COMPATDATA/pfx" ]; then
    printf 'Prefix not found. Stop and correct COMPATDATA.\n'
else
    BACKUP="${COMPATDATA}.before-cet-$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$COMPATDATA" "$BACKUP" && printf 'Backup completed: %s\n' "$BACKUP"
fi
```

Do not proceed with runtime installation unless the copy reports **“Backup completed”** without errors. Save the printed path somewhere outside the terminal. A successful command return is not a substitute for checking that you backed up the correct installation.

Inspect the copied directory before relying on it:

```bash
# Use the actual printed backup path if this is a new terminal session.
ls -ld -- "$BACKUP" "$BACKUP/pfx"
```

Check important save/configuration files if you know where this installation stores them. Steam Cloud does not prove every local setting or mod-related file is recoverable.

## Recover after a failed runtime experiment

Use this only when you intentionally want to return the prefix to its backed-up state. New saves or settings created after the backup will not exist in that older copy. The procedure preserves the current prefix under another name so it is not discarded.

Close Cyberpunk, Steam, and all Protontricks/Wine windows first. Then replace the example `BACKUP` value with the **exact path you saved**. Do not point it at the live prefix.

```bash
# Check and edit both paths before running this block.
COMPATDATA="$HOME/.local/share/Steam/steamapps/compatdata/1091500"
BACKUP="/replace/with/the/exact/printed/backup/path"
FAILED="${COMPATDATA}.after-failed-change-$(date +%Y%m%d-%H%M%S)"

if [ ! -d "$COMPATDATA/pfx" ] || [ ! -d "$BACKUP/pfx" ]; then
    printf 'Live prefix or backup not found. Stop; no restore performed.\n'
elif [ "$(realpath -- "$COMPATDATA")" = "$(realpath -- "$BACKUP")" ]; then
    printf 'Backup points to the live prefix. Stop; no restore performed.\n'
elif [ -e "$FAILED" ]; then
    printf 'Preservation destination already exists. Stop; no restore performed.\n'
else
    mv -- "$COMPATDATA" "$FAILED" &&
    cp -a -- "$BACKUP" "$COMPATDATA" &&
    printf 'Restore completed. Previous live prefix preserved at: %s\n' "$FAILED"
fi
```

Only relaunch after **“Restore completed”** is printed without errors. If copying fails after the move, the previous live prefix remains at the printed/intended `FAILED` path, while the original backup remains untouched. Do not launch Steam into a missing or partially copied prefix; resolve the copy failure first.

This procedure intentionally avoids `rm -rf` and keeps the backup. Do not delete either preserved copy until you have checked the game, saves, settings, and overlay.

## Revert the other changes separately

A prefix restore does not remove newly added files from the game directory. To undo a manual framework installation, identify the exact files from that selected archive and restore the game-folder copies you preserved. Do not delete the whole `bin`, `plugins`, or `red4ext` tree if it contains other mods.

Restore the Steam launch options you saved if you intend to revert loader configuration. If you only enabled diagnostics, remove `PROTON_LOG=1` while retaining the existing working loader overrides. Valve documents that this logging option is a runtime setting, not a permanent prefix modification. [2]

Return to [troubleshooting](troubleshooting.md) and change one variable at a time. A new prefix, a new Proton version, a runtime replacement, and new mod files all at once make it difficult to tell which change caused the result.

## References

[1]: https://github.com/ValveSoftware/Proton/wiki/Proton-FAQ "Valve Proton prefix and save locations"
[2]: https://github.com/ValveSoftware/Proton#runtime-config-options "Valve Proton logging and runtime options"
