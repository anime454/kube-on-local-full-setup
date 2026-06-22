# mockup-app Kubernetes Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy mockup-app on a local kind cluster accessible at `http://mockup.app.local/mockup-app/v1` via Kong Ingress Controller backed by MetalLB.

**Architecture:** Kind's `extraPortMappings` maps `localhost:80` to Kong's NodePort 32080 on the kind node, enabling host access without needing the MetalLB IP (which is unreachable from macOS). MetalLB still assigns a LoadBalancer IP to Kong for in-cluster use. The Helm chart deploys the app with a ClusterIP service; Kong's Ingress routes `mockup.app.local/mockup-app/v1` to it.

**Tech Stack:** kind, kubectl, helm, docker, Kong Ingress Controller, MetalLB v0.14.9, Go/Fiber, Kubernetes 1.29+

## Global Constraints

- App listens on port `3000`; Service exposes port `80 → 3000`; Ingress backend uses port `80`
- Kong NodePort: `32080` (HTTP), `32443` (HTTPS)
- Kind extraPortMappings: `hostPort 80 → containerPort 32080`, `hostPort 443 → containerPort 32443`
- MetalLB IP range computed dynamically from the `kind` Docker network at deploy time
- App namespace: `mockup-app-dev`; Kong namespace: `kong`; cluster name: `local-cluster`
- No secrets/Infisical dependency for local dev
- No git repository in this project — skip all commit steps

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `mockup-app/Dockerfile` | Modify | Fix `EXPOSE 8080` → `EXPOSE 3000` |
| `helm/environments/values.local.yaml` | Modify | Rename `tag` → `image_tag` |
| `helm/templates/01.deployment.yaml` | Modify | Remove `envFrom` secretRef block |
| `helm/templates/02.ingress.yaml` | Modify | Fix backend port `8080` → `80` |
| `kind/cluster.config.yaml` | Replace | Proper kind cluster config with extraPortMappings |
| `metallb/ip-pool.config.yaml` | Replace | `${METALLB_RANGE}` placeholder + L2Advertisement |
| `kong/kong-ingress-value.yaml` | Replace | Correct proxy config with explicit nodePorts |
| `Makefile` | Create | Orchestrates full local stack setup |

---

## Task 1: Fix Helm Chart Bugs and Dockerfile

**Files:**
- Modify: `mockup-app/Dockerfile`
- Modify: `helm/environments/values.local.yaml`
- Modify: `helm/templates/01.deployment.yaml`
- Modify: `helm/templates/02.ingress.yaml`

**Interfaces:**
- Produces: A Helm chart that renders without errors and references the correct image tag, port, and no missing secrets

- [ ] **Step 1: Fix Dockerfile EXPOSE**

In `mockup-app/Dockerfile`, change line 40:
```dockerfile
# Before
EXPOSE 8080

# After
EXPOSE 3000
```

- [ ] **Step 2: Fix values image key**

In `helm/environments/values.local.yaml`, change line 3:
```yaml
# Before
tag: latest

# After
image_tag: latest
```

- [ ] **Step 3: Remove envFrom secretRef from Deployment**

In `helm/templates/01.deployment.yaml`, remove lines 61-64:
```yaml
# Remove this entire block:
          envFrom:
            - secretRef:
                name: {{ .Values.infisical_secret_name }}
```

The `env:` block above it stays. After removal, the container spec ends with `resources:`.

- [ ] **Step 4: Fix Ingress backend port**

In `helm/templates/02.ingress.yaml`, change line 20:
```yaml
# Before
                port:
                  number: 8080

# After
                port:
                  number: 80
```

- [ ] **Step 5: Verify Helm renders correctly**

Run:
```bash
helm template mockup-app ./helm -f ./helm/environments/values.local.yaml
```

Expected: YAML output with no errors. Verify in output:
- `image: mockup:latest` (not `mockup:` with no tag)
- No `envFrom` block appears
- Ingress backend port is `80`, not `8080`

```bash
helm template mockup-app ./helm -f ./helm/environments/values.local.yaml | grep -E "image:|number:|envFrom"
```

Expected output contains:
```
          image: mockup:latest
              number: 80
```

Expected output does NOT contain `envFrom`.

---

## Task 2: Update Infrastructure Configs

**Files:**
- Replace: `kind/cluster.config.yaml`
- Replace: `metallb/ip-pool.config.yaml`
- Replace: `kong/kong-ingress-value.yaml`

**Interfaces:**
- Produces: Config files consumed by `make cluster`, `make metallb`, and `make kong` targets

- [ ] **Step 1: Write kind cluster config**

Replace the entire contents of `kind/cluster.config.yaml`:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 32080
        hostPort: 80
        protocol: TCP
      - containerPort: 32443
        hostPort: 443
        protocol: TCP
```

- [ ] **Step 2: Write MetalLB config with placeholder**

Replace the entire contents of `metallb/ip-pool.config.yaml`:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2
  namespace: metallb-system
```

The `${METALLB_RANGE}` placeholder is substituted by the Makefile at deploy time using `sed`.

- [ ] **Step 3: Write Kong ingress values**

Replace the entire contents of `kong/kong-ingress-value.yaml`:
```yaml
proxy:
  type: LoadBalancer
  http:
    enabled: true
    servicePort: 80
    nodePort: 32080
  tls:
    enabled: true
    servicePort: 443
    nodePort: 32443

admin:
  enabled: true
  http:
    enabled: true
    servicePort: 8001

manager:
  enabled: true
  http:
    enabled: true
    servicePort: 8002
```

- [ ] **Step 4: Validate YAML syntax**

Run:
```bash
python3 -c "import yaml; yaml.safe_load_all(open('kind/cluster.config.yaml'))" && echo "kind: OK"
python3 -c "import yaml; yaml.safe_load_all(open('metallb/ip-pool.config.yaml').read().replace('\${METALLB_RANGE}', '172.18.255.200-172.18.255.250'))" && echo "metallb: OK"
python3 -c "import yaml; yaml.safe_load(open('kong/kong-ingress-value.yaml'))" && echo "kong: OK"
```

Expected:
```
kind: OK
metallb: OK
kong: OK
```

---

## Task 3: Create Makefile

**Files:**
- Create: `Makefile` (project root)

**Interfaces:**
- Consumes: `kind/cluster.config.yaml`, `metallb/ip-pool.config.yaml`, `kong/kong-ingress-value.yaml`, `kong/gateway.yaml`, `helm/`, `mockup-app/`
- Produces: `make all` that stands up the full stack end-to-end

- [ ] **Step 1: Create Makefile**

Create `/Users/localhost/projects/free-time/local-dev-setup/Makefile`:
```makefile
.PHONY: all cluster metallb kong build namespace deploy clean

CLUSTER_NAME   := local-cluster
APP_NAME       := mockup-app
APP_IMAGE      := mockup:latest
APP_NAMESPACE  := mockup-app-dev
KONG_NAMESPACE := kong
METALLB_VERSION := v0.14.9
GATEWAY_API_VERSION := v1.2.0

all: cluster metallb kong build namespace deploy
	@echo ""
	@echo "=========================================="
	@echo "  Setup complete!"
	@echo "  Add to /etc/hosts:"
	@echo "    127.0.0.1  mockup.app.local"
	@echo "  Then test:"
	@echo "    curl http://mockup.app.local/mockup-app/v1"
	@echo "=========================================="

cluster:
	kind create cluster --name $(CLUSTER_NAME) --config kind/cluster.config.yaml

metallb:
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/$(METALLB_VERSION)/config/manifests/metallb-native.yaml
	kubectl wait -n metallb-system --for=condition=ready pod -l app=metallb --timeout=120s
	@GATEWAY=$$(docker network inspect kind --format '{{(index .IPAM.Config 0).Gateway}}') && \
	BASE=$$(echo "$$GATEWAY" | cut -d. -f1,2) && \
	RANGE="$$BASE.255.200-$$BASE.255.250" && \
	sed 's|$${METALLB_RANGE}|'"$$RANGE"'|' metallb/ip-pool.config.yaml | kubectl apply -f -

kong:
	helm repo add kong https://charts.konghq.com 2>/dev/null || true
	helm repo update
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_VERSION)/standard-install.yaml
	helm upgrade --install kong kong/kong \
		-n $(KONG_NAMESPACE) \
		--create-namespace \
		-f kong/kong-ingress-value.yaml \
		--wait
	kubectl apply -f kong/gateway.yaml

build:
	docker build -t $(APP_IMAGE) ./mockup-app
	kind load docker-image $(APP_IMAGE) --name $(CLUSTER_NAME)

namespace:
	kubectl create namespace $(APP_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

deploy:
	helm upgrade --install $(APP_NAME) ./helm \
		-n $(APP_NAMESPACE) \
		-f helm/environments/values.local.yaml \
		--wait

clean:
	kind delete cluster --name $(CLUSTER_NAME)
```

- [ ] **Step 2: Verify Makefile syntax**

Run:
```bash
make --dry-run all 2>&1 | head -30
```

Expected: prints the sequence of commands without executing them, no syntax errors. You should see `kind create cluster`, `kubectl apply`, `helm upgrade`, etc. in order.

---

## Task 4: End-to-End Deployment Test

**Files:** None (verification only)

**Interfaces:**
- Consumes: all outputs from Tasks 1–3
- Produces: a running `mockup-app` pod accessible at `http://mockup.app.local/mockup-app/v1`

- [ ] **Step 1: Verify port 80 is free**

Run:
```bash
lsof -i :80 | grep LISTEN
```

Expected: no output. If something is listening on port 80, stop it before proceeding (kind's extraPortMappings will conflict).

- [ ] **Step 2: Run full setup**

Run (this takes 3-5 minutes):
```bash
make all
```

Expected: completes without error and prints the `/etc/hosts` reminder at the end.

- [ ] **Step 3: Add /etc/hosts entry**

```bash
echo "127.0.0.1  mockup.app.local" | sudo tee -a /etc/hosts
```

Verify:
```bash
grep mockup.app.local /etc/hosts
```

Expected: `127.0.0.1  mockup.app.local`

- [ ] **Step 4: Verify all pods are running**

```bash
kubectl get pods -n mockup-app-dev
kubectl get pods -n kong
```

Expected: all pods in `Running` state, no `CrashLoopBackOff` or `Pending`.

- [ ] **Step 5: Verify Kong LoadBalancer got an IP**

```bash
kubectl get svc -n kong kong-kong-proxy
```

Expected: `EXTERNAL-IP` column shows a `172.18.x.x` address (MetalLB assigned), not `<pending>`.

- [ ] **Step 6: Test the app endpoint**

```bash
curl -s http://mockup.app.local/mockup-app/v1
```

Expected:
```
Hello, World!
```

- [ ] **Step 7: Test the health endpoint**

```bash
curl -s http://mockup.app.local/mockup-app/v1/health
```

Expected:
```json
{"status":"ok"}
```

- [ ] **Step 8: Troubleshooting (run only if Steps 6-7 fail)**

Check Ingress was created and Kong picked it up:
```bash
kubectl get ingress -n mockup-app-dev
kubectl describe ingress mockup-app-ingress -n mockup-app-dev
```

Check app pod logs:
```bash
kubectl logs -n mockup-app-dev -l app=mockup-app --tail=50
```

Check Kong proxy logs:
```bash
kubectl logs -n kong -l app=kong --tail=50
```

Verify Kong can reach the service:
```bash
kubectl get svc -n mockup-app-dev
```

Expected: `mockup-app-service` with ClusterIP and port `80/TCP`.
