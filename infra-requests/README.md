# infra-requests/

The **infra claims** — the small requests that spin up real cloud resources (and
cost real money): the AWS substrate (VPC, IAM/OIDC) and the EKS workload cluster.

These are **claims** (namespaced Composite Resources in Crossplane v2) against an
infra XRD such as `XEKSCluster`. They are *not* raw Managed Resources: the
`provider-terraform` `Workspace` that actually runs the Terraform is hidden
**inside the infra Composition** (in [`../definitions/`](../definitions/)). We
request infra the same way developers request apps — through a claim — so the
abstraction boundary is real on both layers.

Platform-team owned. Changes rarely, but every change here touches real cloud
spend — review carefully, and keep teardown one clean step.

Filled in during **Phase 2** of the roadmap.
