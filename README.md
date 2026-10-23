# PitBull4 Forever

Community-maintained **PitBull4 Forever** fork for World of Warcraft.

**Current source version:** `PitBull4-Lorenzo-Forever-063` (2026-10-23)

**Official Stable download:** [GitHub Releases](https://github.com/Rumorix/PitBull4-Forever/releases/latest)

**Repository:** https://github.com/Rumorix/PitBull4-Forever

## Scope

This repository tracks the **Forever** codebase separately from the maintainer's **Retail/Midnight** and **Classic Era** forks. It includes the Lua source, XML definitions, assets, and bundled libraries needed by the provided addon archive.

### Changes in the current Stable codebase

- Consolidates the Forever v58-v60 changes (pet-range handling, ToT aura refresh attempts, health gradient).
- Merges Soul Shards compatibility work from a separate v58 branch.
- Includes PR #33 (independent Full/Empty opacity), #34 (media previews), #35 (sharing/import safety) and #36 (profile import/export with LibSerialize and LibDeflate).
- The v063 source change aligns version metadata with the already published v062 functionality; no runtime behavior change.
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

**Do not use the GitHub source ZIP as a guaranteed release package.** Install the complete ZIP attached to the latest official GitHub Release.

## Provenance and licensing

This fork is derived from the upstream **PitBull Unit Frames 4.0** project. Original authorship metadata and existing upstream notices have been preserved from the provided source archive. This import does not add a new license or claim ownership of third-party code.

**Before making this repository public or distributing new builds, verify the license and redistribution permissions for the original addon and its bundled dependencies.** The archive contains upstream packager metadata and project IDs; do not use these to publish to the original project's CurseForge/Wago/WoWInterface listings.

## Automation safety

The historical upstream GitHub Actions release workflows have been excluded intentionally. They were configured to package/upload on pushes or tags and should not be re-enabled without an explicit security and publishing review. New automation will create reviewable PRs; no direct merge or release permissions for an AI bot.
