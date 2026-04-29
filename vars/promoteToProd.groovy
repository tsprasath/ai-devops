import org.dev.Constants

/**
 * promoteToProd — Promotes an image tag from one environment to the next.
 *
 * Flow: dev → staging (auto after smoke) → prod (manual approval)
 *
 * Usage:
 *   promoteToProd(
 *     service: 'auth-service',
 *     imageTag: "${IMAGE_TAG}",
 *     fromEnv: 'staging',
 *     toEnv: 'prod',
 *     approvers: 'prasath,admin'
 *   )
 */
def call(Map config = [:]) {
    def service       = config.service    ?: config.appName ?: error("service is required")
    def imageTag      = config.imageTag   ?: error("imageTag is required")
    def fromEnv       = config.fromEnv    ?: 'staging'
    def toEnv         = config.toEnv      ?: 'prod'
    def gitopsRepo    = config.gitopsRepo ?: env.GITOPS_REPO ?: 'https://github.com/tsprasath/ai-devops.git'
    def branch        = config.branch     ?: env.GITOPS_BRANCH ?: 'main'
    def credId        = config.credentialsId ?: 'git-credentials'
    def approvers     = config.approvers  ?: ''
    def timeoutMins   = config.timeoutMinutes ?: 30
    def smokeTestUrl  = config.smokeTestUrl ?: ''

    echo "═══════════════════════════════════════════════════"
    echo "Promotion: ${service}:${imageTag}"
    echo "  ${fromEnv} → ${toEnv}"
    echo "═══════════════════════════════════════════════════"

    // ── Smoke test current environment before promoting ──
    if (smokeTestUrl) {
        echo "Running smoke tests against ${fromEnv}..."
        def smokeExit = sh(
            script: """
                for i in 1 2 3 4 5; do
                    STATUS=\$(curl -s -o /dev/null -w '%{http_code}' ${smokeTestUrl}/health)
                    if [ "\$STATUS" = "200" ]; then
                        echo "Smoke test passed (attempt \$i)"
                        exit 0
                    fi
                    echo "Attempt \$i: got \$STATUS, retrying..."
                    sleep 5
                done
                echo "Smoke tests failed"
                exit 1
            """,
            returnStatus: true
        )
        if (smokeExit != 0) {
            error "Smoke tests failed on ${fromEnv} — ${toEnv} promotion aborted"
        }
    }

    // ── Manual approval gate (for prod) ──
    if (toEnv == 'prod') {
        timeout(time: timeoutMins, unit: 'MINUTES') {
            input message: "Promote ${service}:${imageTag} to PRODUCTION?",
                  ok: "Deploy to ${toEnv}",
                  submitter: approvers ?: null
        }
    }

    // ── Update target env values file via gitopsUpdate ──
    gitopsUpdate(
        service: service,
        imageTag: imageTag,
        targetEnv: toEnv,
        gitopsRepo: gitopsRepo,
        branch: branch,
        credentialsId: credId
    )

    // ── Tag for prod releases ──
    if (toEnv == 'prod') {
        sh """
            git tag -a "v${imageTag}" -m "Production release: ${service} v${imageTag}" || true
            git push origin "v${imageTag}" || true
        """
    }

    // ── Notify ──
    try {
        notifyTeam(
            status: 'SUCCESS',
            message: "Promoted ${service}:${imageTag} to ${toEnv}"
        )
    } catch (Exception e) {
        echo "Notification failed: ${e.message}"
    }

    echo "✓ ${service}:${imageTag} promoted to ${toEnv}"
    return [status: 'promoted', tag: imageTag, env: toEnv]
}
