# CombatText issue 38 validation

This correction targets the Forever V063 source identified in README.md.
It guards GetText() before preview comparison and rejects UNIT_COMBAT events
with secret arguments before frame lookup or any comparison, arithmetic,
formatting or table indexing. A secret UnitInAnyGroup result also skips the
event. Existing combat text continues its normal fade when an event is skipped.
No profile data or protected frame attributes are changed.

Local checks (run from the repository root):

```sh
lua5.1 Tests/combat_text.lua
lua5.1 Tests/combat_text.lua legacy
luac5.1 -p Modules/CombatText/CombatText.lua Tests/combat_text.lua
git diff --check
```

The harness uses a sentinel and a mocked issecretvalue function. It checks
early rejection and ordinary display behavior; it cannot reproduce Blizzard's
secret-value enforcement or prove combat/taint safety.

In-game validation has not been run. On the actual Forever client 12.1.5,
record the build/project identifiers and test:

- Acquire, clear and change targettarget inside and outside combat.
- Exercise damage, zero/absorbed damage, critical/crushing/glancing hits,
  healing, energize, immune, block and fallback combat events.
- Refresh fonts/layouts, toggle preview, and hide/reuse frames.
- Confirm public events display and fade, skipped events do not prevent
  existing text from fading, and other frames continue updating.
- Check Lua errors and taint logs for secret comparisons and
  ADDON_ACTION_BLOCKED.

The repository alone does not establish the reporter's exact client build or
verify the reported occurrence counts. No in-game reproduction is claimed.
