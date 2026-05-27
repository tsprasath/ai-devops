#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
# ai-devops Cluster Bootstrap
# ═══════════════════════════════════════════════════════
# Usage:
#   ./bootstrap.sh <env>                   # env = dev | staging | prod
#   ./bootstrap.sh dev --dry-run           # preview without applying
#   ./bootstrap.sh dev --registry ghcr     # use GitHub Container Registry
#   ./bootstrap.sh dev --registry ocir     # use OCI Registry (default)
#
# Prerequisites:
#   - kubectl configured for the target cluster (minikube or OKE)
#   - .env file at ci/config/.env with registry credentials
#   - kustomize CLI installed (or kubectl with kustomize support)
#   - helm CLI installed
#
# What it does:
#   1. Creates namespaces per environment
#   2. Creates docker-registry pull secrets in each namespace
#   3. Patches default ServiceAccount with imagePullSecrets
#   4. Deploys Stakater Reloader via Helm
#   5. Applies resource quotas, limit ranges, network policies
#   6. Installs ArgoCD (if --install-argocd flag passed)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV="${1:?Usage: bootstrap.sh <dev|staging|prod> [--dry-run] [--registry ghcr|ocir] [--install-argocd]}"
DRY_RUN=""
REGISTRY_TYPE="ghcr"   # default to ghcr for minikube/test
INSTALL_ARGOCD=false

# Parse flags
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true" ;;
    --registry) REGISTRY_TYPE="${2:?--registry requires ghcr or ocir}"; shift ;;
    --install-argocd) INSTALL_ARGOCD=true ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
  shift
done

# ── Validate environment ──
case "$ENV" in
  dev|staging|prod) ;;
  *) echo "ERROR: Invalid environment '$ENV'. Use: dev, staging, prod"; exit 1 ;;
esac

echo "══════════════════════════════════════════════════"
echo "  ai-devops Bootstrap — $ENV  (registry: $REGISTRY_TYPE)"
echo "══════════════════════════════════════════════════"

# ── Load .env for credentials ──
ENV_FILE="$REPO_ROOT/ci/config/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy from env.example and fill in values."
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

# ── Namespaces for this environment ──
NAMESPACES=(
  "diksha-app-${ENV}"
  "diksha-monitoring-${ENV}"
  "diksha-infra-${ENV}"
  "argocd"
  "jenkins"
)

# ── Registry config ──
if [[ "$REGISTRY_TYPE" == "ghcr" ]]; then
  : "${GHCR_USERNAME:?GHCR_USERNAME not set in .env}"
  : "${GHCR_TOKEN:?GHCR_TOKEN not set in .env}"
  REGISTRY_URL="ghcr.io"
  REGISTRY_USER="$GHCR_USERNAME"
  REGISTRY_PASS="$GHCR_TOKEN"
  SECRET_NAME="ghcr-registry"
else
  : "${OCIR_URL:?OCIR_URL not set in .env}"
  : "${OCIR_USERNAME:?OCIR_USERNAME not set in .env}"
  : "${OCIR_PASSWORD:?OCIR_PASSWORD not set in .env}"
  REGISTRY_URL="$OCIR_URL"
  REGISTRY_USER="$OCIR_USERNAME"
  REGISTRY_PASS="$OCIR_PASSWORD"
  SECRET_NAME="ocir-registry"
fi

echo ""
echo "Registry:   $REGISTRY_URL"
echo "Secret name: $SECRET_NAME"

# ── Step 1: Apply Kustomize overlay ──
echo ""
echo "[1/5] Applying Kustomize overlay for $ENV..."
OVERLAY_DIR="$SCRIPT_DIR/overlays/$ENV"

if [[ "$DRY_RUN" == "true" ]]; then
  kubectl apply -k "$OVERLAY_DIR" --dry-run=client
else
  kubectl apply -k "$OVERLAY_DIR"
fi

# ── Step 2: Create registry secret in each namespace ──
echo ""
echo "[2/5] Creating ${REGISTRY_TYPE} registry secrets..."

for NS in "${NAMESPACES[@]}"; do
  echo "  → $NS"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "    (dry-run) would create $SECRET_NAME secret"
  else
    # Ensure namespace exists first
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

    kubectl create secret docker-registry "$SECRET_NAME" \
      --docker-server="$REGISTRY_URL" \
      --docker-username="$REGISTRY_USER" \
      --docker-password="$REGISTRY_PASS" \
      -n "$NS" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
done

# ── Step 3: Patch default ServiceAccount ──
echo ""
echo "[3/5] Patching default ServiceAccount with imagePullSecrets..."

for NS in "${NAMESPACES[@]}"; do
  echo "  → $NS"
  if [[ "$DRY_RUN" != "true" ]]; then
    kubectl patch serviceaccount default -n "$NS" \
      -p "{\"imagePullSecrets\": [{\"name\": \"${SECRET_NAME}\"}]}" \
      2>/dev/null || true
  fi
done

# ── Step 4: Deploy Stakater Reloader via Helm ──
echo ""
echo "[4/5] Deploying Stakater Reloader to diksha-infra-${ENV}..."

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  (dry-run) would install reloader via helm"
else
  helm repo add stakater https://stakater.github.io/stakater-charts 2>/dev/null || true
  helm repo update stakater

  helm upgrade --install reloader stakater/reloader \
    --namespace "diksha-infra-${ENV}" \
    --create-namespace \
    --set reloader.watchGlobally=true \
    --set reloader.logFormat=json \
    --wait --timeout 120s

  echo "  ✓ Reloader deployed"
fi

# ── Step 5: Install ArgoCD (optional) ──
if [[ "$INSTALL_ARGOCD" == "true" ]]; then
  echo ""
  echo "[5/5] Installing ArgoCD..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  (dry-run) would install argocd"
  else
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "  Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

    # Patch service to NodePort for minikube access
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

    echo "  ✓ ArgoCD installed"
    echo "  Get admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo "  Access UI: minikube service argocd-server -n argocd"
  fi
else
  echo ""
  echo "[5/5] ArgoCD install skipped (pass --install-argocd to enable)"
fi

echo ""
echo "══════════════════════════════════════════════════"
echo "  Bootstrap complete for $ENV"
echo "══════════════════════════════════════════════════"
echo ""
echo "Namespaces:"
for NS in "${NAMESPACES[@]}"; do
  echo "  ✓ $NS"
done
echo ""
echo "Next steps:"
echo "  1. Fill secrets: cp inventory/env/dev/secrets.yaml inventory/env/dev/secrets.local.yaml"
echo "                   (edit secrets.local.yaml with real values)"
echo "  2. Apply secrets: kubectl apply -f inventory/env/dev/secrets.local.yaml"
echo "  3. Apply ArgoCD appset: kubectl apply -f kubernetes/argocd-apps/appset-minikube.yaml"
echo "  4. Access ArgoCD: minikube service argocd-server -n argocd"
echo "  5. Build app image: cd ../sample-app && docker build -t ghcr.io/tsprasath/diksha/sample-app:latest ."
echo "                      docker push ghcr.io/tsprasath/diksha/sample-app:latest"
