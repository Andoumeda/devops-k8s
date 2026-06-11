pipeline {
    agent any

    parameters {
        booleanParam(
            name: 'PUSH_IMAGES',
            defaultValue: false,
            description: 'Publicar las imágenes en Docker Hub (requiere credencial dockerhub-credentials)'
        )
    }

    environment {
        NAMESPACE = 'devops-lab'
        MANIFESTS_DIR = 'manifests'
        FRONT_PORT = '8081'   // 8080 lo ocupa Jenkins
        BACK_PORT = '3000'
    }

    stages {
        // Stage 1 - Checkout: obtención del código fuente desde Git
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        // Stage 2 - Build: preparación de la aplicación
        stage('Build') {
            steps {
                dir('backend') {
                    sh 'npm install'
                }
                dir('frontend') {
                    sh 'test -f index.html && test -f app.js && test -f style.css'
                }
            }
        }

        // Stage 3 - Docker Build
        stage('Docker Build') {
            steps {
                sh 'docker build -t todo-backend ./backend'
                sh 'docker build -t todo-frontend ./frontend'
            }
        }

        // Stage 4 - Push de imagen a Docker Hub (opcional por parámetro)
        stage('Push de Imagen') {
            when { expression { params.PUSH_IMAGES } }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo ${DOCKER_PASS} | docker login -u ${DOCKER_USER} --password-stdin
                        docker tag todo-backend ${DOCKER_USER}/todo-backend:latest
                        docker tag todo-frontend ${DOCKER_USER}/todo-frontend:latest
                        docker push ${DOCKER_USER}/todo-backend:latest
                        docker push ${DOCKER_USER}/todo-frontend:latest
                        docker logout
                    '''
                }
            }
        }

        // Stage 5 - Deploy en Kubernetes (disparado manualmente con Build Now)
        stage('Load Images into Kind') {
            steps {
                sh '''
                    CLUSTER=$(kind get clusters | head -n1)
                    kind load docker-image todo-backend --name "$CLUSTER"
                    kind load docker-image todo-frontend --name "$CLUSTER"
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh """
                    kubectl apply -f ${MANIFESTS_DIR}/namespace.yml
                    kubectl apply -f ${MANIFESTS_DIR}/db-secret.yml
                    kubectl apply -f ${MANIFESTS_DIR}/back-config.yml
                    kubectl apply -f ${MANIFESTS_DIR}/db-config.yml
                    kubectl apply -f ${MANIFESTS_DIR}/db-deploy.yml
                    kubectl apply -f ${MANIFESTS_DIR}/back-deploy.yml
                    kubectl apply -f ${MANIFESTS_DIR}/front-deploy.yml
                    kubectl apply -f ${MANIFESTS_DIR}/db-svc.yml
                    kubectl apply -f ${MANIFESTS_DIR}/back-svc.yml
                    kubectl apply -f ${MANIFESTS_DIR}/front-svc.yml
                    kubectl rollout restart deployment/backend deployment/frontend -n ${NAMESPACE}
                    kubectl apply -f ${MANIFESTS_DIR}/back-servicemonitor.yml || echo '[WARN] ServiceMonitor no aplicado: instalar kube-prometheus-stack (install-all.sh paso 8)'
                """
            }
        }

        stage('Wait for Pods Ready') {
            steps {
                sh """
                    kubectl wait --for=condition=ready pod -l app=db -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/backend -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/frontend -n ${NAMESPACE} --timeout=120s
                """
            }
        }

        stage('Port-Forward') {
            steps {
                sh '''
                    kill $(cat /tmp/pf-frontend.pid 2>/dev/null) 2>/dev/null || true
                    kill $(cat /tmp/pf-backend.pid 2>/dev/null) 2>/dev/null || true
                    sleep 1

                    JENKINS_NODE_COOKIE=dontKillMe nohup kubectl port-forward -n ${NAMESPACE} svc/frontend-service ${FRONT_PORT}:80 > /tmp/pf-frontend.log 2>&1 &
                    echo $! > /tmp/pf-frontend.pid

                    JENKINS_NODE_COOKIE=dontKillMe nohup kubectl port-forward -n ${NAMESPACE} svc/backend-service ${BACK_PORT}:3000 > /tmp/pf-backend.log 2>&1 &
                    echo $! > /tmp/pf-backend.pid

                    sleep 3
                '''
            }
        }

        // Stage 7 - Validación: pods activos y aplicación accesible
        stage('Validación') {
            steps {
                sh '''
                    echo "--- Pods activos ---"
                    kubectl get pods -n ${NAMESPACE}

                    echo "--- Health check ---"
                    curl -fsS http://localhost:${BACK_PORT}/health

                    echo ""
                    echo "--- Version ---"
                    curl -fsS http://localhost:${BACK_PORT}/version

                    echo ""
                    echo "--- Frontend accesible ---"
                    curl -fsS -o /dev/null -w "HTTP %{http_code}\\n" http://localhost:${FRONT_PORT}

                    echo "==========================================="
                    echo " Frontend:  http://localhost:${FRONT_PORT}"
                    echo " Backend:   http://localhost:${BACK_PORT}"
                    echo " API Docs:  http://localhost:${BACK_PORT}/api-docs"
                    echo " Health:    http://localhost:${BACK_PORT}/health"
                    echo " Version:   http://localhost:${BACK_PORT}/version"
                    echo " Metrics:   http://localhost:${BACK_PORT}/metrics"
                    echo "==========================================="
                '''
            }
        }
    }

    post {
        success {
            echo 'Deploy completado y validado exitosamente.'
        }
        failure {
            echo 'El pipeline falló.'
            sh '''
                kill $(cat /tmp/pf-frontend.pid 2>/dev/null) 2>/dev/null || true
                kill $(cat /tmp/pf-backend.pid 2>/dev/null) 2>/dev/null || true
            '''
        }
    }
}
