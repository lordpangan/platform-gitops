# infra-requests/

The **infra claims** — the small requests that spin up real cloud resources (and
cost real money): the AWS substrate (VPC, IAM/OIDC) and the EKS workload cluster.

These are **claims** (namespaced Composite Resources in Crossplane v2) against an
infra XRD such as `XEKSCluster`. They are *not* raw Managed Resources: the
`provider-opentofu` `Workspace` that actually runs the OpenTofu is hidden
**inside the infra Composition** (in [`../definitions/`](../definitions/)). We
request infra the same way developers request apps — through a claim — so the
abstraction boundary is real on both layers.

Platform-team owned. Changes rarely, but every change here touches real cloud
spend — review carefully, and keep teardown one clean step.

## Conventions

**Namespaces are the tenancy boundary.** Claims live in a namespace that belongs
to whoever owns the workload — not in `argocd`, which is the GitOps controller's
own namespace. The composed `Workspace` is created in the claim's namespace too,
and the namespace is part of the OpenTofu state key, so the choice is load-bearing
rather than cosmetic. Namespaces are committed here alongside the claims that
need them.

**Sync waves order the apply**, lowest first:

| Wave | Resource | Why |
|------|----------|-----|
| `0` | `Namespace` | Must exist before anything lands in it |
| `1` | `XNetwork` | The VPC the cluster is discovered into |
| `2` | `XEKSCluster` | Finds its VPC by the `network=<name>` tag |

A Lua health check (control-plane ADR 0008) keeps each XR Progressing until it
is `READY=True`, so a later wave waits until the earlier one's cloud resources
exist.

**Claim names are immutable in practice.** Renaming one is a destroy-and-recreate,
not a rename — see [`../definitions/README.md`](../definitions/README.md).

**Some fields can't change after creation.** The API server rejects these
updates (CEL rules in the XRD), because each one would replace or remove live
infrastructure:

| `XNetwork` field | Rule |
|---|---|
| `mode` | can't change: it picks the preset, and so the CIDR |
| `cidr` | can be added once (pinning), then never changed or removed |
| `azCount` | can only grow |

The error shows up in the ArgoCD sync, e.g. `cidr can be set once, then never
changed or removed`. To get a different CIDR, request a new network.

## How to request

- **Backstage:** Create → "Create a Network (XNetwork)" or "Create an EKS
  cluster (XEKSCluster)". Each opens a PR that adds `<name>.yaml` here, with
  the sync-wave and the `source-file-url` annotation already set. The EKS form
  picks its network from the existing XNetworks.
- **By hand:** copy an existing claim. Keep the `argocd.argoproj.io/sync-wave`
  annotation, and add `terasky.backstage.io/source-file-url` if you want to
  edit it from Backstage later.
