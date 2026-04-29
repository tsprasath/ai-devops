# ai-devops

DevOps platform repository for the Diksha project. Contains CI pipelines, Helm charts, ArgoCD applications, Kubernetes bootstrap manifests, Terraform modules, and monitoring configs.

**This is NOT application source code.** Application repos (e.g., [sample-test-app](https://github.com/tsprasath/sample-test-app)) contain source + Dockerfile. This repo owns the deployment infrastructure and GitOps state.

## Architecture — Split-Repo GitOps Flow

```
  ┌──────────────┐       ┌──────────────────┐       ┌──────────────────┐       ┌─────────────┐
  │  App Repo    │ push  │  Jenkins          │  push │  DevOps Repo     │ sync  │  OKE        │
  │ (source +   ├──────►│  Build & Push     ├──────►│  (ai-devops)     ├──────►│  Cluster    │
  │  Dockerfile) │       │  to OCIR          │       │  values-{env}    │       │  via ArgoCD │
  └──────────────┘       └──────────────────┘       └──────────────────┘       └─────────────┘
                                │                            ▲
                                │  Trivy scan, tests         │  ArgoCD watches
                                │  shared-lib steps          │  for tag changes
                                ▼                            │
                         ┌──────────────┐             ┌──────┴───────┐
                         │ OCIR         │             │ ArgoCD       │
                         │ bom.ocir.io  │             │ ApplicationSet│
                         └──────────────┘             └──────────────┘

  Bootstrap (one-time per env):
  ┌─────────────────────┐
  │ kubernetes/bootstrap/    │──► Namespaces, OCIR Secrets, ResourceQuotas, Stakater Reloader
  │ Kustomize overlays  │    diksha-app-{env}, diksha-monitoring-{env}, diksha-infra-{env}
  └─────────────────────┘
```

## Directory Structure

```
ci/
  config/jenkins.yml       JCasC config (env var interpolation, zero hardcoded secrets)
  config/env.example       Environment variables template
  Jenkinsfile              Main CI/CD pipeline
  Jenkinsfile.full         Full pipeline variant (build + deploy all stages)
  Jenkinsfile.pr           PR validation pipeline
  Jenkinsfile.local        WSL local development pipeline
  setup-jenkins-ubuntu24.sh  Jenkins installation script
  pod-templates/build-pod.yaml  Kubernetes pod template for Jenkins agents
  templates/               Jenkinsfile.app-repo template for onboarding app repos

  NOTE: Shared library (vars/, src/) lives on the orphan branch 'shared-lib' in this repo.
        Jenkins loads it via @Library('diksha-dev-lib') pointing to branch 'shared-lib'.

kubernetes/
  helm-charts/             Per-service Helm charts with per-env values
    <service>/
      Chart.yaml
      values-dev.yaml
      values-staging.yaml
      values-prod.yaml
  argocd-apps/             ArgoCD Application manifests + ApplicationSet (auto-discovers from helm-charts/)
  bootstrap/               Kustomize overlays per env — namespaces, OCIR secrets, quotas, Reloader
    base/
    overlays/dev/
    overlays/staging/
    overlays/prod/
  terraform/               OCI infra modules (VCN, OKE, OCIR, API Gateway, WAF, Vault)
  monitoring/              Prometheus, Grafana, Loki configs

security/                  OPA policies, scan configs
docs/                      Architecture documentation
```

## Prerequisites

- OCI CLI configured with appropriate tenancy access
- kubectl connected to the OKE cluster
- Helm 3.x
- Kustomize
- Terraform >= 1.0
- Jenkins with the JCasC plugin
- ArgoCD installed on the cluster

## Quick Start

### 1. Bootstrap a New Environment

```bash
# Apply namespaces, secrets, quotas, Reloader
kubectl apply -k kubernetes/bootstrap/overlays/dev/
```

### 2. Deploy ArgoCD ApplicationSet

```bash
kubectl apply -f kubernetes/argocd-apps/appset-services.yaml
```

ArgoCD auto-discovers every service under `kubernetes/helm-charts/` and creates Application resources per environment.

### 3. Configure Jenkins

Copy `ci/config/env.example` to your Jenkins environment, fill in values (OCIR credentials, OKE kubeconfig, GitHub tokens). Jenkins loads `ci/config/jenkins.yml` via JCasC — all secrets are injected via environment variables, nothing hardcoded.

## How to Add a New Service (4 Steps)

1. **Create Helm chart**: Add `kubernetes/helm-charts/<service-name>/` with `Chart.yaml`, `templates/`, and `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`
2. **Add Jenkinsfile to app repo**: Copy `ci/templates/Jenkinsfile.app-repo` into the app repo root, set the service name parameter
3. **Create Jenkins job**: Add a parameterized pipeline job pointing to the app repo (one pipeline per service)
4. **Push**: ArgoCD ApplicationSet auto-detects the new chart directory and creates the deployment

## Pipeline Flow

```
Developer pushes to app repo
  └─► Jenkins webhook triggers build
       ├─► buildAndPush  — Docker build, push to bom.ocir.io
       ├─► trivyScan     — Image vulnerability scan
       └─► gitopsUpdate  — Updates image tag in ai-devops values-{env}.yaml
            └─► ArgoCD detects change, syncs to OKE cluster
```

## Environment Promotion

| Environment | Trigger                    | Namespace Pattern       |
|-------------|----------------------------|-------------------------|
| dev         | Auto on push to develop    | diksha-app-dev          |
| staging     | Auto on merge to main      | diksha-app-staging      |
| prod        | Manual approval + promote  | diksha-app-prod         |

Promotion to prod uses the `promoteToProd` shared-lib step which copies the staging image tag to `values-prod.yaml` and requires manual approval in Jenkins.

## Stack

- **Runtime**: Node.js 20, Docker
- **Orchestration**: OKE (Oracle Kubernetes Engine)
- **CI**: Jenkins + JCasC + Shared Library (orphan branch `shared-lib`)
- **CD**: ArgoCD + ApplicationSet
- **Registry**: OCIR (bom.ocir.io)
- **IaC**: Terraform (OCI provider)
- **Monitoring**: Prometheus, Grafana, Loki
- **Security**: Trivy, OPA, OCI WAF, OCI Vault

## Namespaces

- `diksha-app-{env}` — Application workloads
- `diksha-monitoring-{env}` — Prometheus, Grafana, Loki
- `diksha-networking-{env}` — Ingress, API Gateway configs
- `diksha-infra-{env}` — Infrastructure services
- `jenkins` — CI server

## Links

- **DevOps Repo**: [tsprasath/ai-devops](https://github.com/tsprasath/ai-devops)
- **Sample App Repo**: [tsprasath/sample-test-app](https://github.com/tsprasath/sample-test-app)
- **Architecture**: [docs/architecture.md](docs/architecture.md)
