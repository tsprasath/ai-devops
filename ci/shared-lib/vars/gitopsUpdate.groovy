/**
 * gitopsUpdate — Updates image tag in the devops repo Helm values file.
 *
 * Split-repo GitOps flow:
 *   APP REPO (source) → Jenkins builds & pushes image
 *   DEVOPS REPO (ai-devops) → Jenkins updates image.tag in values-{env}.yaml
 *   ArgoCD watches devops repo → deploys new image to cluster
 *
 * Usage:
 *   gitopsUpdate(
 *     service: 'auth-service',
 *     imageTag: "${IMAGE_TAG}",
 *     targetEnv: 'dev'
 *   )
 *
 * Params:
 *   service       - Helm chart directory name under kubernetes/helm-charts/
 *   imageTag      - New image tag (e.g., "abc1234-42")
 *   targetEnv     - Environment: dev, staging, prod (default: dev)
 *   gitopsRepo    - Devops repo URL (default: from GITOPS_REPO env var)
 *   branch        - Branch to update (default: main)
 *   credentialsId - Jenkins credential for git push (default: git-credentials)
 *   yamlPath      - yq path to image tag (default: .image.tag)
 */
def call(Map config = [:]) {
    def service     = config.service     ?: config.serviceName ?: error("service is required")
    def imageTag    = config.imageTag    ?: error("imageTag is required")
    def targetEnv   = config.targetEnv   ?: 'dev'
    def gitopsRepo  = config.gitopsRepo  ?: env.GITOPS_REPO ?: 'https://github.com/tsprasath/ai-devops.git'
    def branch      = config.branch      ?: env.GITOPS_BRANCH ?: 'main'
    def credId      = config.credentialsId ?: 'git-credentials'
    def yamlPath    = config.yamlPath    ?: '.image.tag'

    def valuesFile = "kubernetes/helm-charts/${service}/values-${targetEnv}.yaml"

    echo "═══════════════════════════════════════════════════"
    echo "GitOps Update: ${service} → ${targetEnv}"
    echo "  Image tag:   ${imageTag}"
    echo "  Values file: ${valuesFile}"
    echo "  Repo:        ${gitopsRepo}"
    echo "═══════════════════════════════════════════════════"

    withCredentials([usernamePassword(credentialsId: credId, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
        sh """
            set -e
            rm -rf gitops-workdir
            git clone https://\${GIT_USER}:\${GIT_TOKEN}@${gitopsRepo.replaceAll('https://', '')} gitops-workdir
            cd gitops-workdir
            git checkout ${branch}

            # Update image tag in the environment values file
            yq e '${yamlPath} = "${imageTag}"' -i ${valuesFile}

            # Show the change
            git diff

            # Commit and push
            git config user.email "jenkins@ci.local"
            git config user.name "Jenkins CI"
            git add ${valuesFile}
            git diff --cached --quiet && echo "No changes to commit" && exit 0
            git commit -m "deploy(${targetEnv}): ${service} → ${imageTag}"
            git push origin ${branch}
        """
    }

    echo "✓ GitOps repo updated — ArgoCD will sync ${service} in ${targetEnv}"
}
