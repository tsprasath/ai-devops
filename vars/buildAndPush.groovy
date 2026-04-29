def call(Map config = [:]) {
    def imageName = config.imageName ?: error("imageName is required")
    def imageTag  = config.imageTag  ?: error("imageTag is required")
    def registry  = config.registry  ?: error("registry is required")
    def credId    = config.credentialsId ?: 'ocir-credentials'
    def dockerfile = config.dockerfile ?: 'Dockerfile'
    def context    = config.context ?: '.'

    def fullImage = "${registry}/${imageName}:${imageTag}"

    echo "Building Docker image: ${fullImage}"
    sh "docker build -t ${fullImage} -f ${dockerfile} ${context}"

    echo "Pushing image to OCIR: ${fullImage}"
    withCredentials([usernamePassword(credentialsId: credId, usernameVariable: 'OCIR_USER', passwordVariable: 'OCIR_TOKEN')]) {
        sh "echo ${OCIR_TOKEN} | docker login ${registry} -u ${OCIR_USER} --password-stdin"
        sh "docker push ${fullImage}"
    }

    return fullImage
}
