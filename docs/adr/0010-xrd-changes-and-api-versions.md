# ADR 0010 — XRD changes: additive changes go in place; the route for breaking changes is pending a test

- **Status:** Proposed
- **Date:** 2026-11-15

## Context

[ADR 0009](./0009-trunk-and-staged-promotion.md) promotes a Composition through
environments by pinning each claim to a revision. That does not work for the
XRD (`definition.yaml`).

Take `XNetwork`. There is one definition in the cluster. Dev, UAT and prd
claims all use it. It has no revisions. An edit to it reaches every claim in
the same sync.

XRD changes come in three kinds:

| Kind | Example | Effect on existing claims |
|---|---|---|
| Add an optional field | a new `flowLogs` field | None, until a claim sets it. |
| Tighten a rule | make `cidr` required | Claims that break the rule fail on their next update. |
| Remove or rename a field | `azCount` becomes `zones` | Claims that use the old field break. |

The last two are **breaking changes**.

### What the docs say

From the Crossplane docs
([Composite Resource Definitions](https://docs.crossplane.io/latest/composition/composite-resource-definitions/)):

- "Only one version can be `referenceable`." Compositions use that version.
- "Changing which version is `referenceable:true` requires updating the
  `compositeTypeRef.apiVersion` of any Compositions referencing that XRD."
- "Crossplane supports defining multiple `versions`, but the schema of each
  version can't change any existing fields."
- "New versions may define new optional parameters, but new required fields are
  a 'breaking change.'"
- "Breaking schema changes between versions requires the use of conversion
  webhooks."
- "Crossplane recommends implementing breaking schema changes as brand new
  XRDs."
- "Changing or expanding the XRD schema requires restarting the Crossplane pod
  to take effect."

Checked on the cluster (Crossplane v2.3.4): our XRDs use conversion strategy
`None`. It only changes the `apiVersion` text. It cannot rename or move a
field.

So a claim's `apiVersion` is not a pin the way a Composition revision is. And a
new version is not the place for a breaking change.

## Decision

### 1. Adding an optional field happens in place.

No new version. No promotion step for the XRD itself. The field does nothing
until a claim sets it and that claim's pinned Composition revision reads it.
Those two already promote per environment (ADR 0009).

### 2. New fields get no default in the XRD.

A schema default is applied to every existing claim at once. Defaults live in
the Composition, as the mode presets already do
([ADR 0006](./0006-mode-preset-pattern-for-infra-xrds.md)). The Composition is
pinned, so a default is promoted like any other change.

### 3. A new `apiVersion` is for milestones, not for breaking changes.

`v1alpha1` today. A move to `v1beta1`, then `v1`, says the API has matured. The
new version may add optional fields. It does not change or remove existing
ones.

This replaces an earlier draft, which said a breaking change moves the API to
`v1alpha2`. The Crossplane docs rule that out without a conversion webhook.

### 4. Breaking changes: pending the test.

Two routes. The test below picks one.

**Route A: expand, migrate, contract, in place.** Example: make `cidr` required.

```
Expand    XRD: cidr stays optional              harmless, reaches everyone at once
Migrate   PR adds cidr to the dev claims        no approver
          PR adds cidr to the uat claims        approver
          PR adds cidr to the prd claims        approver
Contract  XRD: cidr becomes required            only when no claim lacks it
```

The migrate steps are ordinary promotion PRs (ADR 0009). A CI check validates
every claim in git against the changed XRD, and blocks the contract PR while
one fails. A rename works the same way: add the new field, have the Composition
read either, move the claims, then remove the old field.

Cheap, and it reuses what we have. The Crossplane docs do not cover it.

**Route B: a brand new XRD.** What Crossplane recommends. The new API gets its
own kind and its own Composition. Claims move to it one environment at a time.

Documented and fully independent. Heavier: for infra, each claim becomes a new
object, which risks a destroy and recreate unless the new claim can take over
the old state.

**The test** (on the cluster, with a throwaway claim):

1. Tighten a rule in place while one claim complies and one does not. What
   happens to each, on sync and on its next update?
2. Does the XRD change take effect without restarting the Crossplane pod?
3. Does a claim pinned to an older Composition revision keep reconciling after
   the XRD changes?

If the complying claim is untouched and the failure is clear and early, use
Route A for tightening, renames and removals, and keep Route B for a full
redesign. If not, Route B is the route.

### 5. Each Composition carries a semver release label.

Example:

```yaml
metadata:
  name: xnetwork
  labels:
    release: "0.1.1"
```

Crossplane names a revision from a hash of its content, such as
`xnetwork-d6f24a7`. People can't read that. Each new revision copies the
Composition's labels, so `kubectl get compositionrevisions -L release` shows
the release next to the hash.

Every change to a Composition bumps `release`:

| Change | Bump | Example |
|---|---|---|
| Breaking: it replaces infrastructure, or removes or renames something a claim relies on | major | `1.4.2` to `2.0.0` |
| A new feature that existing claims don't need to change for | minor | `1.4.2` to `1.5.0` |
| A fix or a small update | patch | `1.4.2` to `1.4.3` |

While the API is `v1alpha1` or `v1beta1`, the major stays `0`. This follows
semver: a `0.y.z` release is not yet stable. During `0.y.z`, a breaking change
bumps the minor.

Claims pin by this label (ADR 0009). So each label must belong to one
revision only.

### 6. A required CI check keeps each release label unique.

On every PR, a check compares each changed Composition with `main`. It fails
when:

- the content changed but `release` didn't, or
- the new `release` isn't higher than the old one, or
- a new Composition has no `release` label.

The ruleset on `main` requires the check to pass before a merge. The check
can't judge whether the bump is the right size (major, minor or patch). The
reviewer judges that.

*Amended 2026-11-22.* This first said claims pin by revision name and the label
is only for people. ADR 0009 now pins by the label, so the check became
required.

The first label is `0.1.1`. The revisions before it have no label.

## Alternatives considered

- **Serve `v1alpha2` beside `v1alpha1`, and treat a claim's `apiVersion` as its
  per-environment pin.** It looks most like promotion. Rejected: the docs allow
  a new version to add optional fields only. One version is stored, and nothing
  converts between them.
- **A conversion webhook.** It would allow breaking changes between versions.
  Rejected: a service to write, run and keep available for every API call.
- **A control plane per environment.** The XRD itself would be promoted from
  one cluster to the next. The only option that truly promotes a definition.
  Rejected for now: it doubles what we run, and changes the one-control-plane
  design.
- **Crossplane Configuration packages.** The XRD and Composition are bundled in
  an image with a semver tag. Not now: one cluster still installs one version,
  so it does not stage by environment.

## Consequences

- An additive XRD change still reaches every environment at once. It is safe
  only because it is optional and has no default.
- A claim can set a new field while its pinned Composition revision is too old
  to read it. The field is then ignored, silently. A promotion PR should move
  the pin and set the field together.
- A breaking change takes several PRs and some calendar time, on either route.
- The Backstage `kind: API` schema is a copy of the XRD's `spec`. It changes
  with every XRD edit.
- If the pod restart turns out to be needed, it becomes a step in every XRD
  rollout.

## To settle before building

- **Run the test** in Decision 4, and write the chosen route into this ADR.
- **Build the CI check** in decision 6, and add it to the ruleset.
- **Which tool runs the CI check** (the render tests in `test/` are the
  starting point).
