Issue #7: bounded native renderer recovery

Scope: checked-out Forever v064 source, not the issue's v061 baseline or the
separate Retail fork. No saved-profile fields or client API contracts change.

PLAYER_REGEN_ENABLED grants each failed frame one automatic native retry when
public capability checks pass. The next eligible update consumes the grant only
outside combat and outside Config Mode. Failures remain visible to diagnostics
and legacy ticker selection until the attempt succeeds. Repeated combat exits
cannot replenish a spent retry. Full successful configuration, explicit rebuild,
or disabling native rendering resets the budget. No timers or retry loops added.

Local validation: python3 Tests/native_retry.py runs a Lua 5.1 harness against the
real renderer entry point and native update control flow with container operations
stubbed. It covers creation/configuration failures, ordinary-update suppression,
capability gating, combat deferral, bounded persistent failures, successful cleanup,
and rebuild/toggle resets. It does not emulate protected frames or secret values.
Lua 5.1 syntax checks and git diff --check also pass.

Fallback review: the existing legacy renderer still receives failed updates and
its normal arguments. Update.lua applies configured filters to collected auras,
but Filter.lua's FilterEntry can accept secret auras without evaluating custom
filters. Equivalent custom/ownership filtering in fallback is therefore NOT
established; this patch does not change that independent behavior.

NOT run: real WoW 12.1.5/Forever client testing, taint/protected-operation checks,
secret aura tests, or visual/filter comparisons. In-client validation should inject
a transient creation/configuration failure, end combat, and verify native recovery
without duplicate/stale icons. Repeat with persistent failures across combat exits,
Config Mode, disabled groups, custom/ownership filters, and player/target/party/raid
units. Confirm one retry, retained failure status on repeat failure, and no blocked
actions. Manual rebuild/toggle remain the recovery path after an exhausted retry.
