# Jenkins Setup Guide for DIKSHA DevOps Pipeline

## Quick Start (Automated)

The setup script handles everything — Java, Jenkins, Docker, Node.js, security tools, plugins, and admin user creation.

```bash
# Fresh install (Ubuntu 24.04)
sudo JENKINS_PORT=8081 JENKINS_ADMIN_USER=admin JENKINS_ADMIN_PASS=admin123 \
  bash ci/setup-jenkins-ubuntu24.sh
```

**What it installs:**
- Java 21 (Eclipse Temurin)
- Jenkins 2.555.x LTS (pinned, won't auto-upgrade)
- Docker Engine + jenkins user in docker group
- Node.js 20 LTS
- Trivy (container/filesystem vulnerability scanner)
- Helm 3 (K8s package manager)
- kubectl
- Gitleaks (secret detection)
- 33 Jenkins plugins (Pipeline, BlueOcean, K8s, Docker, JCasC, etc.)

**Environment variables (all optional, have defaults):**

| Variable              | Default      | Description                    |
|-----------------------|--------------|--------------------------------|
| `JENKINS_PORT`        | `8080`       | HTTP port                      |
| `JENKINS_ADMIN_USER`  | `admin`      | Admin username                 |
| `JENKINS_ADMIN_PASS`  | `admin123`   | Admin password                 |

After the script completes, open `http://localhost:<PORT>` and log in.

### Post-Install: Create Pipeline Job + Credentials

Use the Jenkins CLI to set up the pipeline job, shared library, and credentials without clicking through the UI:

```bash
# Download CLI jar
curl -sf -o /tmp/jenkins-cli.jar http://localhost:8081/jnlpJars/jenkins-cli.jar

# Run the setup groovy (creates shared lib + job + credentials)
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8081 \
  -auth admin:admin123 \
  groovy = < ci/setup-pipeline.groovy
```

Or manually — see sections 2-4 below.

### Trigger a Build

```bash
# CLI trigger (waits for completion, streams console)
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8081 \
  -auth admin:admin123 \
  build ai-devops -s -v
```

---

## Manual Setup Reference

### 1. Required Jenkins Plugins

The setup script installs all of these automatically. For manual install:
Manage Jenkins → Plugins → Available:

**Pipeline:** workflow-aggregator, pipeline-stage-view, pipeline-utility-steps, pipeline-graph-view
**SCM:** git, github, github-branch-source
**Build Tools:** nodejs, docker-workflow, docker-commons
**Kubernetes:** kubernetes, kubernetes-cli
**Credentials:** credentials-binding, ssh-credentials
**UI:** blueocean, ansicolor, timestamper, dark-theme
**Notifications:** mailer, slack
**Quality:** warnings-ng, junit, jacoco
**Admin:** configuration-as-code, job-dsl, matrix-auth, role-strategy, ws-cleanup, build-discarder, throttle-concurrents, locale, rebuild, parameterized-trigger

### 2. Credentials Setup

Go to: Manage Jenkins → Credentials → System → Global credentials

| ID                    | Type              | Description                          |
|-----------------------|-------------------|--------------------------------------|
| `ocir-credentials`   | Username/Password | OCIR login (tenancy/user + auth token) |
| `git-credentials`    | Username/Password | GitHub PAT (username + token)        |
| `teams-webhook-url`  | Secret text       | MS Teams/Slack webhook URL           |
| `ocir-repo`          | Secret text       | OCIR namespace/repo path             |
| `oci-region`         | Secret text       | e.g., `ap-mumbai-1`                 |
| `gitops-repo`        | Secret text       | GitOps repo URL (without https://)   |

### 3. Shared Library Setup

Go to: Manage Jenkins → System → Global Pipeline Libraries

```
Name:           diksha-dev-lib
Default version: shared-lib
Retrieval:      Modern SCM → Git
  Project Repo: https://github.com/tsprasath/ai-devops.git
```

The shared library lives on the orphan branch `shared-lib` (vars/ and src/ at repo root).
No library path needed since the standard Jenkins layout is at root.

This makes `@Library('diksha-dev-lib') _` available in Jenkinsfiles.

### 4. Pipeline Jobs

#### Production Job (OKE)
```
Job type:     Multibranch Pipeline
Name:         diksha-auth-service
Source:       GitHub → tsprasath/ai-devops
Script Path:  ci/Jenkinsfile
Branches:     main, develop, release/*
```

#### Local Dev Job (WSL)
```
Job type:     Pipeline
Name:         ai-devops
Source:       Pipeline script from SCM
SCM:          Git → https://github.com/tsprasath/ai-devops.git
Script Path:  ci/Jenkinsfile.local
Branch:       */main
Build triggers: Poll SCM (H/2 * * * *)
```

### 5. Kubernetes Cloud (for OKE)

Go to: Manage Jenkins → Clouds → New cloud → Kubernetes

```
Name:              oke-cluster
Kubernetes URL:    https://<OKE-API-endpoint>
K8s namespace:     jenkins
Jenkins URL:       http://jenkins:8080   (internal service URL)
Jenkins tunnel:    jenkins-agent:50000
Credentials:       kubeconfig or service account
```

---

## File Structure

```
ci/
├── setup-jenkins-ubuntu24.sh  # Automated full Jenkins setup (Ubuntu 24.04)
├── setup-pipeline.groovy      # CLI groovy: shared lib + job + credentials
├── Jenkinsfile                # Production (K8s agent, shared lib, full pipeline)
├── Jenkinsfile.local          # Local WSL (agent any, self-contained, graceful skips)
├── SETUP.md                   # This file
└── shared-lib/               (on orphan branch 'shared-lib', not on main)
    ├── src/org/dev/
    │   └── Constants.groovy   # OCI config, credential IDs, scan thresholds
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

## Pipeline Flow

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

## Troubleshooting

### Setup script GPG key error
If you see `NO_PUBKEY` warnings during Jenkins repo setup, the script handles this with a fallback. The installation still proceeds with cached packages.

### Auth failure after reinstall (401)
If Jenkins was previously installed, stale user directories can cause password mismatch. The setup script clears `/var/lib/jenkins/users/` before creating the admin user. If you hit this manually, delete the users directory and restart Jenkins.

### Plugin install hangs
Use batch install (single CLI call with all plugins) instead of installing one by one:
```bash
java -jar /tmp/jenkins-cli.jar -s http://localhost:8081 \
  -auth admin:admin123 \
  install-plugin plugin1 plugin2 plugin3 ... -deploy
```

### Build #1 shows "Gitleaks: 1 leak found"
This is non-blocking (exit code 0). The leak is `admin:admin123` in `push.sh` — a known test credential. Add a `.gitleaksignore` file to suppress known findings.
