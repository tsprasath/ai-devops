#!/usr/bin/env bash
# =============================================================================
# Jenkins 2.555.x LTS — Full Setup on Ubuntu 24.04
# =============================================================================
# Usage:
#   chmod +x setup-jenkins-ubuntu24.sh
#   sudo ./setup-jenkins-ubuntu24.sh
#
# What this does:
#   1. Installs Java 21 (Temurin)
#   2. Installs Jenkins 2.555.x LTS from official repo
#   3. Installs Docker + adds jenkins user to docker group
#   4. Installs Node.js 20 LTS (for JS builds)
#   5. Installs Trivy (container security scanner)
#   6. Installs Helm 3 (K8s package manager)
#   7. Installs kubectl
#   8. Installs Git, jq, curl, unzip
#   9. Configures Jenkins (port, JVM opts, admin user)
#  10. Installs essential plugins (no manual UI clicking)
#  11. Prints access URL + initial admin password
# =============================================================================

set -euo pipefail

# ── CONFIG ───────────────────────────────────────────────────────────────────
JENKINS_PORT="${JENKINS_PORT:-8080}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-admin123}"
JAVA_VERSION="21"
NODE_VERSION="20"
JENKINS_HOME="/var/lib/jenkins"
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

[[ $EUID -eq 0 ]] || err "Run as root: sudo $0"
[[ "$(lsb_release -rs 2>/dev/null || echo unknown)" == "24.04" ]] || warn "Tested on Ubuntu 24.04 — your mileage may vary"

export DEBIAN_FRONTEND=noninteractive

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
    wget \
    fontconfig \
    > /dev/null 2>&1
log "Base packages installed"

# ═════════════════════════════════════════════════════════════════════════════
# 2. JAVA 21 (Eclipse Temurin — recommended for Jenkins)
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
# 3. JENKINS 2.555.x LTS
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

# Add Jenkins LTS repo
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
    | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg 2>/dev/null
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
# 4. CONFIGURE JENKINS
# ═════════════════════════════════════════════════════════════════════════════
step "Configure Jenkins"

# Set JVM options
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xmx2g -Xms512m -Djenkins.install.runSetupWizard=false"
Environment="JENKINS_PORT=${JENKINS_PORT}"
EOF

# Set port in defaults file too
if [[ -f /etc/default/jenkins ]]; then
    sed -i "s/^HTTP_PORT=.*/HTTP_PORT=${JENKINS_PORT}/" /etc/default/jenkins
fi

systemctl daemon-reload
log "JVM: -Xmx2g -Xms512m, Port: ${JENKINS_PORT}, Setup wizard: disabled"

# ═════════════════════════════════════════════════════════════════════════════
# 5. ADMIN USER + SECURITY (via init.groovy.d)
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

chown -R jenkins:jenkins "${JENKINS_HOME}/init.groovy.d"
log "Admin: ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASS}"

# ═════════════════════════════════════════════════════════════════════════════
# 6. DOCKER
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
# 7. NODE.JS 20 LTS
# ═════════════════════════════════════════════════════════════════════════════
step "Node.js ${NODE_VERSION} LTS"
if node --version 2>/dev/null | grep -q "v${NODE_VERSION}"; then
    log "Node.js already installed: $(node --version)"
else
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
    log "Node.js installed: $(node --version), npm: $(npm --version)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 8. TRIVY (Container Security Scanner)
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
# 9. HELM 3
# ═════════════════════════════════════════════════════════════════════════════
step "Helm 3"
if command -v helm &>/dev/null; then
    log "Helm already installed: $(helm version --short)"
else
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1
    log "Helm installed: $(helm version --short)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 10. KUBECTL
# ═════════════════════════════════════════════════════════════════════════════
step "kubectl"
if command -v kubectl &>/dev/null; then
    log "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    KUBECTL_VER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
    log "kubectl installed: ${KUBECTL_VER}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 11. GITLEAKS (Secret Detection)
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
# 12. START JENKINS + WAIT FOR READY
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
# 13. INSTALL PLUGINS (via jenkins-cli)
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

echo "Installing ${#PLUGINS[@]} plugins..."
for plugin in "${PLUGINS[@]}"; do
    install_plugin "$plugin" &
    # Throttle: max 5 parallel installs
    [[ $(jobs -r -p | wc -l) -ge 5 ]] && wait -n
done
wait
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
# 14. CLEANUP INIT SCRIPTS (run once)
# ═════════════════════════════════════════════════════════════════════════════
# Remove init scripts so they don't re-run on every restart
rm -f "${JENKINS_HOME}/init.groovy.d/01-admin-user.groovy"
log "Init scripts cleaned up"

# ═════════════════════════════════════════════════════════════════════════════
# 15. FIREWALL (optional — open port)
# ═════════════════════════════════════════════════════════════════════════════
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    ufw allow "${JENKINS_PORT}/tcp" > /dev/null 2>&1
    log "Firewall: port ${JENKINS_PORT} opened"
fi

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
echo "    Node.js:  $(node --version 2>/dev/null)"
echo "    npm:      $(npm --version 2>/dev/null)"
echo "    Trivy:    $(trivy --version 2>/dev/null | head -1)"
echo "    Helm:     $(helm version --short 2>/dev/null)"
echo "    kubectl:  $(kubectl version --client --short 2>/dev/null || echo 'installed')"
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
