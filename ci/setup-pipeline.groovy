// DEPRECATED: Use JCasC (ci/config/jenkins.yml) instead. This script is kept as a legacy fallback.
// setup-pipeline.groovy — Run via Jenkins CLI to create shared lib, pipeline job, and credentials
// Usage: java -jar jenkins-cli.jar -s http://localhost:$PORT -auth $USER:$PASS groovy = < ci/setup-pipeline.groovy
// Credentials are passed via Java system properties (-D flags) from the setup script.

import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.*
import hudson.plugins.git.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.workflow.libs.*
import jenkins.plugins.git.*

def instance = Jenkins.getInstance()

// ── 1. Shared Library: diksha-dev-lib ──
def libConfig = instance.getDescriptor("org.jenkinsci.plugins.workflow.libs.GlobalLibraries")
def scm = new GitSCMSource("diksha-dev-lib", "https://github.com/tsprasath/ai-devops.git", "", "*", "", true)
def retriever = new SCMSourceRetriever(scm)
def lib = new LibraryConfiguration("diksha-dev-lib", retriever)
lib.setDefaultVersion("shared-lib")
lib.setImplicit(false)
lib.setAllowVersionOverride(true)
libConfig.get().setLibraries([lib])
libConfig.get().save()
println "[setup] Shared library 'diksha-dev-lib' configured"

// ── 2. Pipeline Job: ai-devops ──
def jobName = "ai-devops"
def existingJob = instance.getItem(jobName)
if (existingJob != null) {
    existingJob.delete()
    println "[setup] Deleted existing job '${jobName}'"
}

def job = instance.createProject(WorkflowJob, jobName)
def scmDef = new CpsScmFlowDefinition(
    new GitSCM(
        [new UserRemoteConfig("https://github.com/tsprasath/ai-devops.git", null, null, null)],
        [new BranchSpec("*/main")],
        null, null, []
    ),
    "ci/Jenkinsfile.local"
)
scmDef.setLightweight(true)
job.setDefinition(scmDef)
job.save()
println "[setup] Pipeline job '${jobName}' created (SCM: ci/Jenkinsfile.local)"

// ── 3. Credentials (from system properties or env vars) ──
def domain = Domain.global()
def store = SystemCredentialsProvider.getInstance().getStore()

// Read from system properties passed via -Dprop=value
def ocirUser  = System.getProperty("ocir.user",  "PLACEHOLDER_UPDATE_ME")
def ocirToken = System.getProperty("ocir.token", "PLACEHOLDER_UPDATE_ME")
def teamsUrl  = System.getProperty("teams.webhook", "")

// Remove existing creds if re-running
["ocir-credentials", "teams-webhook-url"].each { credId ->
    def existing = store.getCredentials(domain).find { it.id == credId }
    if (existing) {
        store.removeCredentials(domain, existing)
        println "[setup] Removed existing credential '${credId}'"
    }
}

def ocir = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL, "ocir-credentials", "OCI Container Registry",
    ocirUser, ocirToken
)
store.addCredentials(domain, ocir)
println "[setup] Credential 'ocir-credentials' added"

if (teamsUrl) {
    def teamsWebhook = new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL, "teams-webhook-url", "Teams Webhook",
        "webhook", teamsUrl
    )
    store.addCredentials(domain, teamsWebhook)
    println "[setup] Credential 'teams-webhook-url' added"
} else {
    println "[setup] Teams webhook URL not provided — skipping"
}

instance.save()
println "[setup] ✅ ALL DONE — shared lib + job + credentials configured"
