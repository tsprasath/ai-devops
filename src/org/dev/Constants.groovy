package org.dev

/**
 * Constants — reads from Jenkins global environment variables set by JCasC.
 *
 * All values are injected via ci/config/jenkins.yml → globalNodeProperties → envVars.
 * Fallback defaults match the env.example values so pipelines work even if
 * a variable is accidentally missing.
 *
 * Usage in pipelines:  import org.dev.Constants
 *                      def registry = Constants.OCIR_URL
 *
 * To change any value, update the env var in your Jenkins pod/container
 * (K8s Secret, Docker -e, systemd EnvironmentFile) — NOT this file.
 */
class Constants implements Serializable {

    // ── OCI / Registry ───────────────────────────────────────────
    static String getOCI_REGION()      { env('OCI_REGION',      'ap-mumbai-1') }
    static String getOCIR_URL()        { env('OCIR_URL',        'bom.ocir.io') }
    static String getOCIR_NAMESPACE()  { env('OCIR_NAMESPACE',  'diksha') }
    static String getPROJECT_NAME()    { env('PROJECT_NAME',    'diksha-dev') }
    static String getOCIR_REPO()       { "${OCIR_URL}/${OCIR_NAMESPACE}/${PROJECT_NAME}" }

    // ── Credential IDs (fixed strings — these map to JCasC credential entries) ──
    static final String OCIR_CREDENTIALS_ID       = 'ocir-credentials'
    static final String GITHUB_TOKEN_CREDENTIAL    = 'git-credentials'
    static final String SLACK_WEBHOOK_CREDENTIAL   = 'slack-webhook-url'
    static final String TEAMS_WEBHOOK_CREDENTIAL   = 'teams-webhook-url'
    static final String SONAR_TOKEN_CREDENTIAL     = 'sonar-token'

    // ── Trivy ────────────────────────────────────────────────────
    static String getTRIVY_SEVERITY_DEFAULT() { env('TRIVY_SEVERITY', 'CRITICAL,HIGH') }
    static final String TRIVY_SEVERITY_CRITICAL = 'CRITICAL'
    static final String TRIVY_SEVERITY_HIGH     = 'HIGH'
    static final int TRIVY_CRITICAL_THRESHOLD   = 0
    static int getTRIVY_HIGH_THRESHOLD()        { env('TRIVY_HIGH_THRESHOLD', '5') as int }

    // ── Notifications ────────────────────────────────────────────
    static String getSLACK_CHANNEL()        { env('SLACK_CHANNEL',        '#ci-cd-notifications') }
    static String getSLACK_CHANNEL_ALERTS() { env('SLACK_CHANNEL_ALERTS', '#ci-cd-alerts') }

    // ── Standard Labels ──────────────────────────────────────────
    static Map<String, String> getSTANDARD_LABELS() {
        [
            'app.kubernetes.io/managed-by' : 'jenkins',
            'app.kubernetes.io/part-of'    : PROJECT_NAME,
            'org.opencontainers.image.source': "https://github.com/tsprasath/ai-devops"
        ]
    }

    // ── Helper: read Jenkins env var with fallback ───────────────
    private static String env(String key, String fallback) {
        // In a Jenkins pipeline context, System.getenv() reads process-level
        // env vars which include JCasC globalNodeProperties values.
        System.getenv(key) ?: fallback
    }
}
