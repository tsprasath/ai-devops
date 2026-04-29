# Architecture Overview

## Split-Repo GitOps Flow

```
  ┌──────────────┐       ┌───────────────────────┐       ┌──────────────────┐       ┌─────────────┐
  │  App Repo    │ push  │  Jenkins               │  git  │  DevOps Repo     │ sync  │  OKE        │
  │ (source +   ├──────►│  1. Build Docker image  ├──────►│  (ai-devops)     ├──────►│  Cluster    │
  │  Dockerfile) │       │  2. Push to OCIR        │       │  update image    │       │             │
  └──────────────┘       │  3. Trivy scan          │       │  tag in          │       │  ArgoCD     │
                         │  4. gitopsUpdate()      │       │  values-{env}    │       │  deploys    │
                         └───────────────────────┘       └──────────────────┘       └─────────────┘

  Bootstrap (applied once per environment):
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  kubernetes/bootstrap/overlays/{dev,staging,prod}/                          │
  │  ┌────────────┐  ┌───────────────┐  ┌────────────┐  ┌──────────────┐  │
  │  │ Namespaces │  │ OCIR Registry │  │ Resource   │  │ Stakater     │  │
  │  │            │  │ Secrets       │  │ Quotas     │  │ Reloader     │  │
  │  └────────────┘  └───────────────┘  └────────────┘  └──────────────┘  │
  └─────────────────────────────────────────────────────────────────────────┘

  ArgoCD ApplicationSet auto-discovers services from kubernetes/helm-charts/:
  ┌──────────────────────────────────────────────┐
  │  kubernetes/helm-charts/                          │
  │    auth-service/  →  ArgoCD App (per env)    │
  │    api-service/   →  ArgoCD App (per env)    │
  │    ...            →  ArgoCD App (per env)    │
  └──────────────────────────────────────────────┘
```

## System Design

```
                    ┌─────────────┐
                    │   DNS/LB    │
                    │  (OCI LB)   │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ OCI WAF     │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ API Gateway │
                    │   (OCI)     │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──┐  ┌─────▼────┐  ┌───▼──────┐
       │  Auth   │  │   API    │  │ Frontend │
       │ Service │  │ Service  │  │  (CDN)   │
       │ (Node)  │  │ (TBD)   │  │          │
       └────┬────┘  └────┬────┘  └──────────┘
            │             │
       ┌────▼─────────────▼────┐
       │    Database Layer     │
       │  (OCI MySQL/Auto DB)  │
       └───────────────────────┘
```

## Environments

| Environment | Trigger                        | Namespaces                                          | Promotion        |
|-------------|--------------------------------|-----------------------------------------------------|------------------|
| **dev**     | Auto on push to develop branch | diksha-app-dev, diksha-monitoring-dev, etc.          | Automatic        |
| **staging** | Auto on merge to main          | diksha-app-staging, diksha-monitoring-staging, etc.  | Automatic        |
| **prod**    | Manual approval in Jenkins     | diksha-app-prod, diksha-monitoring-prod, etc.        | promoteToProd()  |

Bootstrap per environment: `kubectl apply -k kubernetes/bootstrap/overlays/{env}/`

Each environment gets isolated namespaces, resource quotas, and OCIR pull secrets via Kustomize overlays.

## Security Layers

1. **OCI WAF** — DDoS, SQL injection, XSS protection
2. **API Gateway** — JWT validation, rate limiting, CORS
3. **Network Policies** — Service-to-service isolation
4. **Pod Security** — Non-root, read-only FS, no privilege escalation
5. **Image Scanning** — Trivy on every build
6. **Secret Management** — OCI Vault + External Secrets Operator
7. **OPA Policies** — Admission control (security/ directory)

## Infrastructure as Code

Terraform modules in `kubernetes/terraform/`:
- **VCN** — Virtual Cloud Network with public/private subnets
- **OKE** — Oracle Kubernetes Engine cluster
- **OCIR** — Container registry configuration
- **API Gateway** — OCI API Gateway deployment
- **WAF** — Web Application Firewall rules
- **Vault** — OCI Vault for secret management
