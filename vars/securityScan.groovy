def call(Map config = [:]) {
    def image      = config.image ?: error("image is required")
    def configFile = config.configFile ?: 'security/scan-configs/trivy.yaml'
    def reportName = config.reportName ?: 'trivy-report.json'

    echo "Running Trivy security scan on: ${image}"

    // Generate table report for console
    sh """
        trivy image \
            --config ${configFile} \
            --format table \
            ${image}
    """

    // Generate JSON report and fail on CRITICAL
    def exitCode = sh(
        script: """
            trivy image \
                --config ${configFile} \
                --format json \
                --output ${reportName} \
                --exit-code 1 \
                --severity CRITICAL \
                ${image}
        """,
        returnStatus: true
    )

    archiveArtifacts artifacts: reportName, allowEmptyArchive: true

    if (exitCode != 0) {
        error("Trivy scan found CRITICAL vulnerabilities in ${image}")
    }

    echo "Security scan passed - no CRITICAL vulnerabilities found"
}
