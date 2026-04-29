def call(Map config = [:]) {
    def chartPath = config.get('chartPath', 'helm/app')
    def valuesFile = config.get('valuesFile', '')
    def kubeVersion = config.get('kubeVersion', '1.28.0')
    def strict = config.get('strict', true)
    def reportDir = config.get('reportDir', 'helm-reports')

    sh "mkdir -p ${reportDir}"

    def results = [lint: 'failed', template: 'failed', validate: 'failed']

    // Helm lint
    echo "Running helm lint on ${chartPath}..."
    def strictFlag = strict ? '--strict' : ''
    def valuesFlag = valuesFile ? "-f ${valuesFile}" : ''

    def lintExit = sh(
        script: "helm lint ${chartPath} ${strictFlag} ${valuesFlag} 2>&1 | tee ${reportDir}/helm-lint.txt",
        returnStatus: true
    )
    results.lint = lintExit == 0 ? 'passed' : 'failed'

    // Helm template (dry-run render)
    echo "Rendering helm templates..."
    def templateExit = sh(
        script: """
            helm template test-release ${chartPath} \
                ${valuesFlag} \
                --kube-version ${kubeVersion} \
                > ${reportDir}/rendered-templates.yaml 2>&1
        """,
        returnStatus: true
    )
    results.template = templateExit == 0 ? 'passed' : 'failed'

    // kubeconform validation on rendered templates
    if (templateExit == 0) {
        echo "Validating rendered templates with kubeconform..."
        def validateExit = sh(
            script: """
                kubeconform \
                    -kubernetes-version ${kubeVersion} \
                    -summary \
                    -output json \
                    ${reportDir}/rendered-templates.yaml \
                    > ${reportDir}/kubeconform-report.json 2>&1 || true
                kubeconform \
                    -kubernetes-version ${kubeVersion} \
                    -summary \
                    ${reportDir}/rendered-templates.yaml \
                    2>&1 | tee ${reportDir}/kubeconform.txt
            """,
            returnStatus: true
        )
        results.validate = validateExit == 0 ? 'passed' : 'failed'
    }

    archiveArtifacts artifacts: "${reportDir}/**", allowEmptyArchive: true

    if (results.lint == 'failed') {
        error "Helm lint failed for ${chartPath}"
    }
    if (results.template == 'failed') {
        error "Helm template rendering failed for ${chartPath}"
    }
    if (results.validate == 'failed') {
        unstable "Kubeconform validation found issues in rendered templates"
    }

    echo "Helm validation - Lint: ${results.lint}, Template: ${results.template}, Validate: ${results.validate}"
    return results
}
