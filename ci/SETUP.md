# Jenkins Setup Guide for DIKSHA DevOps Pipeline

## 1. Required Jenkins Plugins

Install via Manage Jenkins → Plugins → Available:

```
- Pipeline
- Pipeline: Stage View
- Git
- GitHub
- Kubernetes (for OKE agent)
- Docker Pipeline
- AnsiColor
- Timestamps
- HTML Publisher
- JUnit
- Credentials Binding
- Pipeline Utility Steps
```

## 2. Credentials Setup

Go to: Manage Jenkins → Credentials → System → Global credentials

| ID                    | Type              | Description                          |
|-----------------------|-------------------|--------------------------------------|
| `ocir-credentials`   | Username/Password | OCIR login (tenancy/user + auth token) |
| `git-credentials`    | Username/Password | GitHub PAT (username + token)        |
| `teams-webhook-url`  | Secret text       | MS Teams/Slack webhook URL           |
| `ocir-repo`          | Secret text       | OCIR namespace/repo path             |
| `oci-region`         | Secret text       | e.g., `ap-mumbai-1`                 |
| `gitops-repo`        | Secret text       | GitOps repo URL (without https://)   |

## 3. Shared Library Setup

Go to: Manage Jenkins → System → Global Pipeline Libraries

```
Name:           diksha-dev-lib
Default version: main
Retrieval:      Modern SCM → Git
  Project Repo: https://github.com/tsprasath/ai-devops.git
  Library Path: ci/shared-lib
```

This makes `@Library('diksha-dev-lib') _` available in Jenkinsfiles.

## 4. Pipeline Jobs

### Production Job (OKE)
```
Job type:     Multibranch Pipeline
Name:         diksha-auth-service
Source:       GitHub → tsprasath/ai-devops
Script Path:  ci/Jenkinsfile
Branches:     main, develop, release/*
```

### Local Dev Job (WSL)
```
Job type:     Pipeline
Name:         ai-devops
Source:       Pipeline script from SCM
SCM:          Git → https://github.com/tsprasath/ai-devops.git
Script Path:  ci/Jenkinsfile.local
Branch:       */main
Build triggers: Poll SCM (H/2 * * * *)
```

## 5. Kubernetes Cloud (for OKE)

Go to: Manage Jenkins → Clouds → New cloud → Kubernetes

```
Name:              oke-cluster
Kubernetes URL:    https://<OKE-API-endpoint>
K8s namespace:     jenkins
Jenkins URL:       http://jenkins:8080   (internal service URL)
Jenkins tunnel:    jenkins-agent:50000
Credentials:       kubeconfig or service account
```

## 6. Tool Installations

### WSL (local dev)
Already installed:
- Node.js 20 (via nvm or apt)
- Docker 28.x
- Trivy 0.70.x
- Gitleaks
- Helm (optional)

### OKE (pod containers)
All tools come from container images in the pod template — no installation needed.

## 7. File Structure

```
ci/
├── Jenkinsfile              # Production (K8s agent, shared lib, full pipeline)
├── Jenkinsfile.local        # Local WSL (agent any, self-contained, graceful skips)
└── shared-lib/
    ├── src/org/dev/
    │   └── Constants.groovy # OCI config, credential IDs, scan thresholds
    └── vars/
        ├── buildAndPush.groovy
        ├── codeQualityScan.groovy
        ├── dockerBuild.groovy
        ├── gitleaksScan.groovy
        ├── gitopsUpdate.groovy
        ├── helmLint.groovy
        ├── notifyTeam.groovy
        ├── promoteToProd.groovy
        ├── rollback.groovy
        ├── securityScan.groovy
        └── trivyScan.groovy
```

## 8. Pipeline Flow

```
Jenkinsfile (Production)          Jenkinsfile.local (WSL)
========================          =======================
Checkout                          Checkout
  ↓                                 ↓
Code Quality (shared lib)         Install Dependencies
  ↓                                 ↓
Unit Tests + Coverage             Code Quality (ESLint + Audit)
  ↓                                 ↓
Docker Build (shared lib)         Unit Tests + Coverage
  ↓                                 ↓
Security: Trivy + Gitleaks        Docker Build
  ↓                                 ↓
Helm Validate                     Security: Trivy + Gitleaks
  ↓                                 ↓
Push to OCIR (main/develop)       Helm Validate
  ↓                                 ↓
GitOps Update (main only)         Smoke Test (docker run + curl)
  ↓                                 ↓
Smoke Test (live endpoint)        Cleanup
  ↓
Promote to Staging (manual)
  ↓
Notify Team
```
