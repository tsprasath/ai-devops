import org.dev.Constants

def call(Map config = [:]) {
    def image = config.get('image', '')
    def scanFs = config.get('scanFilesystem', true)
    def scanIac = config.get('scanIaC', true)
    def iacPaths = config.get('iacPaths', ['kubernetes/terraform', 'helm'])
    def severity = config.get('severity', Constants.TRIVY_SEVERITY_DEFAULT)
    def failOnCritical = config.get('failOnCritical', true)
    def failOnHigh = config.get('failOnHigh', false)
    def reportDir = config.get('reportDir', 'trivy-reports')

    sh "mkdir -p ${reportDir}"

    def summary = [critical: 0, high: 0, passed: true]

    // Image vulnerability scan
    if (image) {
        echo "Scanning image: ${image}"
        sh """
            trivy image \
                --severity ${severity} \
                --format json \
                --output ${reportDir}/trivy-image.json \
                ${image} || true

            trivy image \
                --severity ${severity} \
                --format template \
                --template '@/usr/local/share/trivy/templates/html.tpl' \
                --output ${reportDir}/trivy-image.html \
                ${image} || true
        """
        summary = parseResults(summary, "${reportDir}/trivy-image.json")
    }

    // Filesystem secret scan
    if (scanFs) {
        echo "Scanning filesystem for secrets..."
        sh """
            trivy fs \
                --scanners secret \
                --format json \
                --output ${reportDir}/trivy-secrets.json \
                . || true
        """
    }

    // IaC misconfig scan
    if (scanIac) {
        iacPaths.each { path ->
            def safeName = path.replaceAll('[^a-zA-Z0-9]', '-')
            if (fileExists(path)) {
                echo "Scanning IaC path: ${path}"
                sh """
                    trivy config \
                        --severity ${severity} \
                        --format json \
                        --output ${reportDir}/trivy-iac-${safeName}.json \
                        ${path} || true

                    trivy config \
                        --severity ${severity} \
                        --format template \
                        --template '@/usr/local/share/trivy/templates/html.tpl' \
                        --output ${reportDir}/trivy-iac-${safeName}.html \
                        ${path} || true
                """
            }
        }
    }

    // Archive reports
    archiveArtifacts artifacts: "${reportDir}/**", allowEmptyArchive: true
    publishHTML(target: [
        allowMissing: true,
        alwaysLinkToLastBuild: true,
        keepAll: true,
        reportDir: reportDir,
        reportFiles: '*.html',
        reportName: 'Trivy Security Report'
    ])

    // Determine pass/fail
    if (failOnCritical && summary.critical > 0) {
        summary.passed = false
        error "Trivy scan FAILED: ${summary.critical} CRITICAL vulnerabilities found"
    }
    if (failOnHigh && summary.high > Constants.TRIVY_HIGH_THRESHOLD) {
        summary.passed = false
        error "Trivy scan FAILED: ${summary.high} HIGH vulnerabilities exceed threshold (${Constants.TRIVY_HIGH_THRESHOLD})"
    }

    echo "Trivy scan complete - Critical: ${summary.critical}, High: ${summary.high}, Passed: ${summary.passed}"
    return summary
}

private Map parseResults(Map summary, String jsonFile) {
    if (fileExists(jsonFile)) {
        def json = readJSON file: jsonFile
        json.Results?.each { result ->
            result.Vulnerabilities?.each { vuln ->
                if (vuln.Severity == 'CRITICAL') summary.critical++
                if (vuln.Severity == 'HIGH') summary.high++
            }
        }
    }
    return summary
}
