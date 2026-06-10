/**
 * setup-jobs.groovy
 *
 * Ejecutar en: Manage Jenkins -> Script Console
 * Crea 3 jobs de pipeline apuntando a un repo Git local.
 */

import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.plugins.git.GitSCM
import hudson.plugins.git.UserRemoteConfig
import hudson.plugins.git.BranchSpec
import java.util.Collections

def jenkinsInstance = Jenkins.instance

// ============================================================
// 1. CREAR CREDENCIALES DOCKER HUB
// ============================================================
def credentialsDomain = Domain.global()
def credentialsStore = jenkinsInstance.getExtensionList(
    'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
)[0].getStore()

def existingCredentials = credentialsStore.getCredentials(credentialsDomain).find {
    it.id == 'dockerhub-credentials'
}

if (!existingCredentials) {
    def dockerCreds = new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        'dockerhub-credentials',
        'Docker Hub credentials',
        '',
        ''
    )
    credentialsStore.addCredentials(credentialsDomain, dockerCreds)
    println '[OK] Credenciales "dockerhub-credentials" creadas.'
    println '     Ve a: Manage Jenkins -> Credentials -> Global -> dockerhub-credentials'
    println '     y completa usuario + password/token de Docker Hub.'
} else {
    println '[SKIP] Credenciales "dockerhub-credentials" ya existen.'
}

// ============================================================
// 2. CONFIGURAR REPO GIT LOCAL
// ============================================================
def localRepoPath = 'file:///home/rimuru129/Documents/DevOps - Proyecto Kubernetes'

def gitRemoteConfig = new UserRemoteConfig(localRepoPath, null, null, null)
def gitBranchSpec = new BranchSpec('*/main')

def gitSCM = new GitSCM(
    [gitRemoteConfig],
    [gitBranchSpec],
    null,
    null,
    Collections.emptyList()
)

// ============================================================
// 3. CREAR LOS 3 JOBS (Pipeline from SCM)
// ============================================================

def pipelineJobs = [
    [name: 'deploy-full',    jenkinsfile: 'jenkins/Jenkinsfile.deploy',      desc: 'Deploy completo: Build + Kind + K8s'],
    [name: 'push-backend',   jenkinsfile: 'jenkins/Jenkinsfile.push-backend',  desc: 'Push imagen backend a Docker Hub'],
    [name: 'push-frontend',  jenkinsfile: 'jenkins/Jenkinsfile.push-frontend', desc: 'Push imagen frontend a Docker Hub'],
]

pipelineJobs.each { jobDef ->
    def pipelineJob = jenkinsInstance.getItem(jobDef.name)
    if (pipelineJob) {
        println "[SKIP] Job '${jobDef.name}' ya existe."
    } else {
        pipelineJob = jenkinsInstance.createProject(WorkflowJob, jobDef.name)
        pipelineJob.description = jobDef.desc
        pipelineJob.definition = new CpsScmFlowDefinition(gitSCM, jobDef.jenkinsfile)
        pipelineJob.save()
        println "[OK] Job '${jobDef.name}' creado -> ${jobDef.jenkinsfile}"
    }
}

jenkinsInstance.save()

println ''
println '=========================================='
println '  JOBS CREADOS EN JENKINS'
println '=========================================='
println ''
println '  deploy-full   -> Deploy completo (Build + K8s)'
println '  push-backend  -> Push backend a Docker Hub'
println '  push-frontend -> Push frontend a Docker Hub'
println ''
println '  Cada job usa "Pipeline from SCM" apuntando al repo local.'
println '  Haz click en "Build Now" en cada job.'
println '  Los pipelines de push mostraran un modal de credenciales.'
println ''
println '  IMPORTANTE: Configura las credenciales en:'
println '  Manage Jenkins -> Credentials -> Global'
println '  -> dockerhub-credentials (completa usuario y token)'
println '=========================================='
