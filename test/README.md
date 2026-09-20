# test/ — the offline render harness

Every XRD and Composition in [`definitions/`](../definitions/) is asserted here.
The tests run on your laptop. No cluster, no AWS, no spend.

Run them from the repo root:

```sh
make test   # all seven cases
make help   # list every target
```

## What `crossplane render` does

A Composition with `mode: Pipeline` does no templating itself. Each step hands
the work to a **function** over gRPC. So rendering a Composition means running
its functions.

`crossplane render` runs them as local containers:

1. It reads `functions.yaml` to learn which function packages the test needs.
2. It starts each one as a container listening on gRPC.
3. It sends each pipeline step's request to the matching container.
4. It collects the rendered output and tears the containers down.

Nothing persists between runs. The image layers stay in Docker's cache, so only
the first run downloads anything.

You need a Docker daemon for step 2. Docker Desktop works, so does
`colima start`. The Makefile reads your active `docker context` and points
render at the right endpoint.

**Colima only supplies the Docker daemon here.** There is no Kubernetes and no
Crossplane running in it. The functions are plain containers.

## Why `functions.yaml` exists

The cluster knows which functions are installed because Crossplane keeps
`Function` objects. `crossplane render` has no cluster to ask. You tell it
instead, and `functions.yaml` is how.

The file uses the same `kind: Function` YAML a cluster would, but nothing is
installed from it. It is an argument to a command.

## Keep the versions in sync

The same function packages are installed in the kind cluster by the `functions`
Ansible role in **platform-control-plane**. Its versions live in
`ansible/group_vars/all.yml`.

So each version is written down twice, in two separate git repos. They can
drift. If they do, `make test` passes against one version while the cluster runs
another, and these tests stop predicting the cluster.

There is no shared file to fix this. The repos are cloned independently. When
you change a function version, change it in both places.

## Layout

```
test/
  functions.yaml      # which functions render should run
  smoke/              # proves the harness itself works
  xnetwork/           # XNetwork claims
  eks/                # XEKSCluster claims
```

`smoke/` holds its own throwaway Composition. It is not part of the platform.
It renders one ConfigMap, so a failure there means the harness is broken, not a
definition.

`xnetwork/` and `eks/` hold three claims each, and each layer is asserted three
ways:

| file | asserts |
|---|---|
| `xr.yaml` | the `dev` preset |
| `xr-prd.yaml` | the `prd` preset |
| `xr-override.yaml` | explicit `spec.*` beats the preset, and un-overridden preset values do not leak |

The Compositions themselves stay in `definitions/`. Only the claims live here.

## How an assertion works

Each `test-*` target renders once into a shell variable, then greps it. Two
helpers do the checking:

- `check <regex> <name>` — fails if the pattern is **missing**
- `refute <regex> <name>` — fails if the pattern is **present**

`refute` is for things that must never come back. Every target ends with
`refute '<no value>'`, because a broken Go template path renders that literal
string instead of erroring. `test-eks` also refutes the old `env = var.cluster_name`
bug.

## What these tests cannot catch

Render checks the composed `Workspace` — its structure and its variables. It
never parses the OpenTofu inside `module: |`.

So these all pass here and fail at a real apply:

- HCL syntax errors
- undeclared or unreferenced variables
- duplicate arguments in a block (this has happened — a duplicate `key =` in a
  backend rendered clean and passed the whole suite)
- OpenTofu module and provider version conflicts

Render also has no package manager. There is no dependency resolution and no
`Installed`/`Healthy` condition. The function image just runs. A function that
is broken in the cluster can still render fine here.
