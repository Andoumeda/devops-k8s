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

def jenkins = Jenkins.instance

// ============================================================
// 1. CREAR CREDENCIALES DOCKER HUB
// ============================================================
def domain = Domain.global()
def store = jenkins.getExtensionList(
    'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
)[0].getStore()

def existing = store.getCredentials(domain).find {
    it.id == 'dockerhub-credentials'
}

if (!existing) {
    def creds = new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        'dockerhub-credentials',
        'Docker Hub credentials',
        '',
        ''
    )
    store.addCredentials(domain, creds)
    println '[OK] Credenciales "dockerhub-credentials" creadas.'
    println '     Ve a: Manage Jenkins -> Credentials -> Global -> dockerhub-credentials'
    println '     y completa usuario + password/token de Docker Hub.'
} else {
    println '[SKIP] Credenciales "dockerhub-credentials" ya existen.'
}

// ============================================================
// 2. CONFIGURAR REPO GIT LOCAL
// ============================================================
def repoPath = 'file:///home/rimuru129/Documents/DevOps - Proyecto Kubernetes'

def userRemoteConfig = new UserRemoteConfig(repoPath, null, null, null)
def branchSpec = new BranchSpec('*/main')

def scm = new GitSCM(
    [userRemoteConfig],
    [branchSpec],
    null,
    null,
    Collections.emptyList()
)

// ============================================================
// 3. CREAR LOS 3 JOBS (Pipeline from SCM)
// ============================================================

def jobs = [
    [name: 'deploy-full',    jenkinsfile: 'jenkins/Jenkinsfile.deploy',      desc: 'Deploy completo: Build + Kind + K8s'],
    [name: 'push-backend',   jenkinsfile: 'jenkins/Jenkinsfile.push-backend',  desc: 'Push imagen backend a Docker Hub'],
    [name: 'push-frontend',  jenkinsfile: 'jenkins/Jenkinsfile.push-frontend', desc: 'Push imagen frontend a Docker Hub'],
]

jobs.each { jobDef ->
    def job = jenkins.getItem(jobDef.name)
    if (job) {
        println "[SKIP] Job '${jobDef.name}' ya existe."
    } else {
        job = jenkins.createProject(WorkflowJob, jobDef.name)
        job.description = jobDef.desc
        job.definition = new CpsScmFlowDefinition(scm, jobDef.jenkinsfile)
        job.save()
        println "[OK] Job '${jobDef.name}' creado -> ${jobDef.jenkinsfile}"
    }
}

jenkins.save()

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
