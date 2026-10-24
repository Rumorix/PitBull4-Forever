# Native aura recovery — candidate for Forever V62

The addon version remains `PitBull4-Lorenzo-Forever-061-MergedFixes`.
This change is limited to the normal Aura module's native renderer and lifecycle.
MajorCooldownAuras, ImportantDebuffs, saved settings and layout/filter definitions
are unchanged.

## English changelog

- Preserve enabled native aura groups when a unit temporarily disappears, so
  reacquiring Target of Target during combat does not leave its auras disabled.
- Defer native construction, configuration, teardown and fallback-button cleanup
  during combat; reconcile current frame state after `PLAYER_REGEN_ENABLED`.
- Recover transient native-renderer failures with three automatic retries instead
  of permanently excluding the frame after its first error.
- Bound persistent failures, clean up partially constructed native surfaces,
  cancel retries on module disable and expose retry state in native diagnostics.
- Track native ownership per frame, independently of global API availability;
  continue combat-safe native refreshes when other frames use legacy fallback.
- Suspend unprotected legacy fallback controls during combat and reconcile
  current visibility and pooled cleanup after combat, including `OnHide`.
- Add isolated Lua 5.1 regression coverage. No version or SavedVariables migration.

## Recovery contract

Temporary unit absence does not disable native groups or hide their holders.
Blizzard's managed container and the secure unit-frame parent retain ownership
of live aura processing and immediate visibility. `OnHide` passes through the
same combat boundary as `ClearFrame` rather than calling the old legacy alias.

Combat-time requests are coalesced per frame. Recovery reads current public
configuration and unit existence after combat, rather than replaying an earlier
clear against a unit that has returned. It does not read aura payloads, GUIDs,
ownership, spell identity or duration values. Existing dynamic refreshes continue
using Blizzard's supported `UpdateAllAuras()` entry point.

A failed frame receives one initial attempt and at most three automatic retries,
with delays of 0.25, 1 and 3 seconds after successive failures. One shared timer
serves eligible frames. Routine updates respect both the delay and attempt cap;
they cannot reset the budget. Hidden frames, unavailable units, disabled layouts
and Config Mode previews do not consume retries. Combat pauses recovery without
spending attempts. Success removes the failure and retry record.

Exhausted failures remain visible in `/pitbull 121status` as `attempts=4` and
`retry=exhausted`. The existing explicit native-container rebuild or native-mode
off/on controls reset the budget; reload also resets session state. During
out-of-combat failures the existing legacy fallback remains available.

Native surfaces first needed during combat, or requiring a different literal
unit token, are configured after combat. This deliberately avoids insecure
container construction/rebinding during lockdown. It does not guarantee a new
display can appear before combat ends.

## Automated testing

From the repository root, with Lua 5.1 installed:

```sh
lua5.1 Tests/native_aura_recovery.lua
```

Alternatively, use Python with `lupa==2.6` and its Lua 5.1 runtime:

```sh
python -B Tests/run_native_aura_recovery.py
```

In the prepared cloud environment:

```sh
PYTHONPATH=/workspace/.onboarding/python python -B Tests/run_native_aura_recovery.py
PYTHONPATH=/workspace/.onboarding/python python -B /workspace/.onboarding/pitbull4/validate.py
```

The regression suite loads the real `Aura.lua` and `NativeContainer_12_1.lua`
into isolated environments with public frame/timer mocks. It covers combat clear
and reacquisition, precombat absence, first-use deferral, unit-token changes,
transient success without another event, persistent-failure exhaustion, combat
pause/resume, shared timers, hidden/disabled layouts, partial-construction and
configuration exceptions, module disable/re-enable, preview transitions, and
buff/debuff filter and limit preservation.

Mocks reject native frame mutations during simulated combat and reject attempts
to read protected aura data. They are not an implementation of WoW's secure
execution, forbidden object partitions or secret-value enforcement.

## Required Retail 12.1.5 / Forever client testing

1. Start with auras visible on Target and Target of Target. Enter combat, clear
   target with Escape, reacquire with Tab, and repeat rapidly. Change the target's
   target without changing your target. Buff/debuff icons must recover, with no
   blocked-action or Lua errors.
2. Repeat for Focus, party/raid unit reuse, pets and boss-frame appearance. Reload
   during combat. Existing surfaces should continue updating; a surface not yet
   constructed must initialize after combat ends.
3. Repeat with buffs disabled, debuffs disabled, strict combined limits, split
   ownership styling, player-only filters and custom sizes. Verify settings,
   enabled states, anchors and limits remain unchanged after recovery.
4. Outside combat, enter/exit PitBull Config Mode, switch profiles, and disable/
   re-enable Aura. Verify there are no duplicate native/legacy icon sets. Check
   that deferred layout changes are applied after leaving combat.
5. Check `/pitbull 121status` after a naturally occurring native failure. Confirm
   transient failures recover, persistent failures stop at four total attempts,
   and explicit rebuild can retry after the underlying issue is resolved. Use
   the automated fault injection for deterministic failure tests; do not modify
   Blizzard API implementations in the game client.

Capture the exact client/build, affected unit, native status output, Lua errors
and taint/blocked-action logs. Passing the automated suite does not establish
in-game combat correctness or certify the change for release.

## PR #2 review follow-up

Global native availability no longer decides whether a particular frame is native.
Only a configured state for the current unit token, without a recorded failure or
Config Mode override, owns that frame. `UNIT_AURA` routes combat-safe native
refreshes independently of fallback failures and legacy raid throttling.

Legacy rebuilds, layout, allocation and pooled deletion remain deferred throughout
combat, including with native mode disabled. Existing unprotected fallback icons
and highlights are hidden without deleting or reparenting them. Protection and
forbidden-object checks precede visibility mutations. Protected or forbidden
fallback controls are left to their secure parent during combat: if that parent
stays visible, their old visuals may persist until combat ends. No insecure fix can
promise immediate protected cleanup. After combat, current visible frames rebuild;
hidden frames receive cleanup even though normal frame iteration excludes them.
A returned unit is updated instead of replaying its earlier clear.

The Lua 5.1 suite now contains 18 cases, including mixed renderers for the same
unit, failed initialization, combat `UNIT_AURA`, transient disappearance, fallback
`OnHide`, disabled native mode, and protected/forbidden controls.

Additional in-game checklist: reproduce a native failure on one frame alongside a
healthy native frame, apply/remove auras during combat, and verify the healthy
frame stays live. Confirm unprotected fallback visuals suspend and recover after
combat, hidden fallback controls are cleaned up, and protected fallback controls
produce no blocked-action/taint errors. Test raid performance mode as well.

## Tester follow-up: stale Target/Target-of-Target icons

The 23 October portal-transition report is not independently reproduced. Code
review found that clearing a temporarily absent unit preserved native groups but
never requested a reparse. That clear path now uses the existing native refresh:
`UpdateAllAuras()` during combat, and the existing Hide/Show refresh outside combat.
Groups remain armed for reacquisition; no GUID or aura payload is read. Fallback
behavior is unchanged. The regression verifies refresh requests on disappearance
and combat-time return, not Blizzard's actual removal of visible icons.

Live verification required: with Target and ToT auras visible, let ToT disappear,
clear/reacquire Target, and cross an instance portal, both solo and in a party,
in and out of combat. Check that old icons disappear and current auras return.
Repeat with native mode disabled or a naturally occurring fallback, and check
for duplicate icons, Lua errors, blocked actions and taint. Record client build
and native diagnostics; automated tests do not verify live protected rendering.
