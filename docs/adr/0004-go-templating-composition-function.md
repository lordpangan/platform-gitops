# ADR 0004 — Go-templating composition function (over patch-and-transform)

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

The `XEKSCluster` Composition must compute
`effective config = preset[mode] merged with explicit overrides` — conditional,
overridable defaults (see ADR 0003) — and emit the `Workspace`.

## Decision

- Use **`function-go-templating`** to compute the merge explicitly and render the
  composed `Workspace`.

## Alternatives considered

- **`function-patch-and-transform`** — *can* express this (a `map` transform per
  field for the preset, plus an ordered `Optional` patch per field for the
  override), and it's the canonical mechanism with no extra dependency. Rejected as
  the primary approach: the override relies on **implicit patch-ordering +
  skip-on-absent** semantics, which reads poorly and is easy to break, and the
  patch list grows multiplicatively as modes/fields are added. Kept as a viable
  **fallback**.
- **`function-kcl`** — also expresses conditional logic cleanly; comparable to
  Go-templating. Either would do; Go-templating chosen for its ubiquity, simple
  templating model, and because the render harness already runs it.

## Consequences

- Render tests must cover the `mode` presets **and** override-beats-preset — the
  logic lives in the template, so it's exactly what we assert.
- No new dependency: the harness (ticket 01) already runs `function-go-templating`.
- Genuinely complex computation (subnet math, loops) stays in the OpenTofu modules,
  keeping the template flat and readable.
