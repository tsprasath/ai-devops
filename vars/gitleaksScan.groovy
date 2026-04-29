def call(Map config = [:]) {
    def reportDir = config.get('reportDir', 'gitleaks-reports')
    def failOnFindings = config.get('failOnFindings', true)
    def scanPath = config.get('scanPath', '.')

    sh "mkdir -p ${reportDir}"

    echo "Running Gitleaks secret detection..."

    def exitCode = sh(
        script: """
            gitleaks detect \
                --source=${scanPath} \
                --report-format=json \
                --report-path=${reportDir}/gitleaks-report.json \
                --verbose
        """,
        returnStatus: true
    )

    archiveArtifacts artifacts: "${reportDir}/**", allowEmptyArchive: true

    def findingCount = 0
    if (fileExists("${reportDir}/gitleaks-report.json")) {
        def findings = readJSON file: "${reportDir}/gitleaks-report.json"
        if (findings instanceof List) {
            findingCount = findings.size()
        }
    }

    echo "Gitleaks scan complete - Findings: ${findingCount}"

    if (findingCount > 0 && failOnFindings) {
        error "Gitleaks FAILED: ${findingCount} secret(s) detected in repository"
    }

    return findingCount
}
