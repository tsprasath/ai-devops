#!/usr/bin/env bash
# =============================================================================
# Jenkins 2.555.x LTS — Full DevOps Workstation Setup on Ubuntu 24.04
# =============================================================================
# Usage:
#   chmod +x setup-jenkins-ubuntu24.sh
#   sudo ./setup-jenkins-ubuntu24.sh
#
# What this does:
#   1.  System packages (git, jq, curl, unzip, zip, tree, colordiff, etc.)
#   2.  Timezone → Asia/Kolkata (IST)
#   3.  Java 21 (Eclipse Temurin)
#   4.  Jenkins 2.555.x LTS + plugins + admin user
#   5.  Docker Engine + adds jenkins user to docker group
#   6.  Python 3.x + pip
#   7.  NVM + Node.js 20 LTS
#   8.  OCI CLI (Oracle Cloud)
#   9.  Ansible 9.12.0 (ansible-core 2.16.x)
#  10.  Helm 3.16.3
#  11.  kubectl 1.30.8
#  12.  k9s 0.32.7
#  13.  OPA (Open Policy Agent) 0.70.0
#  14.  Trivy (container security scanner)
#  15.  Gitleaks (secret detection)
# =============================================================================

set -euo pipefail

# ── CONFIG ───────────────────────────────────────────────────────────────────
# All credentials can be set via environment variables OR will be prompted.
# Example: JENKINS_ADMIN_PASS=mysecret sudo -E ./setup-jenkins-ubuntu24.sh
JAVA_VERSION="21"
NODE_VERSION="20"
JENKINS_HOME="/var/lib/jenkins"

# Pinned tool versions
HELM_VERSION="3.16.3"
KUBECTL_VERSION="1.30.8"
K9S_VERSION="0.32.7"
OPA_VERSION="0.70.0"
ANSIBLE_VERSION="9.12.0"      # ansible package (includes ansible-core 2.16.x)
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo -E $0"
[[ "$(lsb_release -rs 2>/dev/null || echo unknown)" == "24.04" ]] || warn "Tested on Ubuntu 24.04 — your mileage may vary"

export DEBIAN_FRONTEND=noninteractive

# ═════════════════════════════════════════════════════════════════════════════
# 0. INTERACTIVE CREDENTIAL PROMPTS (skip if env vars are set)
# ═════════════════════════════════════════════════════════════════════════════
# Helper: prompt for a value if env var is empty. Usage: ask VAR "prompt" "default"
ask() {
    local var="$1" prompt="$2" default="${3:-}"
    if [[ -n "${!var:-}" ]]; then
        log "${prompt}: ${!var} (from env)"
        return
    fi
    if [[ -n "$default" ]]; then
        read -rp "  ${prompt} [${default}]: " val
        eval "$var=\"${val:-$default}\""
    else
        read -rp "  ${prompt}: " val
        while [[ -z "$val" ]]; do
            warn "This field is required"
            read -rp "  ${prompt}: " val
        done
        eval "$var=\"$val\""
    fi
}

# Helper: prompt for password (hidden input)
ask_secret() {
    local var="$1" prompt="$2" default="${3:-}"
    if [[ -n "${!var:-}" ]]; then
        log "${prompt}: ******* (from env)"
        return
    fi
    if [[ -n "$default" ]]; then
        read -srp "  ${prompt} [${default}]: " val
        echo ""
        eval "$var=\"${val:-$default}\""
    else
        read -srp "  ${prompt}: " val
        echo ""
        while [[ -z "$val" ]]; do
            warn "This field is required"
            read -srp "  ${prompt}: " val
            echo ""
        done
        eval "$var=\"$val\""
    fi
}

echo ""
echo -e "${CYAN}━━━ Runtime Configuration ━━━${NC}"
echo -e "  Set via env vars to skip prompts (e.g. ${YELLOW}JENKINS_ADMIN_PASS=xxx sudo -E $0${NC})"
echo ""

echo -e "  ${GREEN}── Jenkins ──${NC}"
ask         JENKINS_PORT        "Jenkins port"                   "8080"
ask         JENKINS_ADMIN_USER  "Jenkins admin username"         "admin"
ask_secret  JENKINS_ADMIN_PASS  "Jenkins admin password"         "admin123"

echo ""
echo -e "  ${GREEN}── OCIR (OCI Container Registry) ──${NC}"
ask         OCIR_USER           "OCIR username (namespace/user)" "bmzbbujw9kal/oracleidentitycloudservice/user@example.com"
ask_secret  OCIR_TOKEN          "OCIR auth token"                ""

echo ""
echo -e "  ${GREEN}── Teams Webhook ──${NC}"
ask         TEAMS_WEBHOOK_URL   "Teams webhook URL"              ""

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# 1. SYSTEM UPDATES + BASE PACKAGES
# ═════════════════════════════════════════════════════════════════════════════
step "System update + base packages"
apt-get update -qq
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    jq \
    unzip \
    zip \
    wget \
    fontconfig \
    tree \
    colordiff \
    python3 \
    python3-pip \
    python3-venv \
    > /dev/null 2>&1
log "Base packages installed"

# ═════════════════════════════════════════════════════════════════════════════
# 2. TIMEZONE → IST
# ═════════════════════════════════════════════════════════════════════════════
step "Timezone → Asia/Kolkata (IST)"
timedatectl set-timezone Asia/Kolkata 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
log "Timezone set to $(date +%Z) ($(date +%z))"

# ═════════════════════════════════════════════════════════════════════════════
# 3. JAVA 21 (Eclipse Temurin — recommended for Jenkins)
# ═════════════════════════════════════════════════════════════════════════════
step "Java ${JAVA_VERSION} (Eclipse Temurin)"
if java -version 2>&1 | grep -q "version \"${JAVA_VERSION}"; then
    log "Java ${JAVA_VERSION} already installed"
else
    wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg
    echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/adoptium.list
    apt-get update -qq
    apt-get install -y -qq "temurin-${JAVA_VERSION}-jdk" > /dev/null 2>&1
    log "Java ${JAVA_VERSION} installed: $(java -version 2>&1 | head -1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 4. JENKINS 2.555.x LTS
# ═════════════════════════════════════════════════════════════════════════════
step "Jenkins 2.555.x LTS"
if systemctl is-active --quiet jenkins 2>/dev/null; then
    CURRENT_VER=$(jenkins --version 2>/dev/null || echo "unknown")
    if [[ "$CURRENT_VER" == 2.555* ]]; then
        log "Jenkins ${CURRENT_VER} already running"
    else
        warn "Jenkins ${CURRENT_VER} found — will upgrade to 2.555.x"
    fi
fi

# Add Jenkins LTS repo (use current key)
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
    | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg 2>/dev/null || \
    tee /usr/share/keyrings/jenkins-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
    > /etc/apt/sources.list.d/jenkins.list
apt-get update -qq

# Install/pin to 2.555.x
JENKINS_PKG=$(apt-cache madison jenkins | awk '{print $3}' | grep '^2\.555' | head -1)
if [[ -z "$JENKINS_PKG" ]]; then
    warn "2.555.x not found in repo — installing latest LTS"
    apt-get install -y -qq jenkins > /dev/null 2>&1
else
    log "Installing Jenkins ${JENKINS_PKG}"
    apt-get install -y -qq "jenkins=${JENKINS_PKG}" > /dev/null 2>&1
    # Pin version to prevent accidental upgrades
    cat > /etc/apt/preferences.d/jenkins <<EOF
Package: jenkins
Pin: version ${JENKINS_PKG}
Pin-Priority: 1001
EOF
    log "Pinned Jenkins to ${JENKINS_PKG} (won't auto-upgrade)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 5. CONFIGURE JENKINS
# ═════════════════════════════════════════════════════════════════════════════
step "Configure Jenkins"

# Set JVM options
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xmx2g -Xms512m -Djenkins.install.runSetupWizard=false"
Environment="JENKINS_PORT=${JENKINS_PORT}"
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yml"
EnvironmentFile=-/var/lib/jenkins/secrets/.env
EOF

# Copy JCasC config and prepare secrets directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "${JENKINS_HOME}/casc_configs"
if [[ -f "${SCRIPT_DIR}/config/jenkins.yml" ]]; then
    cp "${SCRIPT_DIR}/config/jenkins.yml" "${JENKINS_HOME}/casc_configs/jenkins.yml"
    log "JCasC config copied to ${JENKINS_HOME}/casc_configs/jenkins.yml"
fi
mkdir -p "${JENKINS_HOME}/secrets"
if [[ ! -f "${JENKINS_HOME}/secrets/.env" ]]; then
    touch "${JENKINS_HOME}/secrets/.env"
    chmod 600 "${JENKINS_HOME}/secrets/.env"
    log "Secrets .env placeholder created — fill with values from ci/config/env.example"
fi

# Set port in defaults file too
if [[ -f /etc/default/jenkins ]]; then
    sed -i "s/^HTTP_PORT=.*/HTTP_PORT=${JENKINS_PORT}/" /etc/default/jenkins
fi

systemctl daemon-reload
log "JVM: -Xmx2g -Xms512m, Port: ${JENKINS_PORT}, Setup wizard: disabled"

# ═════════════════════════════════════════════════════════════════════════════
# 6. ADMIN USER + SECURITY (via init.groovy.d)
# ═════════════════════════════════════════════════════════════════════════════
step "Admin user setup"
mkdir -p "${JENKINS_HOME}/init.groovy.d"

cat > "${JENKINS_HOME}/init.groovy.d/01-admin-user.groovy" <<'GROOVY'
import jenkins.model.*
import hudson.security.*
import hudson.model.*

def instance = Jenkins.getInstance()

// Create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
def existingUser = hudsonRealm.getUser("ADMIN_USER_PLACEHOLDER")
if (existingUser == null) {
    hudsonRealm.createAccount("ADMIN_USER_PLACEHOLDER", "ADMIN_PASS_PLACEHOLDER")
}
instance.setSecurityRealm(hudsonRealm)

// Authorization: logged-in users can do anything, anon read
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Set URL
def jlc = JenkinsLocationConfiguration.get()
jlc.setUrl("http://localhost:JENKINS_PORT_PLACEHOLDER/")
jlc.save()

instance.save()
println "[init] Admin user created, security configured"
GROOVY

# Replace placeholders
sed -i "s/ADMIN_USER_PLACEHOLDER/${JENKINS_ADMIN_USER}/g" "${JENKINS_HOME}/init.groovy.d/01-admin-user.groovy"
sed -i "s/ADMIN_PASS_PLACEHOLDER/${JENKINS_ADMIN_PASS}/g" "${JENKINS_HOME}/init.groovy.d/01-admin-user.groovy"
sed -i "s/JENKINS_PORT_PLACEHOLDER/${JENKINS_PORT}/g"     "${JENKINS_HOME}/init.groovy.d/01-admin-user.groovy"

# Clear stale user dirs (from previous installs) so fresh realm works
rm -rf "${JENKINS_HOME}/users/"*

chown -R jenkins:jenkins "${JENKINS_HOME}/init.groovy.d"
log "Admin: ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASS}"

# ═════════════════════════════════════════════════════════════════════════════
# 7. DOCKER
# ═════════════════════════════════════════════════════════════════════════════
step "Docker Engine"
if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
else
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    systemctl enable --now docker
    log "Docker installed: $(docker --version)"
fi

# Add jenkins user to docker group
usermod -aG docker jenkins 2>/dev/null || true
log "Jenkins user added to docker group"

# ═════════════════════════════════════════════════════════════════════════════
# 8. JENKINS BASHRC + DOCKER GROUP
# ═════════════════════════════════════════════════════════════════════════════
step "Jenkins user config"
cp /etc/skel/.bashrc "${JENKINS_HOME}/.bashrc" 2>/dev/null || true
chown jenkins:jenkins "${JENKINS_HOME}/.bashrc" 2>/dev/null || true
log "Jenkins bashrc + docker group configured"

# ═════════════════════════════════════════════════════════════════════════════
# 9. NVM + NODE.JS 20 LTS
# ═════════════════════════════════════════════════════════════════════════════
step "NVM + Node.js ${NODE_VERSION} LTS"
export NVM_DIR="/opt/nvm"
mkdir -p "${NVM_DIR}"
if [[ ! -f "${NVM_DIR}/nvm.sh" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | NVM_DIR="${NVM_DIR}" bash > /dev/null 2>&1
    log "NVM installed to ${NVM_DIR}"
else
    log "NVM already installed"
fi
# Source NVM and install Node
source "${NVM_DIR}/nvm.sh"
nvm install "${NODE_VERSION}" > /dev/null 2>&1
nvm alias default "${NODE_VERSION}" > /dev/null 2>&1
# Symlink node/npm to /usr/local/bin so all users (including jenkins) can use them
NODE_PATH="$(nvm which ${NODE_VERSION})"
NODE_DIR="$(dirname "${NODE_PATH}")"
ln -sf "${NODE_DIR}/node" /usr/local/bin/node
ln -sf "${NODE_DIR}/npm" /usr/local/bin/npm
ln -sf "${NODE_DIR}/npx" /usr/local/bin/npx
# Add NVM sourcing to jenkins bashrc
if ! grep -q 'NVM_DIR' "${JENKINS_HOME}/.bashrc" 2>/dev/null; then
    cat >> "${JENKINS_HOME}/.bashrc" <<NVMRC
export NVM_DIR="${NVM_DIR}"
[ -s "\${NVM_DIR}/nvm.sh" ] && . "\${NVM_DIR}/nvm.sh"
NVMRC
fi
log "Node.js installed: $(node --version), npm: $(npm --version)"

# ═════════════════════════════════════════════════════════════════════════════
# 10. OCI CLI (Oracle Cloud Infrastructure)
# ═════════════════════════════════════════════════════════════════════════════
step "OCI CLI"
if command -v oci &>/dev/null; then
    log "OCI CLI already installed: $(oci --version 2>&1)"
else
    # Install OCI CLI non-interactively for all users
    curl -fsSL https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh | \
        bash -s -- --accept-all-defaults --install-dir /opt/oci-cli/lib --exec-dir /usr/local/bin > /dev/null 2>&1
    log "OCI CLI installed: $(oci --version 2>&1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 11. ANSIBLE ${ANSIBLE_VERSION}
# ═════════════════════════════════════════════════════════════════════════════
step "Ansible ${ANSIBLE_VERSION}"
CURRENT_ANSIBLE=$(pip3 show ansible 2>/dev/null | grep -i '^version:' | awk '{print $2}' || echo "none")
if [[ "$CURRENT_ANSIBLE" == "${ANSIBLE_VERSION}" ]]; then
    log "Ansible ${ANSIBLE_VERSION} already installed"
else
    pip3 install --break-system-packages "ansible==${ANSIBLE_VERSION}" > /dev/null 2>&1
    log "Ansible installed: $(ansible --version | head -1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 12. TRIVY (Container Security Scanner)
# ═════════════════════════════════════════════════════════════════════════════
step "Trivy"
if command -v trivy &>/dev/null; then
    log "Trivy already installed: $(trivy --version | head -1)"
else
    curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
        | gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
        > /etc/apt/sources.list.d/trivy.list
    apt-get update -qq
    apt-get install -y -qq trivy > /dev/null 2>&1
    log "Trivy installed: $(trivy --version | head -1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 13. HELM ${HELM_VERSION}
# ═════════════════════════════════════════════════════════════════════════════
step "Helm ${HELM_VERSION}"
if helm version --short 2>/dev/null | grep -q "${HELM_VERSION}"; then
    log "Helm ${HELM_VERSION} already installed"
else
    curl -fsSLo /tmp/helm.tar.gz \
        "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
    tar xzf /tmp/helm.tar.gz -C /tmp
    mv /tmp/linux-amd64/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
    rm -rf /tmp/linux-amd64 /tmp/helm.tar.gz
    log "Helm installed: $(helm version --short)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 14. KUBECTL ${KUBECTL_VERSION}
# ═════════════════════════════════════════════════════════════════════════════
step "kubectl ${KUBECTL_VERSION}"
if kubectl version --client -o json 2>/dev/null | grep -q "${KUBECTL_VERSION}"; then
    log "kubectl ${KUBECTL_VERSION} already installed"
else
    curl -fsSLo /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
    log "kubectl installed: v${KUBECTL_VERSION}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 15. GITLEAKS (Secret Detection)
# ═════════════════════════════════════════════════════════════════════════════
step "Gitleaks"
if command -v gitleaks &>/dev/null; then
    log "Gitleaks already installed: $(gitleaks version)"
else
    GITLEAKS_VER=$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name | tr -d v)
    curl -fsSLo /tmp/gitleaks.tar.gz \
        "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz"
    tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks
    chmod +x /usr/local/bin/gitleaks
    rm -f /tmp/gitleaks.tar.gz
    log "Gitleaks installed: $(gitleaks version)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 16. K9S ${K9S_VERSION}
# ═════════════════════════════════════════════════════════════════════════════
step "k9s ${K9S_VERSION}"
if k9s version --short 2>/dev/null | grep -q "${K9S_VERSION}"; then
    log "k9s ${K9S_VERSION} already installed"
else
    curl -fsSLo /tmp/k9s.tar.gz \
        "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
    tar xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s
    chmod +x /usr/local/bin/k9s
    rm -f /tmp/k9s.tar.gz
    log "k9s installed: v${K9S_VERSION}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 17. OPA (Open Policy Agent) ${OPA_VERSION}
# ═════════════════════════════════════════════════════════════════════════════
step "OPA ${OPA_VERSION}"
if opa version 2>/dev/null | grep -q "${OPA_VERSION}"; then
    log "OPA ${OPA_VERSION} already installed"
else
    curl -fsSLo /usr/local/bin/opa \
        "https://openpolicyagent.org/downloads/v${OPA_VERSION}/opa_linux_amd64_static"
    chmod +x /usr/local/bin/opa
    log "OPA installed: $(opa version | head -1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 18. START JENKINS + WAIT FOR READY
# ═════════════════════════════════════════════════════════════════════════════
step "Starting Jenkins"
systemctl enable jenkins
systemctl restart jenkins

echo -n "  Waiting for Jenkins to start "
for i in $(seq 1 60); do
    if curl -sf -o /dev/null "http://localhost:${JENKINS_PORT}/login" 2>/dev/null; then
        echo ""
        log "Jenkins is UP on port ${JENKINS_PORT}"
        break
    fi
    echo -n "."
    sleep 3
done

# Verify it's actually responding
if ! curl -sf -o /dev/null "http://localhost:${JENKINS_PORT}/login" 2>/dev/null; then
    err "Jenkins failed to start within 3 minutes. Check: journalctl -u jenkins -n 50"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 19. INSTALL PLUGINS (via jenkins-cli)
# ═════════════════════════════════════════════════════════════════════════════
step "Installing plugins"

# Download CLI jar
CLI_JAR="/tmp/jenkins-cli.jar"
curl -sf -o "${CLI_JAR}" "http://localhost:${JENKINS_PORT}/jnlpJars/jenkins-cli.jar"

install_plugin() {
    java -jar "${CLI_JAR}" \
        -s "http://localhost:${JENKINS_PORT}" \
        -auth "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}" \
        install-plugin "$1" -deploy 2>/dev/null && echo "  ✓ $1" || echo "  ✗ $1 (failed)"
}

# Essential plugins
PLUGINS=(
    # Pipeline
    workflow-aggregator          # Pipeline suite (all pipeline steps)
    pipeline-stage-view          # Stage view visualization
    pipeline-utility-steps       # readFile, writeFile, etc.
    pipeline-graph-view          # Pipeline graph
    
    # SCM
    git                          # Git plugin
    github                       # GitHub integration
    github-branch-source         # GitHub multibranch
    
    # Build tools
    nodejs                       # Node.js installations
    docker-workflow              # Docker pipeline steps
    docker-commons               # Docker commons
    
    # Kubernetes
    kubernetes                   # K8s cloud + pod templates
    kubernetes-cli               # kubectl in pipeline
    
    # Credentials
    credentials-binding          # Inject creds into builds
    ssh-credentials              # SSH keys
    
    # UI & Reporting
    blueocean                    # Modern UI
    ansicolor                    # ANSI color in console
    timestamper                  # Timestamps in console
    
    # Notifications
    mailer                       # Email notifications
    slack                        # Slack notifications
    
    # Security & Quality
    warnings-ng                  # Compiler warnings, lint
    junit                        # Test results
    jacoco                       # Code coverage
    
    # Administration
    configuration-as-code        # JCasC (YAML config)
    job-dsl                      # Job DSL (groovy job definitions)
    matrix-auth                  # Matrix authorization
    role-strategy                # Role-based access control
    ws-cleanup                   # Workspace cleanup
    build-discarder              # Build log rotation
    throttle-concurrents         # Throttle builds
    
    # Misc
    locale                       # Force English locale
    dark-theme                   # Dark theme
    rebuild                      # Rebuild with same params
    parameterized-trigger        # Trigger parameterized builds
)

echo "Installing ${#PLUGINS[@]} plugins in one batch..."
java -jar "${CLI_JAR}" \
    -s "http://localhost:${JENKINS_PORT}" \
    -auth "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}" \
    install-plugin "${PLUGINS[@]}" -deploy 2>&1 | while read -r line; do echo "  $line"; done
log "Plugin installation complete"

# Restart to activate plugins
systemctl restart jenkins
echo -n "  Restarting Jenkins "
for i in $(seq 1 40); do
    if curl -sf -o /dev/null "http://localhost:${JENKINS_PORT}/login" 2>/dev/null; then
        echo ""
        log "Jenkins restarted with plugins"
        break
    fi
    echo -n "."
    sleep 3
done

# ═════════════════════════════════════════════════════════════════════════════
# 20. CLEANUP INIT SCRIPTS (run once)
# ═════════════════════════════════════════════════════════════════════════════
# Remove init scripts so they don't re-run on every restart
rm -f "${JENKINS_HOME}/init.groovy.d/01-admin-user.groovy"
log "Init scripts cleaned up"

# ═════════════════════════════════════════════════════════════════════════════
# DONE — SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ JENKINS SETUP COMPLETE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  URL:       http://$(hostname -I | awk '{print $1}'):${JENKINS_PORT}"
echo "  Local:     http://localhost:${JENKINS_PORT}"
echo "  User:      ${JENKINS_ADMIN_USER}"
echo "  Password:  ${JENKINS_ADMIN_PASS}"
echo ""
echo "  Installed tools:"
echo "    Java:     $(java -version 2>&1 | head -1)"
echo "    Jenkins:  $(jenkins --version 2>/dev/null || echo 'check systemctl status jenkins')"
echo "    Docker:   $(docker --version 2>/dev/null)"
echo "    Python:   $(python3 --version 2>/dev/null)"
echo "    NVM:      $(source /opt/nvm/nvm.sh 2>/dev/null && nvm --version || echo 'installed')"
echo "    Node.js:  $(node --version 2>/dev/null)"
echo "    npm:      $(npm --version 2>/dev/null)"
echo "    OCI CLI:  $(oci --version 2>/dev/null || echo 'installed')"
echo "    Ansible:  $(ansible --version 2>/dev/null | head -1)"
echo "    Helm:     $(helm version --short 2>/dev/null)"
echo "    kubectl:  $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion || echo 'installed')"
echo "    k9s:      $(k9s version --short 2>/dev/null | grep Version || echo 'installed')"
echo "    OPA:      $(opa version 2>/dev/null | head -1)"
echo "    Trivy:    $(trivy --version 2>/dev/null | head -1)"
echo "    Gitleaks: $(gitleaks version 2>/dev/null)"
echo ""
echo "  Config:"
echo "    JENKINS_HOME: ${JENKINS_HOME}"
echo "    JVM:          -Xmx2g -Xms512m"
echo "    Plugins:      ${#PLUGINS[@]} installed"
echo "    Version pin:  /etc/apt/preferences.d/jenkins"
echo ""
echo "  Next steps:"
echo "    1. Open http://localhost:${JENKINS_PORT} in browser"
echo "    2. Login with ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASS}"
echo "    3. Configure credentials (Manage Jenkins → Credentials)"
echo "    4. Create your first pipeline job"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
