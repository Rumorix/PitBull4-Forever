# Issue 6: native aura combat clear

The Forever renderer retains native state after clearing a frame. Combat reuse
intentionally skips group enablement and visibility configuration, so clearing
those groups during combat could leave them disabled until combat ends.

ClearNativeFrame now preserves preconfigured native groups during combat. It
adds no combat API calls, layout changes, aura-value inspection or saved-profile
fields. Out-of-combat clearing is unchanged. Aura's existing
PLAYER_REGEN_ENABLED UpdateAll reconciles active frames, and clears frames whose
unit is still absent or whose module is disabled.

Local regression: `lua5.1 Tests/native_aura_clear.lua`. The harness loads the
renderer and exercises repeated clear/reuse with a fixed targettarget token,
all buff/debuff enablement combinations, split/combined ownership, absent state,
legacy clear delegation, and out-of-combat clearing. It rejects attempted combat
mutations even when the renderer contains errors with pcall.

Live Forever client 12.1.5 validation remains required:

- Build targettarget containers before combat, then repeatedly remove and
  restore the unit with known buffs/debuffs, keeping the literal token unchanged.
- Test buffs only, debuffs only, both, neither, and split ownership.
- Check disappearance for stale icons and reappearance for missing auras or
  duplicate native/legacy displays; repeat with owner-frame hide/show.
- Check combat exit with the unit both present and absent, and with the module
  disabled. Confirm out-of-combat clearing and configuration still apply.
- Check forbidden-action, taint and secret-value errors.

The harness does not emulate Blizzard's secure lifecycle or verify visible aura
contents. Preserving groups relies on the managed container's unit lifecycle;
live testing must confirm that absent units do not leave stale icons. This fix
does not restore groups already cleared out of combat before entering combat,
or change explicit native retirement/rebuild behavior.
