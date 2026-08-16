# ADR 0003 — `dev`/`prd` mode profiles for `XEKSCluster`

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

Cluster sizing (capacity type, instance type, node counts, endpoint) varies mostly
by **environment class**, not field by field. Exposing every knob raises cognitive
load; hiding them all removes needed flexibility.

## Decision

- `XEKSCluster` takes a **required `mode: dev | prd`** that selects an opinionated
  preset:
  - `dev` → SPOT / t3.small / min 1 · desired 2 · max 3
  - `prd` → ON_DEMAND / t3.medium / min 2 · desired 3 · max 6
- Individual node fields stay optional **overrides**:
  `effective = preset[mode] merged with explicit fields`.
- `mode` is **required** (no default) — it forces an explicit dev-vs-prod decision,
  so nobody runs prod on dev settings by accident.

## Alternatives considered

- **Expose all node fields, no modes** — maximum flexibility, maximum cognitive
  load; every requester hand-tunes. Rejected (this is a golden path).
- **Hide all sizing behind one fixed profile** — simplest, but loses the dev/prod
  distinction. Rejected.
- **`mode` optional, default `dev`** — convenient, but risks silently running prod
  on dev settings. Rejected in favour of required.

## Consequences

- Adding a mode (e.g. `staging`) or tuning a preset is a one-place platform change.
- Power users override individual fields without abandoning the profile.
- The conditional, overridable-default logic drives the composition-function choice
  — see ADR 0004.
