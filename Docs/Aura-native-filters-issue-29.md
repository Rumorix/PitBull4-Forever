# Forever native aura filter compatibility (issue 29)

This guidance describes the Forever v064 source identified by README.md and
PitBull4_Mainline.toc, separate from the Retail/Midnight fork. The issue cites
v061; no comparison with that historical baseline or live WoW 12.1.5 validation
is claimed here.

## Native filtering and migration

Under the layout's Aura > Filters options, the supported selections are:

| Selection | Native buff filter | Native debuff filter |
| --- | --- | --- |
| None | `HELPFUL` | `HARMFUL` |
| Only my auras (native) | `HELPFUL|PLAYER` | `HARMFUL|PLAYER` |

None means no additional PitBull filter; it does not hide all auras. Blizzard
owns aura selection through these filter strings. PLAYER is not a promise of
the old compound "mine" rules, including their pet and visibility behavior.

Saved filter identifiers remain in the profile. In
`Modules/Aura/NativeContainer_12_1.lua`, `get_filter_string` maps them as follows:

- `!C` and `!E` use the base filter plus `PLAYER`.
- Empty/unset identifiers and `!B`, `!D`, `!N`, `!P`, `!Q` use the base filter.
- Other identifiers use the base filter with an `approximate:` diagnostic tag.

These are substitutions, not evaluation of the legacy expressions in
`Modules/Aura/Filter.lua`. Custom spell-name, meta and Lua filters have no
one-to-one native replacement. A saved custom filter can therefore show more
auras than expected. Ownership grouping can split the base selection into
PLAYER and !PLAYER groups; it does not restore legacy filter semantics.

To migrate, review the buff and debuff selections for each affected layout
outside combat and explicitly choose None or Only my auras (native) according
to the desired native selection. Selecting an option replaces that layout's
selected filter identifier; this documentation change itself does not rewrite
profiles or delete saved filter definitions.

## Highlights and previews

After a successful native update, the Aura module clears legacy buttons and
deletes `frame.aura_highlight`. Legacy Aura highlight rules do not control that
native display, even if their settings remain saved.

For dispel highlighting, configure the separate **Dispel highlights** module.
Its source selects `HARMFUL|RAID` when restricted to dispels available to the
player, otherwise `HARMFUL|DISPELLABLE`, and delegates selection and dispel-color
presentation to Blizzard. This is a narrower feature, not a replacement for
arbitrary spell-specific or custom highlight rules. Actual availability and
selection require validation on the installed client and class/spec.

Config Mode uses the legacy sample renderer. A preview can therefore differ
from the successful native runtime display. Older clients and native failure
paths can also use the legacy renderer. Disabling native rendering is not an
established safe workaround for protected aura restrictions.

## Validation

This correction changes an options description and documentation only. It
does not add aura inspection, protected API calls, combat configuration changes
or saved-profile migrations. The relevant source paths are
`get_filter_string`, `get_ownership_group_filters` and `UpdateFrame` in
`Modules/Aura/NativeContainer_12_1.lua`, and `get_filter` / `initialize_button`
in `Modules/DispelHighlights/DispelHighlights.lua`.

Local syntax/format checks, from the repository root:

```sh
luac5.1 -p Modules/Aura/Options.lua
git diff --check
```

No automated gameplay regression fixture is added for this text-only change.
Static review cannot establish Blizzard API acceptance or combat/taint safety.
In-game tests have not been run. On the actual WoW 12.1.5 client, record the
exact build, Forever version, class/spec and affected layout, then:

- Compare None and Only my auras with own, pet and other-player buffs/debuffs.
- Load a copy of a profile with a known custom/meta filter. Record the saved
  identifier, expected auras and observed base-filter fallback before explicitly
  changing the selection. Verify unrelated profile settings are preserved.
- Compare saved legacy highlight expectations with native runtime behavior and
  the separate Dispel highlights module; include dispellable and
  non-dispellable debuffs.
- Compare Config Mode previews with normal runtime and transitions between them.
- Exercise player, target, party and raid frames before, during and after
  combat, including aura changes and target switches. Make configuration changes
  outside combat and verify deferred changes settle after combat.
- Capture sanitized `/pitbull 121status` output and check Lua/taint logs for
  secret-value errors and blocked actions. Inspect per-frame buffFilter and
  debuffFilter modes: a zero approximateFilters total alone does not establish
  legacy parity, and grouping prefixes can mask that counter's approximation
  detection in this source.
