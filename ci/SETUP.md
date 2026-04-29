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

# Set the JCasC config path and secret env vars
# Option A: EnvironmentFile (recommended for systemd-managed Jenkins)
sudo cp ci/config/env.example /var/lib/jenkins/secrets/.env
sudo vi /var/lib/jenkins/secrets/.env  # fill in real values
sudo chown jenkins:jenkins /var/lib/jenkins/secrets/.env
sudo chmod 600 /var/lib/jenkins/secrets/.env

sudo mkdir -p /etc/systemd/system/jenkins.service.d
sudo tee /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yml"
EnvironmentFile=/var/lib/jenkins/secrets/.env
EOF

# Restart to apply
sudo systemctl daemon-reload && sudo systemctl restart jenkins

# Option B: Kubernetes Secret (recommended for OKE/container deployments)
# Create a K8s Secret with the env vars from env.example, mount as env in the
# Jenkins pod spec. JCasC picks them up automatically — no systemd needed.
# See: kubernetes/helm-charts/ for Helm-based Jenkins deployment.
```

Non-secret values (OCI region, OCIR URL, repo URLs, Slack channels, Trivy thresholds, KUBECONFIG path) are hardcoded directly in `jenkins.yml` — no env vars needed for those.

Verify JCasC applied: http://localhost:8081/configuration-as-code/

### Trigger a Build

```bash
# CLI trigger (waits for completion, streams console)
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8081 \
  -auth admin:<password> \
  build service-build-auth-service -s -v
```

---

## Credentials

All credentials are managed via JCasC (`ci/config/jenkins.yml`) and populated from environment variables. No manual UI setup needed.

| ID                    | Type              | Env Vars                             | Description                          |
|-----------------------|-------------------|--------------------------------------|--------------------------------------|
| `ocir-credentials`   | Username/Password | `OCIR_USERNAME`, `OCIR_PASSWORD`     | OCIR login (tenancy/user + auth token) |
| `git-credentials`    | Username/Password | `GIT_USERNAME`, `GIT_TOKEN`          | GitHub PAT for repo access & gitops  |
| `slack-webhook-url`  | Secret text       | `SLACK_WEBHOOK_URL`                  | Slack incoming webhook               |
| `teams-webhook-url`  | Secret text       | `TEAMS_WEBHOOK_URL`                  | MS Teams incoming webhook            |
| `sonar-token`        | Secret text       | `SONAR_TOKEN`                        | SonarQube analysis token (optional)  |

**Kubeconfig:** NOT a Jenkins credential — it's a file at `/var/lib/jenkins/secrets/kubeconfig` exposed via the `KUBECONFIG` global environment variable. All pipeline steps (kubectl, helm) pick it up automatically.

## Global Environment Variables

Hardcoded in `jenkins.yml` (no env var interpolation needed):

| Variable              | Value                                              |
|-----------------------|----------------------------------------------------|
| `OCI_REGION`          | `ap-mumbai-1`                                      |
| `OCIR_URL`            | `bom.ocir.io`                                      |
| `OCIR_NAMESPACE`      | `diksha`                                           |
| `PROJECT_NAME`        | `diksha-dev`                                       |
| `GITOPS_REPO`         | `https://github.com/tsprasath/ai-devops.git`       |
| `GITOPS_BRANCH`       | `main`                                             |
| `AUTH_SERVICE_REPO`   | `https://github.com/tsprasath/sample-test-app.git` |
| `SLACK_CHANNEL`       | `#ci-cd-notifications`                             |
| `SLACK_CHANNEL_ALERTS`| `#ci-cd-alerts`                                    |
| `TRIVY_SEVERITY`      | `CRITICAL,HIGH`                                    |
| `TRIVY_HIGH_THRESHOLD`| `5`                                                |
| `KUBECONFIG`          | `/var/lib/jenkins/secrets/kubeconfig`               |

## Shared Library

```
Name:           diksha-dev-lib
Default version: shared-lib
Retrieval:      Modern SCM → Git Source
  Remote:       https://github.com/tsprasath/ai-devops.git
  Credentials:  git-credentials
```

The shared library lives on the orphan branch `shared-lib` (vars/ and src/ at repo root).
This makes `@Library('diksha-dev-lib') _` available in Jenkinsfiles.

## Pipeline Jobs

All jobs are auto-created by JCasC Job DSL. No manual setup needed.

| Job Name                      | Type                | Description                                          |
|-------------------------------|---------------------|------------------------------------------------------|
| `service-build-auth-service`  | Pipeline            | Build auth-service, push to OCIR, update GitOps      |
| `ai-devops-pr`               | Multibranch Pipeline| PR validation — lint, test, scan (no deploy)         |
| `ai-devops-local`            | Pipeline            | Local/WSL dev pipeline — no K8s, no shared lib       |

**Adding a new service job:** Copy the `service-build-auth-service` block in `ci/config/jenkins.yml`, change the job name and default parameters (`APP_REPO_URL`, `SERVICE_NAME`), restart Jenkins.

## Kubernetes Cloud (OKE — Optional)

The K8s cloud config is commented out in `jenkins.yml` for local development. Uncomment when deploying to OKE with pod-based agents:

```yaml
# In jenkins.yml → jenkins: → clouds:
clouds:
  - kubernetes:
      name: "oke"
      serverUrl: "${OKE_API_SERVER}"
      namespace: "jenkins"
      jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
      jenkinsTunnel: "jenkins-agent.jenkins.svc.cluster.local:50000"
```

## Namespaces

| Namespace    | Purpose                          |
|--------------|----------------------------------|
| `dev`        | Application workloads (dev)      |
| `staging`    | Application workloads (staging)  |
| `prod`       | Application workloads (prod)     |
| `monitoring` | Prometheus, Grafana, Loki        |

---

## File Structure

```
ci/
├── config/
│   ├── jenkins.yml               # JCasC: jobs, credentials, shared lib, tools, global env vars
│   └── env.example               # Documents required secret env vars only
├── setup-jenkins-ubuntu24.sh     # Automated full Jenkins setup (Ubuntu 24.04)
├── setup-pipeline.groovy         # Pipeline seed job (alternative to JCasC Job DSL)
├── Jenkinsfile                   # Production (K8s agent, shared lib, full pipeline)
├── Jenkinsfile.full              # Full pipeline variant (build + deploy all stages)
├── Jenkinsfile.pr                # PR validation pipeline
├── Jenkinsfile.local             # Local WSL (agent any, self-contained, graceful skips)
├── pod-templates/build-pod.yaml  # Kubernetes pod template for Jenkins agents
├── templates/
│   └── Jenkinsfile.app-repo      # Template for onboarding new app repos
└── SETUP.md                      # This file

shared-lib branch (orphan branch 'shared-lib'):
├── src/org/dev/
│   └── Constants.groovy          # OCI config, credential IDs, scan thresholds
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
  -auth admin:<password> \
  install-plugin plugin1 plugin2 plugin3 ... -deploy
```

### JCasC not applying
- Verify `CASC_JENKINS_CONFIG` env var is set: `systemctl show jenkins | grep CASC`
- Verify secrets loaded: `systemctl show jenkins | grep EnvironmentFile`
- Check Jenkins logs: `journalctl -u jenkins -f`
- Validate config at: http://localhost:8081/configuration-as-code/

### Build #1 shows "Gitleaks: 1 leak found"
This is non-blocking (exit code 0). The leak is a known test credential. Add a `.gitleaksignore` file to suppress known findings.
