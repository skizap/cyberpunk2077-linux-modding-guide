# Version scope and validation limits

This guide focuses on Cyberpunk 2077 **2.5**, Cyber Engine Tweaks **1.38.0**, and RED4ext **1.31.0** through Steam Proton. These are version-specific instructions, not a compatibility guarantee for every distribution, Proton release, or future game update.

## Match the game and framework releases

CET **1.38.0** release notes support Cyberpunk patch **2.5**, with game build `3.0.88.46235`, and say earlier game patches are unsupported. The versioned README requires RED4ext before CET. [1] [2]

RED4ext **1.31.0** release notes set Cyberpunk patch **2.5** as the minimum supported game version. Its installation documentation requires Visual C++ Redistributable 2022. Select the normal loader archive, not the SDK or symbols package. [3] [4]

The Linux modding guide lists `d3dcompiler_47`, `vcrun2022`, and the combined loader override:

```text
WINEDLLOVERRIDES="winmm,version=n,b" %command%
```

Back up the game's actual prefix before runtime changes. An existing installation that already works does not need speculative runtime replacement. [5]

## Proton and distribution choices

**Proton 11.0-2** is an example compatibility-tool version, not a requirement to replace another working Proton release. The CET Linux guide treats Proton Experimental as optional. Record the tool you select and avoid changing it at the same time as runtimes or mod files. [6]

Linux Mint and Ubuntu use the `apt` examples in the installation guide. Other distributions should use their own official Flatpak setup instructions. Differences in Steam packaging, library locations, sandbox permissions, and launchers can affect where the prefix is found. No hardware-specific configuration is documented here.

## What is and is not validated

The repository's shell examples have been syntax-checked, not executed against a game installation by the documentation tooling. The Markdown links and issue-form structure were checked locally. These checks do not establish universal game compatibility or independently reproduce the installation on multiple computers.

The guide does not identify a single universal cause of ASI Loader Error 998. Microsoft's definition is a memory-access error; the message alone cannot establish the exact failing DLL or runtime. Use the documented requirements and current logs to narrow the problem. [7]

Backup restoration is provided as a cautious recovery procedure, not a claim that every possible prefix state has been restore-tested. Inspect each path and preserve the current prefix before copying a backup back into place.

## Documentation boundaries

The guide contains no personal case history, hardware inventory, machine name, personal home-directory path, uploaded logs, screenshots, or private account information. Filesystem examples use `$HOME` or clearly marked placeholders. Third-party software is linked from its official source rather than redistributed.

Re-check the selected release notes after game or framework updates. If a generic mod description conflicts with release-specific notes, use the notes for the exact archive and game build rather than assuming the newest archive supports every patch.

## References

[1]: https://github.com/maximegmd/CyberEngineTweaks/releases/tag/v1.38.0 "CET 1.38.0 game compatibility"
[2]: https://github.com/maximegmd/CyberEngineTweaks/blob/v1.38.0/README.md "CET 1.38.0 RED4ext prerequisite"
[3]: https://github.com/WopsS/RED4ext/releases/tag/v1.31.0 "RED4ext 1.31.0 release notes"
[4]: https://docs.red4ext.com/getting-started/installing-red4ext.md "RED4ext installation and Visual C++ 2022 requirement"
[5]: https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-users/users-modding-cyberpunk-2077/the-cyberpunk-2077-game-directory/modding-on-linux.md "Linux modding prerequisites and overrides"
[6]: https://wiki.redmodding.org/cyber-engine-tweaks/getting-started/installing/linux-proton.md "CET Linux installation and runtime cautions"
[7]: https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--500-999- "Microsoft definition of error 998"
