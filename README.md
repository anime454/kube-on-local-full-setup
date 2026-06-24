# kube-local-full-setup

A fully local Kubernetes dev environment using kind, MetalLB, and Kong Gateway — with a Go mockup app deployed via Helm. One command stands up the entire stack on your machine with no cloud required.

---

## What's inside

| Component | Role |
|-----------|------|
| [kind](https://kind.sigs.k8s.io/) | Runs a Kubernetes cluster inside Docker |
| [MetalLB](https://metallb.universe.tf/) | Provides a LoadBalancer IP so Kong gets a real address |
| [Kong Gateway](https://konghq.com/) | API gateway that routes external HTTP traffic into the cluster |
| [mockup-app](./mockup-app) | Tiny Go HTTP server (Fiber) used to verify the full path works |
| [Helm](https://helm.sh/) | Packages and deploys the mockup app into the cluster |

---

## Architecture

```
curl http://mockup.app.local/mockup-app/v1
        │
        ▼
  /etc/hosts → 127.0.0.1
        │
        ▼
  kind node (port 80 → NodePort 32080)
        │
        ▼
  Kong proxy (LoadBalancer)
        │
        ▼
  Kong Ingress (strips /mockup-app/v1 prefix)
        │
        ▼
  mockup-app Service → Pod (port 3000)
```

---

## Prerequisites

Install the following tools before you begin:

```bash
# Docker Desktop — https://www.docker.com/products/docker-desktop
# (install manually; no brew formula for Docker Desktop)

# kind — Kubernetes in Docker
brew install kind

# kubectl — Kubernetes CLI
brew install kubectl

# Helm — Kubernetes package manager
brew install helm

# Go — needed to build the mockup app image
brew install go
```

> Docker Desktop must be running before you execute any `make` command.

---

## Quick Start

```bash
make all
```

This single command runs every step end-to-end (see [Make targets](#make-targets) below for what each step does).

When it finishes, add this line to `/etc/hosts`:

```
127.0.0.1  mockup.app.local
```

Then verify the stack is working:

```bash
curl http://mockup.app.local/mockup-app/v1
# Hello, World!
```

---

## Make targets

| Target | What it does |
|--------|-------------|
| `make all` | Runs every target below in order — full setup from scratch |
| `make cluster` | Creates the kind cluster (`local-cluster`) with port mappings for 80 and 443 |
| `make metallb` | Installs MetalLB and assigns an IP pool based on the kind node's Docker network |
| `make kong` | Installs Kong via Helm and applies the Gateway API resources |
| `make build` | Builds the mockup-app Docker image and loads it into the kind cluster |
| `make namespace` | Creates the `mockup-app-dev` namespace (idempotent) |
| `make deploy` | Deploys the mockup-app Helm chart into `mockup-app-dev` |
| `make clean` | Deletes the kind cluster only |
| `make clean-all` | Deletes the cluster, uninstalls Helm releases, removes namespaces and the Docker image |

---

## Project structure

```
.
├── Makefile               # Orchestrates the full setup
├── kind/
│   └── cluster.config.yaml   # kind cluster definition (port mappings, node labels)
├── metallb/
│   └── ip-pool.config.yaml   # MetalLB IP pool config (range filled in at runtime)
├── kong/
│   ├── kong-ingress-value.yaml  # Helm values for Kong (proxy ports, admin, manager)
│   └── gateway.yaml             # Gateway API Gateway resource
├── helm/
│   ├── Chart.yaml            # Helm chart metadata
│   ├── environments/
│   │   └── values.local.yaml # Local dev values (image, ingress host, resources)
│   └── templates/            # Kubernetes manifests (Deployment, Service, Ingress, HPA, SA)
└── mockup-app/
    ├── main.go               # Go HTTP server with / and /health endpoints
    └── Dockerfile            # Multi-stage build → minimal runtime image
```

---

## Testing it works

After `make all` and the `/etc/hosts` entry:

```bash
# Main endpoint
curl http://mockup.app.local/mockup-app/v1
# Hello, World!

# Health check (direct pod port-forward)
kubectl port-forward -n mockup-app-dev svc/mockup-app-service 3000:80
curl http://localhost:3000/health
# {"status":"ok"}
```

---

## Tear down

```bash
# Remove just the cluster (fastest — leaves Helm repos intact)
make clean

# Remove everything: cluster, namespaces, Helm releases, Docker image
make clean-all
```

To rebuild from scratch after a clean:

```bash
make all
```
