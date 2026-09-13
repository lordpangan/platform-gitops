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

Waves order the *apply*, not readiness: ArgoCD has no health check registered for
these custom kinds, so it reports them Healthy the moment they are applied rather
than when the cloud resources exist. A later wave can therefore start before an
earlier one has finished building. Crossplane retries until it converges, so this
is noisy rather than fatal — expect the EKS `Workspace` to fail its VPC lookup a
few times on a cold build.

**Claim names are immutable in practice.** Renaming one is a destroy-and-recreate,
not a rename — see [`../definitions/README.md`](../definitions/README.md).
