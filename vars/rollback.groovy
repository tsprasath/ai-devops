import org.dev.Constants

def call(Map config = [:]) {
    def gitopsRepo = config.get('gitopsRepo', '')
    def gitopsBranch = config.get('gitopsBranch', 'main')
    def environment = config.get('environment', 'prod')
    def previousTag = config.get('previousTag', '')
    def appName = config.get('appName', Constants.PROJECT_NAME)
    def argoApp = config.get('argoApp', "${appName}-${environment}")

    echo "=== ROLLBACK: ${appName} in ${environment} to ${previousTag} ==="

    if (!previousTag) {
        error "previousTag is required for rollback"
    }

    // Revert GitOps repo to previous image tag
    dir('gitops-rollback') {
        git branch: gitopsBranch, credentialsId: Constants.GITHUB_TOKEN_CREDENTIAL, url: gitopsRepo

        sh """
            cd overlays/${environment} || cd environments/${environment} || true
            if [ -f kustomization.yaml ]; then
                sed -i 's|newTag:.*|newTag: ${previousTag}|' kustomization.yaml
            fi
            if [ -f values.yaml ]; then
                sed -i 's|tag:.*|tag: "${previousTag}"|' values.yaml
            fi
            git add -A
            git commit -m "ROLLBACK: ${appName} in ${environment} to ${previousTag}"
            git push origin ${gitopsBranch}
        """
    }

    // ArgoCD sync
    echo "Triggering ArgoCD sync for ${argoApp}..."
    def syncExit = sh(
        script: """
            argocd app sync ${argoApp} --force --prune 2>&1 || true
            argocd app wait ${argoApp} --timeout 300 --health 2>&1 || true
        """,
        returnStatus: true
    )

    def status = syncExit == 0 ? 'SUCCESS' : 'PARTIAL'
    def message = "ROLLBACK ${status}: ${appName} in ${environment} reverted to ${previousTag}"

    // Notify team
    notifyTeam(status, message)
    echo message

    return [status: status, environment: environment, tag: previousTag]
}

private void notifyTeam(String status, String message) {
    try {
        withCredentials([string(credentialsId: Constants.SLACK_WEBHOOK_CREDENTIAL, variable: 'SLACK_URL')]) {
            def color = status == 'SUCCESS' ? 'warning' : 'danger'
            sh """
                curl -s -X POST \$SLACK_URL \
                    -H 'Content-type: application/json' \
                    -d '{"channel":"${Constants.SLACK_CHANNEL_ALERTS}","attachments":[{"color":"${color}","text":"${message}"}]}'
            """
        }
    } catch (Exception e) {
        echo "Notification failed: ${e.message}"
    }
}
