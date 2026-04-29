# Monitoring Stack

Complete monitoring stack using Prometheus, Grafana, Loki, and custom dashboards.

## Prerequisites

- Kubernetes cluster with Helm 3 installed
- `kubectl` configured for your cluster

## 1. Add Helm Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## 2. Create Namespace

```bash
kubectl create namespace monitoring
```

## 3. Create Secrets

```bash
# Grafana admin credentials
kubectl create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='YOUR_PASSWORD' \
  -n monitoring

# Slack webhook for Alertmanager
kubectl create secret generic alertmanager-slack-webhook \
  --from-literal=slack-webhook-url='https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  -n monitoring
```

## 4. Deploy Prometheus Stack (includes Grafana, Alertmanager)

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  -f prometheus/prometheus-values.yaml \
  -n monitoring

# Apply alerting rules
kubectl apply -f prometheus/alerting-rules.yaml
```

## 5. Deploy Loki Stack

```bash
helm install loki grafana/loki-stack \
  -f loki/loki-values.yaml \
  -n monitoring
```

## 6. Import Grafana Dashboards

### Option A: ConfigMap (recommended for GitOps)

```bash
kubectl create configmap grafana-dashboards \
  --from-file=grafana/dashboards/ \
  -n monitoring

kubectl label configmap grafana-dashboards grafana_dashboard=1 -n monitoring
```

### Option B: Manual Import

1. Open Grafana UI
2. Go to Dashboards → Import
3. Upload each JSON file from `grafana/dashboards/`

## 7. Access Grafana

```bash
# Port forward
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

# Or get the LoadBalancer URL
kubectl get svc prometheus-grafana -n monitoring
```

Open http://localhost:3000 and log in with your admin credentials.

## Dashboards

| Dashboard | UID | Description |
|-----------|-----|-------------|
| DORA Metrics | `dora-metrics-dev` | Deployment frequency, lead time, change failure rate, MTTR |
| Security Overview | `security-overview` | CVEs, WAF blocks, auth failures, security events |
| Service Health | `service-health` | Request rates, error rates, latency percentiles, pod status |

## Alerting Rules

- **service-health**: HighErrorRate, HighLatency, PodCrashLooping, PodNotReady
- **security**: HighWAFBlocks, AuthFailureSpike, CriticalVulnerabilityFound
- **deployment**: DeploymentFailed, HighChangeFailureRate, SlowLeadTime

## Architecture

```
Prometheus  ──→  Grafana  ←──  Loki
    ↑                           ↑
scrape configs              Promtail
    ↑                           ↑
apps, jenkins,            pod logs
api-gateway
```
