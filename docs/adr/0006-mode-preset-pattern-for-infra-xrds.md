# ADR 0006 — Mode presets with per-field overrides are the standard shape for infra XRDs

- **Status:** Accepted
- **Date:** 2026-09-13

## Context

[ADR 0003](./0003-dev-prd-mode-profiles.md) chose `dev`/`prd` mode presets for
`XEKSCluster`. `XNetwork` was then written the same way: a required `mode`
selects a preset, and individual fields can override it.

So this is no longer one XRD's design. It is the shape every infra XRD here
follows, and the next one should follow it too.

Writing the second one also surfaced four rules that are not obvious from reading
the finished Compositions. Each was found by breaking something. They are written
down here so the third XRD does not rediscover them.

## Decision

Every infra XRD uses this shape:

- A **required `mode`** field with an enum, usually `dev | prd`.
- A **preset per mode**, held in the Composition, holding the values that
  genuinely differ between environments.
- **Optional override fields** in the XRD. An explicitly set field beats the
  preset; an unset field keeps the preset value.

In the Composition that reads:

```
{{- $p := index $presets $xr.spec.mode -}}
...
value: "{{ $xr.spec.cidr | default $p.cidr }}"
```

### Rule 1 — a preset-controlled field must have no `default:` in the XRD

An XRD `default:` is applied by the API server at admission, *before* the
Composition template runs. So the field is never empty, `| default` never fires,
and the preset is silently ignored.

This is easy to miss because nothing errors. A `mode: prd` claim simply comes out
with dev values.

### Rule 2 — the selector field is the exception

`mode` itself has no default either, but for the opposite reason: nothing falls
back from it. It must be listed in the XRD's `required:` instead.

Removing its default *without* making it required gives
`index $presets nil` at render time. Note that `required:` is a sibling list of
`properties:`, not a flag inside a field.

### Rule 3 — not every preset value should be overridable

Some values are a platform decision, not a per-claim one. `XNetwork` fixes NAT
gateway on for `prd` and off for `dev`, and offers no override field. The
Composition reads the preset directly:

```
value: "{{ $p.natGateway }}"
```

Deciding "overridable or platform-fixed" is a per-field choice, made when the
field is added.

### Rule 4 — never use `| default` on a boolean or a number that can be zero

`default` treats `false` as empty, so `{{ false | default true }}` renders
`"true"`. The same trap applies to `0`.

A boolean that genuinely needs an override needs an explicit `if`, not
`| default`.

## Alternatives considered

- **Amend ADR 0003 to cover both XRDs.** Rejected. ADR 0003 records a real
  decision made for `XEKSCluster` on a specific date, and this repo's convention
  is not to rewrite past ADRs. It stands as the first instance of the pattern.
- **Leave the pattern undocumented and let people copy an existing
  Composition.** This is what actually happens if nothing is written down, and
  copying carries the shape but not the reasoning. All four rules above are
  invisible in a working Composition — you cannot see an absent `default:`.
- **Expose every field with no presets.** Already rejected in ADR 0003;
  restated here because it is the obvious thing to reach for when a preset feels
  restrictive. The answer is to add an override field, not to drop the preset.

## Consequences

- Adding a mode, such as `staging`, is a one-place change per Composition.
- Adding a field means three decisions: does it go in the preset, is it
  overridable, and does the override need a real `if` rather than `| default`.
- Every XRD field that is preset-controlled must be checked for a stray
  `default:` in review. It is the most likely mistake, and the quietest.
- Render tests should assert three paths per layer: the `dev` preset, the `prd`
  preset, and an override claim. The override test must also assert the preset
  value is *absent*, since a leaked preset otherwise looks like a pass.
