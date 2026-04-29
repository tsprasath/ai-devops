import org.dev.Constants

def call(Map config = [:]) {
    def imageName = config.get('imageName', Constants.PROJECT_NAME)
    def dockerfile = config.get('dockerfile', 'Dockerfile')
    def context = config.get('context', '.')
    def registry = config.get('registry', Constants.OCIR_REPO)
    def cacheFrom = config.get('cacheFrom', "${registry}/${imageName}:latest")
    def extraBuildArgs = config.get('buildArgs', [:])

    def gitCommit = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
    def gitShortSha = gitCommit.take(7)
    def branchName = env.BRANCH_NAME?.replaceAll('[^a-zA-Z0-9_.-]', '-') ?: 'unknown'
    def buildNumber = env.BUILD_NUMBER ?: '0'
    def buildDate = sh(script: 'date -u +"%Y-%m-%dT%H:%M:%SZ"', returnStdout: true).trim()
    def version = config.get('version', "${branchName}-${gitShortSha}")

    def fullImage = "${registry}/${imageName}"

    // Build tags list
    def tags = [
        gitShortSha,
        "${branchName}-${buildNumber}",
        buildNumber
    ]
    if (branchName == 'main' || branchName == 'master') {
        tags.add('latest')
    }

    // Construct build args
    def buildArgsStr = [
        "--build-arg BUILD_DATE=${buildDate}",
        "--build-arg GIT_COMMIT=${gitCommit}",
        "--build-arg VERSION=${version}"
    ]
    extraBuildArgs.each { k, v ->
        buildArgsStr.add("--build-arg ${k}=${v}")
    }

    // Construct tag flags
    def tagFlags = tags.collect { "-t ${fullImage}:${it}" }.join(' ')

    echo "Building Docker image: ${fullImage}"
    echo "Tags: ${tags.join(', ')}"

    sh """
        docker pull ${cacheFrom} || true
        docker build \
            --cache-from ${cacheFrom} \
            ${buildArgsStr.join(' ')} \
            ${tagFlags} \
            -f ${dockerfile} \
            --label org.opencontainers.image.created=${buildDate} \
            --label org.opencontainers.image.revision=${gitCommit} \
            --label org.opencontainers.image.version=${version} \
            ${context}
    """

    def primaryTag = "${fullImage}:${gitShortSha}"
    echo "Primary image: ${primaryTag}"

    return [
        image: fullImage,
        primaryTag: primaryTag,
        tags: tags,
        gitCommit: gitCommit,
        gitShortSha: gitShortSha,
        version: version
    ]
}
