# ADR 0009 — Two delivery modes on one trunk: promotion is a PR between environment folders

- **Status:** Accepted
- **Date:** 2026-11-14

## Context

Today a merge to `main` is live at once. Both ArgoCD Applications track `main`
with auto-sync. There is one control plane. `dev` and `prd` are a `mode` on a
claim, not separate places.

That is fine for a team that ships trunk-style. Many teams don't. They build
and test on dev, promote to UAT for the ITPM and PO to test, then promote to
prd for live traffic. Each promotion needs a named person to say yes. The
platform has no way to express that.

Infra has a second gap. Every claim follows its Composition through
`compositionUpdatePolicy: Automatic`, so a Composition edit reaches dev and prd
in the same sync. That is how a preset change half-replaced two VPCs
(learning record 0009, [ADR 0008](./0008-guard-replace-forcing-fields.md)).
Nothing is proven on dev before prd gets it.

### Goals

- A tenant team can pick **trunk** or **staged** delivery, per service.
- A promotion to UAT or prd needs an approval from that service's approver, and
  leaves a record of who approved what.
- The same flow covers app claims and infra claims.
- A Composition change reaches dev first, and UAT and prd only when promoted.
  prd always runs a pinned, known version.

### Non-goals

- Designing `WebApp` or where app environments run (Phase 5).
- A promotion controller (Kargo). It can be layered on later.
- Requiring two approvers. The layout allows it; it is not built now.
- Rolling out changes to the control plane itself (`platform-control-plane`).

### Anti-goals

- Nothing reaches prd without an approver, in either mode.
- What reaches prd must never differ from what was tested in UAT.
- One tenant's promotion must never carry another tenant's changes with it.
- An approver must not need to read YAML to know what they are approving.

## Decision

### 1. One branch. One folder per tenant and environment.

Example first:

```
infra-requests/atlas/dev/vpc.yaml
infra-requests/atlas/uat/vpc.yaml
infra-requests/atlas/prd/vpc.yaml
app-requests/atlas/dev/payments.yaml
app-requests/atlas/uat/payments.yaml
app-requests/atlas/prd/payments.yaml
```

The rule: `<tenant>/<env>/<name>.yaml`, under `infra-requests/` and
`app-requests/`. A **tenant is a project**, such as `atlas`. A project holds
several services (`payments`, `ledger`). Its infra is shared by those services.
Each service is one file under `app-requests/`. Environments are `dev`, `uat`, `prd`. A team that wants a SIT
adds a `sit/` folder; the name is not special.

Each file is its own claim with its own name. The folder is for people,
`CODEOWNERS` and tooling. ArgoCD already recurses, so it needs no change.

A claim's identity is still its namespace and name
([ADR 0005](./0005-claim-identity-namespace-and-state-key.md)). The namespace
stays the tenant. The environment goes in the claim's name and its `env` tag,
as `dev-vpc-1` does today. Moving a file between folders does not rename the
claim, so no state key moves.

### 2. Promotion is a PR that copies a tested version up one environment.

The PR touches only the target environment's file. What it copies:

| Claim | The version that moves |
|---|---|
| App (`WebApp`) | the image tag, and the Composition revision pin |
| Infra (`XNetwork`, `XEKSCluster`) | the Composition revision pin, and the `spec` fields that are not per-environment |

Per-environment fields are never copied: `mode`, `cidr`, the claim name and
`tags.env`.

A Backstage "Promote" action opens the PR, the same way the edit template
does. A PR opened by hand is equally valid.

### 3. Approval is a GitHub review, set by `CODEOWNERS`.

```
/infra-requests/atlas/uat/   @atlas-approver
/infra-requests/atlas/prd/   @atlas-approver
/app-requests/atlas/uat/     @atlas-approver
/app-requests/atlas/prd/     @atlas-approver
```

A line can also name one service's file, if that service needs its own
approver.

`main` is protected and requires a code-owner review. The merge is the
approval. The PR is the audit record.

The ITPM and PO are one person for now, so one owner per path is enough. The
lines are per service and per environment on purpose. A second approver, and a
required check that both have approved, can be added later without moving
files. `CODEOWNERS` on its own is satisfied by any one owner.

The PR description is written for the approver: what is promoted, what changed
since the version in the target environment, and a link to where it was tested.
The Promote action generates it.

### 4. Trunk and staged differ only in how many environments come first.

| | Trunk | Staged |
|---|---|---|
| Environments | `prd` only | `dev`, `uat`, `prd` |
| `CODEOWNERS` lines for the service | on `prd/` | on `uat/` and `prd/` |
| Merge to `prd/` | after the approver's review | after the approver's review |
| Infra Composition version | `prd` pinned | `dev` follows the newest; `uat` and `prd` pinned |

Nothing reaches prd without an approver, in either mode. A trunk team skips the
lower environments, not the gate.

A service's mode is which environment folders it has. There is no separate
`deliveryMode` field to keep in step.

### 5. For infra, the Composition release is the version.

- **dev** claims keep `compositionUpdatePolicy: Automatic` with no selector.
  They take every new revision first.
- **uat** and **prd** claims are pinned to one release.
- **`prd` is always pinned**, in both modes. It is the same rule as never
  running a container image on `latest`: you can audit what prd ran, and you
  can rebuild it.
- Promoting moves the pin, in a PR, with the same approver.

The Composition release does for infra what the image tag does for an app.

A pinned claim looks like this:

```yaml
spec:
  crossplane:
    compositionUpdatePolicy: Automatic
    compositionRevisionSelector:
      matchLabels:
        release: "0.1.1"
```

**Pin by the `release` label.** Each Composition carries a semver `release`
label ([ADR 0010](./0010-xrd-changes-and-api-versions.md)). Crossplane copies it
to each new revision. The claim uses the newest revision with that label. A
promotion PR changes the label, for example `0.1.0` to `0.1.1`. People can read
and remember a release. They can't remember a hash.

The policy is `Automatic`, not `Manual`. The Crossplane docs describe a label
selector only with `Automatic`. With `Manual`, the docs say you move a claim by
editing `compositionRevisionRef`; they don't say that a selector change moves
it.

**The label must be unique.** If someone changes a Composition and forgets to
bump `release`, two revisions share a label. With `Automatic`, a claim on that
label then moves to the new revision by itself, with no PR on its folder. A CI
check prevents this (ADR 0010). The ruleset on `main` requires it.

*Amended 2026-11-22.* This decision first pinned by revision name
(`compositionUpdatePolicy: Manual` with `compositionRevisionRef.name`, for
example `xnetwork-d6f24a7`). It is exact, and a test on the cluster showed it
holds. It was replaced because people can't read a hash. A label pin with a
required uniqueness check gives the same exactness.

### 6. Environment and `mode` are separate things.

The environment is the folder: where a claim sits in the promotion flow, and
who must approve it. `mode` is a sizing and cost profile
([ADR 0003](./0003-dev-prd-mode-profiles.md)).

Example: the first claims on this platform are `prd`, in trunk mode. They use
`mode: dev` to save cost.

UAT infra should normally use `mode: prd`, so it tests what prd will run. It
costs more while it is up. Tear it down between test rounds.

## Alternatives considered

- **A branch per environment** (`dev`, `uat`, `main`, one ArgoCD Application
  each; promotion is a merge). Familiar from many companies. Rejected: branches
  drift, and prd can receive a merge result nobody tested. In one shared repo a
  branch merge promotes every tenant at once. The Backstage templates all open
  PRs against `main`.
- **A promotion controller (Kargo).** Purpose-built: stages, a pipeline view,
  verification, "only what passed dev". Not now: it is one more component to
  run, and it writes the same folder-per-environment commits underneath. This
  decision is the layer it would sit on.
- **ArgoCD manual sync as the gate.** Rejected: no record of who approved.
- **Promote the infra request only, not the Composition version.** Nothing to
  build. Rejected: a Composition edit would still skip the gate and reach every
  environment at once, which is the failure this is meant to stop.
- **`compositionUpdatePolicy: Manual` on everything** (raised in ADR 0008).
  Rejected: dev should take new revisions by itself, or nothing tests them.
- **Trunk with auto-merge and no approver.** The first draft of this ADR.
  Rejected: every deploy to prd needs an approver.

## Consequences

- Tenants run different Composition revisions at the same time. The platform
  must say how long each is supported. Crossplane keeps every revision: the
  cluster holds all 8 of each Composition, back to the first. ArgoCD has not
  pruned them.
- Reverting a Composition to earlier content is a new release with a new
  label. A label change makes a new revision, so a pin to the old label still
  finds the old revision.
- A pin does not make a breaking change safe. If a revision changes something
  that replaces infrastructure, moving the pin replaces it. Breaking revisions
  are planned as their own change, and the promotion PR must say so.
- A trunk tenant has no dev claim of its own. A revision it promotes was
  exercised only by other tenants' dev claims.
- The pin does not cover the XRD (`definition.yaml`). An XRD has no revisions.
  A change to it applies to every claim at once, pinned or not.
  [ADR 0010](./0010-xrd-changes-and-api-versions.md) covers how XRD changes are
  staged.
- The pin covers the Composition's content. It does not cover the
  go-templating function version, the provider version, or floating module
  constraints inside the HCL (`~> 5.0`). Those still move for everyone. Pinning
  module versions exactly is the Renovate work in the roadmap.
- Approvers need GitHub accounts with write access. Branch protection still
  stops direct pushes to `main`.
- GitHub does not let a PR's author approve it. The Promote action must open
  PRs as an identity that is not the approver. Backstage will use a GitHub App
  for this.
- Branch protection needs a public repo or a paid plan on a personal account.
- The create and edit templates change: they take a tenant and an environment,
  and write to the new path. The `source-file-url` annotation follows the path.
- Existing claims move into the new layout. Their names and namespaces stay, so
  it is a file move only. The current namespace `dev` is an environment name
  used as a tenant; new tenants get a real tenant namespace.
- `app-requests/README.md` says `<namespace>/<kind>/<name>.yaml`. This replaces
  it with `<tenant>/<env>/<name>.yaml`.
- Presets stay append-only (ADR 0008). The pin is a second guard, not a
  replacement.
- Until the CI check exists, a forgotten label bump reaches every claim pinned
  to that label. The reviewer of each Composition PR must check the label.

## To settle before building

**The Composition-pinning session.** It decides:

- The Promote template's steps and the PR description format.
- The order of the migration for the existing claims.
- A test on the cluster: pin a claim, move the pin forward and back, and read
  the plan each time.

**Left to Phase 5:**

- Where each app environment runs (namespaces in one cluster, or a cluster per
  environment).
