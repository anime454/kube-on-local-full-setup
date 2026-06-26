# Infisical on Kubernetes

This directory integrates [Infisical](https://infisical.com/) with the local cluster using the **Infisical Secrets Operator**. Secrets defined in Infisical are synced into native Kubernetes `Secret` objects automatically.

---

## How it works

```
Infisical Server (self-hosted)
        │
        ▼
InfisicalConnection   ←  address of your Infisical instance
        │
        ▼
InfisicalAuth         ←  authenticates via Universal Auth (clientId + clientSecret)
        │
        ▼
InfisicalStaticSecret ←  fetches secrets from a project/environment and writes them
        │                 to a Kubernetes Secret
        ▼
  Secret: local-dev-api-secret (namespace: local-dev)
```

---

## Prerequisites

1. A running Infisical instance (self-hosted or cloud).
2. The **Infisical Secrets Operator** installed in the cluster:

```bash
helm repo add infisical-helm-charts https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/
helm repo update
helm upgrade --install infisical-operator infisical-helm-charts/secrets-operator \
  --create-namespace \
  -n infisical-operator-system
```

3. The `local-dev` namespace exists:

```bash
kubectl create namespace local-dev --dry-run=client -o yaml | kubectl apply -f -
```

---

## Step 1 — Create the auth secret

The operator needs your Infisical **Universal Auth** credentials. Create the Kubernetes Secret manually (never commit these values):

```bash
kubectl create secret generic infisical-auth \
  --namespace local-dev \
  --from-literal=clientId=<YOUR_CLIENT_ID> \
  --from-literal=clientSecret=<YOUR_CLIENT_SECRET>
```

Get these values from **Infisical → Project → Access Control → Machine Identities → Universal Auth**.

---

## Step 2 — Apply the operator resources

```bash
kubectl apply -f infisical/connect.yaml
kubectl apply -f infisical/auth.yaml
kubectl apply -f infisical/static-secert.yaml
```

Or apply all at once:

```bash
kubectl apply -f infisical/
```

---

## Resource breakdown

### `connect.yaml` — InfisicalConnection

Points the operator to your Infisical server.

```yaml
spec:
  address: http://192.168.64.52:9991   # Change to your Infisical instance URL
```

Update `address` to match your local or hosted Infisical URL.

---

### `auth.yaml` — InfisicalAuth

Tells the operator which auth method to use and where the credentials live.

```yaml
spec:
  method: universal
  universal:
    clientIdRef:
      name: infisical-auth      # Secret created in Step 1
      key: clientId
    clientSecretRef:
      name: infisical-auth
      key: clientSecret
```

---

### `static-secert.yaml` — InfisicalStaticSecret

Defines which Infisical secrets to sync and where to write them in the cluster.

```yaml
spec:
  sources:
    - projectId: 4445aabc-7c2c-4319-868a-36d2610450f6   # Infisical project ID
      environmentSlug: dev                               # dev / staging / prod
      secretPath: "/"                                    # path inside the project

  syncOptions:
    refreshInterval: 60s    # how often the operator re-syncs
    instantUpdates: false

  targets:
    - name: local-dev-api-secret    # the Kubernetes Secret that will be created/updated
      namespace: local-dev
      kind: Secret
      creationPolicy: Owner         # operator owns and cleans up this secret
```

Change `projectId`, `environmentSlug`, and `secretPath` to match your Infisical project.

---

## Verify the sync

```bash
# Check operator reconciled without errors
kubectl get infisicalstaticsecret -n local-dev

# Confirm the managed secret was created
kubectl get secret local-dev-api-secret -n local-dev

# Inspect the synced keys (values are base64-encoded)
kubectl get secret local-dev-api-secret -n local-dev -o jsonpath='{.data}' | jq 'keys'
```

---

## Using the secret in a deployment

Reference the managed secret in your pod spec via `envFrom` or individual `env` entries:

```yaml
envFrom:
  - secretRef:
      name: local-dev-api-secret
```

or per-key:

```yaml
env:
  - name: MY_API_KEY
    valueFrom:
      secretKeyRef:
        name: local-dev-api-secret
        key: MY_API_KEY
```

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Secret not created | `kubectl describe infisicalstaticsecret my-static-secret -n local-dev` |
| Auth failure | Verify `clientId` / `clientSecret` in the `infisical-auth` secret are correct |
| Connection refused | Confirm Infisical is reachable from inside the cluster at the address in `connect.yaml` |
| Operator not running | `kubectl get pods -n infisical-operator-system` |
