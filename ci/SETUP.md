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

### Post-Install: Apply JCasC Configuration

JCasC auto-creates jobs, credentials, and shared library config on startup. To apply:

```bash
# Copy JCasC config
sudo mkdir -p /var/lib/jenkins/casc_configs
sudo cp ci/config/jenkins.yml /var/lib/jenkins/casc_configs/jenkins.yml

# Place kubeconfig for deployments
sudo mkdir -p /var/lib/jenkins/secrets
sudo cp <your-kubeconfig> /var/lib/jenkins/secrets/kubeconfig
sudo chown -R jenkins:jenkins /var/lib/jenkins/secrets
sudo chmod 600 /var/lib/jenkins/secrets/kubeconfig

# Set only the secret env vars (see ci/config/env.example)
# Option A: systemd EnvironmentFile
sudo tee /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yml"
Environment="JENKINS_ADMIN_PASSWORD=your-password"
Environment="OCIR_USERNAME=tenancy/user"
Environment="OCIR_PASSWORD=auth-token"
Environment="GIT_TOKEN=ghp_xxx"
Environment="SLACK_WEBHOOK_URL=https://hooks.slack.com/..."
Environment="TEAMS_WEBHOOK_URL=https://outlook.office.com/..."
Environment="SONAR_TOKEN=sqp_xxx"
EOF

# Restart to apply
sudo systemctl daemon-reload && sudo systemctl restart jenkins
```

Non-secret values (OCI region, OCIR URL, repo URLs, channels, thresholds, KUBECONFIG path) are hardcoded in jenkins.yml — no env vars needed for those.

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

All credentials are managed via JCasC (`ci/config/jenkins.yml`) and populated from environment variables. No manual UI setup needed.

| ID                    | Type              | Env Vars                             | Description                          |
|-----------------------|-------------------|--------------------------------------|--------------------------------------|
| `ocir-credentials`   | Username/Password | `OCIR_USERNAME`, `OCIR_PASSWORD`     | OCIR login (tenancy/user + auth token) |
| `git-credentials`    | Username/Password | `GIT_USERNAME`, `GIT_TOKEN`          | GitHub PAT for repo access & gitops  |
| `slack-webhook-url`  | Secret text       | `SLACK_WEBHOOK_URL`                  | Slack incoming webhook               |
| `teams-webhook-url`  | Secret text       | `TEAMS_WEBHOOK_URL`                  | MS Teams incoming webhook            |
| `sonar-token`        | Secret text       | `SONAR_TOKEN`                        | SonarQube analysis token (optional)  |

**Note:** Kubeconfig is NOT a Jenkins credential — it's a file at `/var/lib/jenkins/secrets/kubeconfig` exposed via the `KUBECONFIG` global env var.

### 3. Shared Library Setup

Go to: Manage Jenkins → System → Global Pipeline Libraries

```
Name:           diksha-dev-lib
Default version: shared-lib
Retrieval:      Modern SCM → Git Source
  Project Repo: https://github.com/tsprasath/ai-devops.git
  Credentials:  git-credentials
```

The shared library lives on the orphan branch `shared-lib` (vars/ and src/ at repo root).
No library path needed since the standard Jenkins layout is at root.

This makes `@Library('diksha-dev-lib') _` available in Jenkinsfiles.

### 4. Pipeline Jobs (via JCasC)

All jobs are auto-created by JCasC Job DSL in `ci/config/jenkins.yml`. No manual setup needed.

| Job Name                      | Type                | Description                                          |
|-------------------------------|---------------------|------------------------------------------------------|
| `service-build-auth-service`  | Pipeline            | Build auth-service, push to OCIR, update GitOps      |
| `ai-devops-pr`               | Multibranch Pipeline| PR validation — lint, test, scan (no deploy)         |
| `ai-devops-local`            | Pipeline            | Local/WSL dev pipeline — no K8s, no shared lib       |

#### Adding a New Service Job

Copy the `service-build-auth-service` block in `ci/config/jenkins.yml`, change the job name, default parameters (`APP_REPO_URL`, `SERVICE_NAME`), and apply JCasC.

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
├── config/
│   ├── jenkins.yml               # JCasC: jobs, credentials, shared lib, tools (secrets via ${VAR})
│   └── env.example               # Documents all required environment variables
├── setup-jenkins-ubuntu24.sh     # Automated full Jenkins setup (Ubuntu 24.04)
├── Jenkinsfile                   # Production (K8s agent, shared lib, full pipeline)
├── Jenkinsfile.full              # Full pipeline variant (build + deploy all stages)
├── Jenkinsfile.pr                # PR validation pipeline
├── Jenkinsfile.local             # Local WSL (agent any, self-contained, graceful skips)
├── pod-templates/build-pod.yaml  # Kubernetes pod template for Jenkins agents
├── templates/                    # Jenkinsfile.app-repo template for onboarding app repos
├── SETUP.md                      # This file
└── shared-lib/                  (on orphan branch 'shared-lib', not on main)
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
