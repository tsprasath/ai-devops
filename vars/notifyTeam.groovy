def call(Map config = [:]) {
    def status  = config.status  ?: currentBuild.currentResult
    def channel = config.channel ?: '#builds'
    def webhookCredId = config.webhookCredentialsId ?: 'teams-webhook-url'

    def color = status == 'SUCCESS' ? '#36a64f' : '#dc3545'
    def emoji = status == 'SUCCESS' ? ':white_check_mark:' : ':x:'

    def payload = """{
        "text": "${emoji} *${env.JOB_NAME}* #${env.BUILD_NUMBER}",
        "attachments": [{
            "color": "${color}",
            "fields": [
                { "title": "Status", "value": "${status}", "short": true },
                { "title": "Branch", "value": "${env.GIT_BRANCH ?: 'N/A'}", "short": true },
                { "title": "Commit", "value": "${env.GIT_COMMIT?.take(7) ?: 'N/A'}", "short": true },
                { "title": "Build URL", "value": "${env.BUILD_URL}", "short": false }
            ]
        }]
    }"""

    // Try Slack webhook
    try {
        withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_WEBHOOK')]) {
            sh "curl -s -X POST -H 'Content-type: application/json' --data '${payload}' ${SLACK_WEBHOOK}"
        }
    } catch (Exception e) {
        echo "Slack notification skipped: ${e.message}"
    }

    // Try Teams webhook
    try {
        withCredentials([string(credentialsId: webhookCredId, variable: 'TEAMS_WEBHOOK')]) {
            def teamsPayload = """{
                "@type": "MessageCard",
                "themeColor": "${color}",
                "summary": "${env.JOB_NAME} ${status}",
                "sections": [{
                    "activityTitle": "${emoji} ${env.JOB_NAME} #${env.BUILD_NUMBER} - ${status}",
                    "facts": [
                        { "name": "Branch", "value": "${env.GIT_BRANCH ?: 'N/A'}" },
                        { "name": "Commit", "value": "${env.GIT_COMMIT?.take(7) ?: 'N/A'}" }
                    ],
                    "potentialAction": [{
                        "@type": "OpenUri",
                        "name": "View Build",
                        "targets": [{ "os": "default", "uri": "${env.BUILD_URL}" }]
                    }]
                }]
            }"""
            sh "curl -s -X POST -H 'Content-type: application/json' --data '${teamsPayload}' ${TEAMS_WEBHOOK}"
        }
    } catch (Exception e) {
        echo "Teams notification skipped: ${e.message}"
    }
}
