# PitBull4 Forever

Community-maintained **PitBull4 Forever** fork for World of Warcraft.

**Current imported build:** `PitBull4-Lorenzo-Forever-061-MergedFixes` (2026-10-19)

**Repository:** https://github.com/Rumorix/PitBull4-Forever

## Scope

This repository tracks the **Forever** codebase separately from the maintainer's **Retail/Midnight** and **Classic Era** forks. It includes the Lua source, XML definitions, assets, and bundled libraries needed by the provided addon archive.

### Changes in this imported build

- Consolidates the Forever v58-v60 changes (pet-range handling, ToT aura refresh attempts, health gradient).
- Merges Soul Shards compatibility work from a separate v58 branch.
- Does **not** claim that all combat-specific behavior has been verified in-game.

For the detailed build-specific changes, see [`LORENZO_RELEASE_NOTES.txt`](LORENZO_RELEASE_NOTES.txt) and [`LORENZO_BUILD_VERSION.txt`](LORENZO_BUILD_VERSION.txt).

## Development and bug reports

Please open a GitHub Issue using the **Bug report** template. Include:

- Exact build and WoW client version
- Character class/spec and relevant PitBull4 module
- Steps to reproduce, expected behavior, actual behavior
- Lua errors (BugGrabber/BugSack), and screenshots if useful

Avoid including character/account identifiers, access tokens, or other private information in logs. A future Discord bot can mirror reports into GitHub Issues.

## Installation

The WoW addon folder should be named `PitBull4` and contain `PitBull4_Mainline.toc` directly inside it. For a local working checkout named `PitBull4-Forever`, copy the checked-out repository *contents* into `Interface/AddOns/PitBull4/`; do not rename the actual game-addon folder to `PitBull4-Forever`.

**Do not use the GitHub source ZIP as a guaranteed release package.** A release workflow will be designed separately and reviewed before being enabled.

## Provenance and licensing

This fork is derived from the upstream **PitBull Unit Frames 4.0** project. Original authorship metadata and existing upstream notices have been preserved from the provided source archive. This import does not add a new license or claim ownership of third-party code.

**Before making this repository public or distributing new builds, verify the license and redistribution permissions for the original addon and its bundled dependencies.** The archive contains upstream packager metadata and project IDs; do not use these to publish to the original project's CurseForge/Wago/WoWInterface listings.

## Automation safety

The historical upstream GitHub Actions release workflows have been excluded intentionally. They were configured to package/upload on pushes or tags and should not be re-enabled without an explicit security and publishing review. New automation will create reviewable PRs; no direct merge or release permissions for an AI bot.
