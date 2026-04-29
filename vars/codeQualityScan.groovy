def call(Map config = [:]) {
    def reportDir = config.get('reportDir', 'code-quality-reports')
    def sonarUrl = config.get('sonarUrl', env.SONAR_URL ?: '')
    def sonarProject = config.get('sonarProject', env.JOB_NAME ?: 'default-project')
    def failOnAudit = config.get('failOnAudit', true)
    def auditLevel = config.get('auditLevel', 'high')

    sh "mkdir -p ${reportDir}"

    def results = [eslint: 'skipped', audit: 'skipped', sonar: 'skipped']

    // ESLint with JUnit reporter
    echo "Running ESLint..."
    def eslintExit = sh(
        script: """
            npx eslint . \
                --format junit \
                --output-file ${reportDir}/eslint-junit.xml \
                2>&1 || true
            npx eslint . \
                --format json \
                --output-file ${reportDir}/eslint-report.json \
                2>&1 || true
        """,
        returnStatus: true
    )
    results.eslint = eslintExit == 0 ? 'passed' : 'warnings'

    // Publish ESLint JUnit results
    junit allowEmptyResults: true, testResults: "${reportDir}/eslint-junit.xml"

    // npm audit
    echo "Running npm audit..."
    def auditExit = sh(
        script: """
            npm audit --audit-level=${auditLevel} --json > ${reportDir}/npm-audit.json 2>&1
        """,
        returnStatus: true
    )
    results.audit = auditExit == 0 ? 'passed' : 'failed'

    archiveArtifacts artifacts: "${reportDir}/**", allowEmptyArchive: true

    if (auditExit != 0 && failOnAudit) {
        unstable "npm audit found vulnerabilities at level: ${auditLevel}"
    }

    // SonarQube (optional)
    if (sonarUrl) {
        echo "Running SonarQube analysis..."
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
            sh """
                npx sonar-scanner \
                    -Dsonar.host.url=${sonarUrl} \
                    -Dsonar.login=\$SONAR_TOKEN \
                    -Dsonar.projectKey=${sonarProject} \
                    -Dsonar.sources=src \
                    -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
                    || true
            """
        }
        results.sonar = 'submitted'
    }

    echo "Code quality results - ESLint: ${results.eslint}, Audit: ${results.audit}, Sonar: ${results.sonar}"
    return results
}
