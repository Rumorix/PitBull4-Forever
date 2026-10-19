# Pet name and Blizzard pet-frame fixes

Candidate fixes against `main`; addon version remains
`PitBull4-Lorenzo-Forever-061-MergedFixes`. This branch is independent of the
ongoing native-aura/U1–U3 work.

## English changelog

- Repair exact historical stock Name LuaTexts automatically when rendering a
  Name slot, including saved layouts such as `CustomPets`. Historical presets
  expected three suffix arguments; the current `Angle()` returns one string.
- Preserve user-customized LuaTexts and their error reporting. Do not substitute
  blank strings for missing formatting arguments or inspect secret names.
- Retry Blizzard pet-frame hiding after world entry, the unit-frame addon loads,
  and the player's pet changes. Install the existing hide policy once per frame,
  including a late-created or replacement PetFrame.
- Defer pet-frame mutations during combat and recheck module/profile settings
  when deferred work executes. No new Show replacement or Blizzard mixin hook.

## Investigation and limits

`CustomPets` is a saved layout name, not a configuration shipped in this
repository. Its actual text source and the reporter's SavedVariables are not
available. The Imgur album could not be fetched because this environment's proxy
denied access.

The old stock Standard Name script returns:

```lua
return '%s %s%s%s',Name(unit),Angle(AFK(unit) or DND(unit))
```

With the current `Angle()`, this supplies only two strings for four `%s`
conversions. It reproduces the reported missing fifth argument to
`SetFormattedText` (self, format, name, suffix, **missing string**, ...).
The existing profile-upgrade tool already recognizes these exact historical
scripts, but normal rendering omitted this Name compatibility step. Rendering
now uses that existing exact map for canonical/localized Name slots. Other slots
and scripts differing from the known stock source remain unchanged.

This establishes a built-in legacy-script defect that matches the error; it
does **not** establish that the reporter uses that exact script. A custom script
can cause a similar error, as can a genuinely absent name return during a client
transition. Neither is silently rewritten or hidden by this patch. Secret names
continue passing directly to the existing formatted-text render sink.

The default Blizzard pet frame has a separate lifecycle defect. If PetFrame is
absent during the one-time Player hide pass, that pass is still recorded as
complete. Later discovery was never retried for pet/world/unit-frame loading
events. The fix preserves the existing setting: pet hiding follows **Hide
Blizzard frames → Player**. If that option or the module is disabled, this patch
does not hide a newly discovered pet frame. Existing hidden frames still follow
the documented reload requirement when restoring Blizzard frames.

The two confirmed defects are independent; a LuaTexts formatting error is
caught by its own renderer and does not control HideBlizzard's state.

## Automated tests

The suite loads the full production LuaTexts and HideBlizzard files with limited
WoW frame/timer mocks, and uses the actual `Angle()` helper source. It verifies
all five exact legacy presets (including Druid-form branches), canonical and
localized slots, preservation of custom scripts/errors, opaque-name forwarding,
late/replacement PetFrame discovery, idempotent hooks, and combat/settings
deferral. Both primary regression scenarios fail against unchanged `main`.

With Python and Lupa's Lua 5.1 runtime (`lupa==2.6` in the cloud environment):

```sh
PYTHONPATH=/workspace/.onboarding/python python -B -m unittest discover -s Tests -v
PYTHONPATH=/workspace/.onboarding/python python -B /workspace/.onboarding/pitbull4/validate.py
```

These mocks do not emulate WoW's secret-value implementation, taint propagation,
secure execution or Blizzard Edit Mode. Client verification remains required.

## In-game checklist — Retail 12.1.5 / Forever

1. Back up SavedVariables. Record the exact client build, character class/spec,
   current profile, pet unit token and CustomPets Name text source/events.
2. With a known historical stock Name script, summon a named pet and verify its
   name renders without `{err}` or formatting errors. Test summon/dismiss,
   resummon/rename, death/revival, zoning and reload. Verify other custom text
   scripts and fonts/anchors/events remain unchanged.
3. Test public and restricted pet-name situations during combat. Do not interpret
   opaque data in diagnostic scripts. Check Lua errors and taint/blocked-action
   logs; forwarding a mocked opaque name alone does not prove client behavior.
4. Enable HideBlizzard and its Player option. Verify the Blizzard pet frame is
   hidden when present at login and after late pet creation, zoning, reload and
   vehicle transitions. Confirm PitBull's pet frame and pet action bar still work.
5. Summon/change pets during combat. No addon-initiated protected frame mutation
   should occur; if first discovered during combat, hiding waits until combat
   ends. A repeated Blizzard OnShow also waits until safe to hide.
6. Check enabling/disabling the module and Player option, including changes
   before deferred work runs. Reload when restoring previously hidden Blizzard
   frames. Exercise Blizzard Edit Mode entry/exit and verify no blocked actions.

If the original issue remains, provide the exact **CustomPets → Lua:Name** source,
its selected events, client/build, relevant HideBlizzard options and fresh Lua
error stack. Avoid sending account/character identifiers or complete private
SavedVariables when a redacted configuration excerpt is sufficient.
