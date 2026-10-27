# Contributing

Thanks for helping improve this Linux Mint, Steam Proton, Cyberpunk 2077, CET, and RED4ext guide. Contributions should make the tutorial more reproducible, easier to verify, and easier to maintain.

Before opening an issue or pull request, check the local [README](README.md) and [troubleshooting guide](docs/troubleshooting.md). If your situation is already covered, add the missing version details or clarification rather than duplicating the existing guidance.

## Documentation contributions

This repository contains documentation and one helper installer script (`cyberpunk-linux-modder.sh`). Please contribute original prose written for this guide. Do not paste third-party documentation, mod pages, troubleshooting posts, game files, mod binaries, screenshots, logs, or other copyrighted material.

When adding or revising technical instructions:

- Link to primary or official documentation where available, such as the official project page, release page, or maintainer documentation.
- State the date on which a version-specific instruction was checked.
- Clearly distinguish between a result you personally tested and an inference based on available evidence. For example, label a tested configuration as “user-tested” and a plausible but unverified explanation as “inferred.”
- Include the relevant game, CET, RED4ext, Proton, Protontricks, and Steam packaging details when reporting behavior.
- Keep changes small, reversible, and narrowly scoped. Explain what a reader should change, how to confirm the result, and how to undo the change if it does not help.

Avoid universal claims about `error998` or any other error. The same message can have different causes across game builds, mod versions, prefixes, and Steam installations. Describe the observed conditions and evidence instead.

Do not recommend `sudo` with Protontricks. Do not present deleting a Proton prefix or using `--force` as a blanket fix. If either action is relevant to a narrowly documented case, it must be clearly marked as exceptional, explain the risk, and offer safer reversible checks first.

## Script contributions

The installer script accepts changes that keep its safety envelope intact:

- Keep `bash -n` clean and ShellCheck (style level) free of findings.
- Keep `--self-test` passing, and extend it when adding or changing helpers.
- Never add silent privilege escalation, redistribution of game or mod binaries, mirror downloads, or unconfirmed component installation.
- Preserve backups-before-changes, checksum verification, dry-run fidelity, and the documented exit codes.
- Update `docs/installer.md` in the same pull request whenever behavior, phases, or flags change.

## Reporting installation problems

Use the installation-problem issue form and provide enough information for someone else to reproduce the issue. In particular, include:

- Cyberpunk 2077 game version.
- CET and RED4ext versions.
- Proton version and compatibility-tool source.
- Linux Mint version if known. If it is unknown, say so rather than guessing.
- Whether Steam is installed natively or through Flatpak.
- Protontricks version and how it was installed or packaged.
- Exact steps, expected behavior, actual behavior, and relevant log excerpts.

Before posting logs, redact usernames, private home paths, account identifiers, tokens, passwords, and other secrets. Do not upload copyrighted game or mod files. Link only to official or primary sources for game, compatibility-tool, CET, RED4ext, and mod information.

## Pull requests

Keep each pull request focused on one correction, clarification, or tested addition. In the pull request description, say:

- What changed and why.
- Which version dates and sources you checked.
- Whether the instructions were user-tested or inferred.
- How the reader can verify the result and reverse the change if needed.

If a proposed change depends on an unverified assumption, open an issue first or label it clearly as inferred. Maintainers may request version details, a primary source, or a narrower claim before merging.

## License for contributions

By submitting original documentation to this repository, you agree to share that contribution under the license governing the file you change: CC BY 4.0 for the documentation and MIT for `cyberpunk-linux-modder.sh` (both summarized in [LICENSE](LICENSE)). Keep third-party software, assets, copied documentation, and private diagnostics out of commits. Link to their official sources instead.
