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
