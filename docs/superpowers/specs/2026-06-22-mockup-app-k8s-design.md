# mockup-app Kubernetes Deployment Design

**Date:** 2026-06-22
**Scope:** Deploy mockup-app on a local kind cluster with LoadBalancer (MetalLB) and Ingress (Kong)

---

## Prerequisites

The following tools must be installed on the macOS host:

| Tool | Purpose |
|------|---------|
| `kind` | Local Kubernetes cluster inside Docker |
| `kubectl` | Cluster management |
| `helm` | Package manager for Kubernetes |
| `docker` | Build and run containers |
| `make` | Run Makefile targets (pre-installed on macOS) |

---

## Goals

- Full local Kubernetes stack runnable from a single `make all`
- `curl http://mockup.app.local/mockup-app/v1` works from macOS host
- Kong Ingress Controller handles routing; MetalLB provides LoadBalancer concept
- Helm chart bugs fixed so the app actually starts

---

## Architecture

```
curl http://mockup.app.local/mockup-app/v1
  │
  ├── /etc/hosts: 127.0.0.1 → mockup.app.local  (manual one-time step)
  │
  ▼
localhost:80 (macOS host)
  │
  ├── kind extraPortMappings: hostPort 80 → containerPort 32080 on kind node
  │
  ▼
Kong proxy (NodePort 32080)
  │
  ▼
Kong Ingress Controller
  │
  ├── Ingress: host=mockup.app.local, path=/mockup-app/v1, strip-path=true
  │
  ▼
mockup-app-service (ClusterIP, port 80 → 3000)
  │
  ▼
mockup-app Pod (Go/Fiber, port 3000)
```

**Why NodePort + extraPortMappings instead of MetalLB IP directly:**
On macOS with Docker Desktop, the kind Docker bridge IPs (`172.18.x.x`) are not reachable from the host. Kind's `extraPortMappings` is the standard workaround — it maps `localhost:80` to a port on the kind node container. MetalLB is still installed and assigns a `172.18.x.x` IP to Kong's service (useful for in-cluster access and as a learning component), but host access routes through NodePort 32080.

---

## Components

### 1. Kind Cluster (`kind/cluster.config.yaml`)

Add a proper cluster config with `extraPortMappings` on the control-plane node:
- `hostPort: 80` → `containerPort: 32080`
- `hostPort: 443` → `containerPort: 32443`

### 2. MetalLB

- Installed via official manifest (`metallb-native.yaml`)
- IP pool range computed dynamically from the kind Docker network gateway at deploy time
- `L2Advertisement` resource required (MetalLB v0.13+)
- `metallb/ip-pool.config.yaml` updated to use `${METALLB_RANGE}` placeholder (substituted by Makefile via `sed` at deploy time)

### 3. Kong Ingress Controller (`kong/kong-ingress-value.yaml`)

Keep `type: LoadBalancer` (MetalLB assigns a `172.18.x.x` IP for in-cluster access), and explicitly set:
- `proxy.http.nodePort: 32080`
- `proxy.tls.nodePort: 32443`

Both paths work: macOS host uses NodePort 32080 via extraPortMappings; in-cluster traffic uses the MetalLB IP.

### 4. Helm Chart — Bug Fixes

| File | Bug | Fix |
|------|-----|-----|
| `helm/environments/values.local.yaml` | `tag: latest` — template expects `.Values.image_tag` | Rename key to `image_tag` |
| `helm/templates/02.ingress.yaml` | Backend port hardcoded to `8080`, Service listens on `80` | Change to `80` |
| `helm/templates/01.deployment.yaml` | `envFrom: secretRef: mockup-app-secret` — pod crashes without Infisical | Remove `envFrom` block |
| `mockup-app/Dockerfile` | `EXPOSE 8080` — app listens on `3000` | Change to `EXPOSE 3000` |

### 5. Makefile

Located at project root. Targets:

| Target | Action |
|--------|--------|
| `make all` | Runs: cluster → metallb → kong → build → namespace → deploy |
| `make cluster` | `kind create cluster --name local-cluster --config kind/cluster.config.yaml` |
| `make metallb` | Install MetalLB manifest, wait for ready, apply IP pool with computed range |
| `make kong` | `helm upgrade --install kong kong/kong -f kong/kong-ingress-value.yaml -n kong --create-namespace`, then apply `kong/gateway.yaml` |
| `make build` | `docker build -t mockup:latest ./mockup-app && kind load docker-image mockup:latest --name local-cluster` |
| `make namespace` | `kubectl create namespace mockup-app-dev --dry-run=client -o yaml \| kubectl apply -f -` |
| `make deploy` | `helm upgrade --install mockup-app ./helm -f ./helm/environments/values.local.yaml -n mockup-app-dev` |
| `make clean` | `kind delete cluster --name local-cluster` |

After `make all`, the Makefile prints:
```
Add to /etc/hosts:  127.0.0.1  mockup.app.local
Then test with:     curl http://mockup.app.local/mockup-app/v1
```

---

## Files Changed / Created

| File | Action |
|------|--------|
| `Makefile` | Create |
| `kind/cluster.config.yaml` | Replace with proper kind cluster config |
| `metallb/ip-pool.config.yaml` | Update addresses to use `${METALLB_RANGE}` placeholder + add L2Advertisement |
| `kong/kong-ingress-value.yaml` | Keep LoadBalancer, add explicit nodePorts 32080/32443 |
| `helm/environments/values.local.yaml` | Rename `tag` → `image_tag` |
| `helm/templates/01.deployment.yaml` | Remove `envFrom` block |
| `helm/templates/02.ingress.yaml` | Fix backend port `8080` → `80` |
| `mockup-app/Dockerfile` | Fix `EXPOSE 8080` → `EXPOSE 3000` |

---

## Out of Scope

- TLS / HTTPS
- Infisical / secrets management
- CI/CD pipeline
- Multi-node kind cluster
