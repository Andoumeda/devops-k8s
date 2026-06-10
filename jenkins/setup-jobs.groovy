/**
 * setup-jobs.groovy
 *
 * Ejecutar en: Manage Jenkins -> Script Console
 * Crea 3 jobs de pipeline "from SCM" apuntando al repo Git local.
 *
 * Requisitos previos (una sola vez, en una terminal):
 *   sudo usermod -aG docker jenkins
 *   sudo -u jenkins git config --global --add safe.directory '*'
 *   sudo systemctl restart jenkins
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
// 1. CREAR CREDENCIALES DOCKER HUB (vacías, completar en la UI)
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
// OJO: la rama del repo es "master" (no "main").
def localRepoPath = 'file:///home/rimuru129/Documents/DevOps - Proyecto Kubernetes'

def gitSCM = new GitSCM(
    [new UserRemoteConfig(localRepoPath, null, null, null)],
    [new BranchSpec('*/master')],
    null,
    null,
    Collections.emptyList()
)

// ============================================================
// 3. CREAR LOS 3 JOBS (Pipeline from SCM)
// ============================================================

def pipelineJobs = [
    [name: 'deploy-full',   jenkinsfile: 'Jenkinsfile',                       desc: 'Pipeline completo: Checkout + Build + Docker + Deploy K8s + Validación'],
    [name: 'push-backend',  jenkinsfile: 'jenkins/Jenkinsfile.push-backend',  desc: 'Push imagen backend a Docker Hub'],
    [name: 'push-frontend', jenkinsfile: 'jenkins/Jenkinsfile.push-frontend', desc: 'Push imagen frontend a Docker Hub'],
]

pipelineJobs.each { jobDef ->
    def pipelineJob = jenkinsInstance.getItem(jobDef.name)
    if (pipelineJob) {
        pipelineJob.definition = new CpsScmFlowDefinition(gitSCM, jobDef.jenkinsfile)
        pipelineJob.save()
        println "[OK] Job '${jobDef.name}' ya existía, definición actualizada -> ${jobDef.jenkinsfile}"
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
println '  deploy-full   -> Pipeline completo (botón de deploy manual)'
println '  push-backend  -> Push backend a Docker Hub'
println '  push-frontend -> Push frontend a Docker Hub'
println ''
println '  Cada job usa "Pipeline from SCM" sobre el repo local (rama master).'
println '  Recordá hacer "git commit" para que los jobs vean los cambios.'
println '  Haz click en "Build Now" en cada job.'
println ''
println '  IMPORTANTE: Configura las credenciales en:'
println '  Manage Jenkins -> Credentials -> Global'
println '  -> dockerhub-credentials (completa usuario y token)'
println '=========================================='
