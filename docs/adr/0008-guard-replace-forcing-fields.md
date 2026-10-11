# ADR 0008 — Replace-forcing fields are immutable; presets are append-only

- **Status:** Accepted
- **Date:** 2026-10-11

## Context

[ADR 0006](./0006-mode-preset-pattern-for-infra-xrds.md) made mode presets with
per-field overrides the standard shape. It didn't say what happens when a
preset or a field changes under live infrastructure.

On 2026-10-11 the `dev` CIDR preset changed from `/16` to `/20`. Every XNetwork
without its own `cidr` followed it, through `compositionUpdatePolicy:
Automatic`. A VPC's CIDR can't change in place, so OpenTofu planned a replace.
It deleted the subnets, then deadlocked: the old VPC couldn't be deleted while
the Internet Gateway was attached, and the plan only moved the IGW once the new
VPC existed. After 20 minutes the provider killed the run, which left a state
lock and unsaved state. Two VPCs were left with no subnets
(learning record 0009).

The same kind of break can come from three directions: editing `cidr` on a
claim, switching `mode` (which switches the preset), and editing a preset.
Shrinking `azCount` is a cousin: it deletes subnets, and that hangs the same way
once anything (EKS nodes) has ENIs in them.

## Decision

**Fields that would replace or remove live infrastructure can't change after
creation. The API server enforces this with CEL transition rules in the XRD.**

For `XNetwork`, on `spec`:

- `mode` is immutable.
- `cidr` can be added (pinning a claim to its live value), but never changed
  or removed.
- `azCount` can only grow.

**Presets are append-only.** A preset's values are never changed in place. A
new need gets a new mode. A comment above the presets in the Composition says
so.

## Alternatives considered

- **`compositionUpdatePolicy: Manual` for networks.** It stops every Composition
  change from rolling out on its own, which covers presets too. Not now: every
  change would need a per-XR upgrade step, and we have no tooling for that yet.
  Revisit with the Composition-revisions work in ROADMAP Phase 3.
- **Write the resolved CIDR into the XR at creation.** Presets could then never
  move an existing VPC. Rejected for now: it adds logic to the Composition, and
  the write-back must never fight the CEL rule.
- **A Kyverno validate policy instead of CEL.** It would work the same way, but
  it adds a dependency and keeps the rule away from the API it protects. CEL
  ships with the API server and lives in the XRD.
- **Do nothing, and rely on reading the plan.** Nobody sees the plan before
  apply in this setup, so that isn't a control.

## Consequences

- Bad edits fail early and visibly, as an ArgoCD sync error with a clear
  message, instead of as a stuck Workspace twenty minutes later. This applies
  to every client: ArgoCD, `kubectl` and the Backstage edit form.
- Changing a CIDR now means requesting a new network and moving onto it. That
  is honest: it was always a replace.
- The rules run only on update. A claim created with a bad value is still
  caught only by the schema (`pattern`, `minimum`) or by AWS.
- Presets have no technical guard. A preset edit still rolls out to every XR
  that relies on it. The guard is the comment and this ADR.
- `XEKSCluster` doesn't have rules yet. Its replace-forcing fields need checking
  with `tofu plan` first (ROADMAP Phase 3).
