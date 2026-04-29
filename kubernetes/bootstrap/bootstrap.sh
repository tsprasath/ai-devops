#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
# ai-devops Cluster Bootstrap
# ═══════════════════════════════════════════════════════
# Usage:
#   ./bootstrap.sh <env>          # env = dev | staging | prod
#   ./bootstrap.sh dev --dry-run  # preview without applying
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - .env file at ci/config/.env with OCIR credentials
#   - kustomize CLI installed (or kubectl with kustomize support)
#
# What it does:
#   1. Creates namespaces per environment (diksha-app-{env}, etc.)
#   2. Creates OCIR docker-registry secrets in each namespace
#   3. Patches default ServiceAccount with imagePullSecrets
#   4. Deploys Stakater Reloader for secret rotation
#   5. Applies resource quotas, limit ranges, network policies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV="${1:?Usage: bootstrap.sh <dev|staging|prod> [--dry-run]}"
DRY_RUN="${2:-}"

# ── Validate environment ──
case "$ENV" in
  dev|staging|prod) ;;
  *) echo "ERROR: Invalid environment '$ENV'. Use: dev, staging, prod"; exit 1 ;;
esac

echo "══════════════════════════════════════════════════"
echo "  ai-devops Bootstrap — $ENV"
echo "══════════════════════════════════════════════════"

# ── Load .env for OCIR credentials ──
ENV_FILE="$REPO_ROOT/ci/config/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy from env.example and fill in values."
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

# Required vars
: "${OCIR_URL:?OCIR_URL not set in .env}"
: "${OCIR_USERNAME:?OCIR_USERNAME not set in .env}"
: "${OCIR_PASSWORD:?OCIR_PASSWORD not set in .env}"

# ── Namespaces for this environment ──
NAMESPACES=(
  "diksha-app-${ENV}"
  "diksha-monitoring-${ENV}"
  "diksha-networking-${ENV}"
  "diksha-infra-${ENV}"
  "jenkins"
)

# ── Step 1: Apply Kustomize overlay (creates namespaces, quotas, etc.) ──
echo ""
echo "[1/4] Applying Kustomize overlay for $ENV..."
OVERLAY_DIR="$SCRIPT_DIR/overlays/$ENV"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  kubectl apply -k "$OVERLAY_DIR" --dry-run=client
else
  kubectl apply -k "$OVERLAY_DIR"
fi

# ── Step 2: Create OCIR registry secret in each namespace ──
echo ""
echo "[2/4] Creating OCIR registry secrets..."

DOCKER_CONFIG_JSON=$(kubectl create secret docker-registry ocir-registry \
  --docker-server="$OCIR_URL" \
  --docker-username="$OCIR_USERNAME" \
  --docker-password="$OCIR_PASSWORD" \
  --dry-run=client -o jsonpath='{.data.\.dockerconfigjson}')

for NS in "${NAMESPACES[@]}"; do
  echo "  → $NS"
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "    (dry-run) would create ocir-registry secret"
  else
    kubectl create secret docker-registry ocir-registry \
      --docker-server="$OCIR_URL" \
      --docker-username="$OCIR_USERNAME" \
      --docker-password="$OCIR_PASSWORD" \
      -n "$NS" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
done

# ── Step 3: Patch default ServiceAccount in each namespace ──
echo ""
echo "[3/4] Patching default ServiceAccount with imagePullSecrets..."

for NS in "${NAMESPACES[@]}"; do
  echo "  → $NS"
  if [[ "$DRY_RUN" != "--dry-run" ]]; then
    kubectl patch serviceaccount default -n "$NS" \
      -p '{"imagePullSecrets": [{"name": "ocir-registry"}]}' \
      2>/dev/null || true
  fi
done

# ── Step 4: Deploy Reloader to infra namespace ──
echo ""
echo "[4/4] Deploying Stakater Reloader to diksha-infra-${ENV}..."

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo "  (dry-run) would deploy reloader"
else
  # Apply the reloader manifest with correct namespace
  kubectl apply -f "$SCRIPT_DIR/base/reloader.yaml" \
    --namespace="diksha-infra-${ENV}" 2>/dev/null || \
  echo "  Reloader already deployed or using Helm install"
fi

echo ""
echo "══════════════════════════════════════════════════"
echo "  Bootstrap complete for $ENV"
echo "══════════════════════════════════════════════════"
echo ""
echo "Namespaces created:"
for NS in "${NAMESPACES[@]}"; do
  echo "  ✓ $NS"
done
echo ""
echo "Next steps:"
echo "  1. Deploy Jenkins: helm install jenkins ... -n jenkins"
echo "  2. Apply JCasC:    kubectl create secret generic jenkins-casc-secrets \\"
echo "                        --from-env-file=ci/config/.env -n jenkins"
echo "  3. Deploy apps:    argocd app create ... or kubectl apply -k apps/overlays/$ENV"
