# Render-test harness for the platform-gitops definitions.
# Uses the shared platform-engineer devbox (crossplane CLI) + colima/Docker.
# `crossplane render` runs composition functions as local containers — offline, $0.

# Point render at whatever Docker endpoint the active context uses (colima or
# Docker Desktop); render otherwise defaults to /var/run/docker.sock.
DOCKER_HOST ?= $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
export DOCKER_HOST

# The shared devbox.json is one directory up (platform-engineer). devbox only
# reads the config in its own dir, and its --config flag mishandles `--` args, so
# we cd up to run the crossplane binary and pass absolute paths ($(CURDIR)/...).
CROSSPLANE := cd .. && devbox run -- crossplane
FUNCS      := $(CURDIR)/test/functions.yaml

.DEFAULT_GOAL := help
.PHONY: help render-smoke test-smoke

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

render-smoke:  ## Render the harness smoke composite (prints composed output)
	@$(CROSSPLANE) render $(CURDIR)/test/smoke/xr.yaml $(CURDIR)/test/smoke/composition.yaml $(FUNCS)

test-smoke:  ## Prove the render harness works end to end (render + assert)
	@out="$$($(CROSSPLANE) render $(CURDIR)/test/smoke/xr.yaml $(CURDIR)/test/smoke/composition.yaml $(FUNCS) 2>/dev/null)"; \
	if echo "$$out" | grep -q 'go-templating renders for smoke'; then \
	  echo "PASS — harness renders via function-go-templating (offline)"; \
	else \
	  echo "FAIL — expected render output not found:"; echo "$$out"; exit 1; \
	fi
