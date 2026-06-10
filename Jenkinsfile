pipeline {
    agent any

    environment {
        NAMESPACE = 'devops-lab'
        MANIFESTS_DIR = 'manifests'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Backend Install') {
            steps {
                dir('backend') {
                    sh 'npm install'
                }
            }
        }

        stage('Frontend Verify') {
            steps {
                dir('frontend') {
                    sh 'test -f index.html && test -f app.js && test -f style.css'
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                sh 'docker build -t todo-backend ./backend'
                sh 'docker build -t todo-frontend ./frontend'
            }
        }

        stage('Load Images into Kind') {
            steps {
                sh 'kind load docker-image todo-backend'
                sh 'kind load docker-image todo-frontend'
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
                """
            }
        }

        stage('Wait for Pods Ready') {
            steps {
                sh """
                    kubectl wait --for=condition=ready pod -l app=db -n ${NAMESPACE} --timeout=120s
                    kubectl wait --for=condition=ready pod -l app=backend -n ${NAMESPACE} --timeout=120s
                    kubectl wait --for=condition=ready pod -l app=frontend -n ${NAMESPACE} --timeout=120s
                """
            }
        }

        stage('Port-Forward & Open Browser') {
            steps {
                sh '''
                    nohup kubectl port-forward -n devops-lab svc/frontend-service 8080:80 > /tmp/pf-frontend.log 2>&1 &
                    echo $! > /tmp/pf-frontend.pid

                    nohup kubectl port-forward -n devops-lab svc/backend-service 3000:3000 > /tmp/pf-backend.log 2>&1 &
                    echo $! > /tmp/pf-backend.pid

                    sleep 3

                    xdg-open http://localhost:8080 > /dev/null 2>&1 || true
                    xdg-open http://localhost:3000/api-docs > /dev/null 2>&1 || true

                    echo "==========================================="
                    echo " Frontend:  http://localhost:8080"
                    echo " Backend:   http://localhost:3000"
                    echo " API Docs:  http://localhost:3000/api-docs"
                    echo "==========================================="
                    echo "Port-forwards activos en background."
                    echo "Para detenerlos:"
                    echo "  kill \$(cat /tmp/pf-frontend.pid)"
                    echo "  kill \$(cat /tmp/pf-backend.pid)"
                '''
            }
        }
    }

    post {
        success {
            echo 'Deploy completado exitosamente.'
        }
        failure {
            echo 'El build fallo.'
            sh '''
                kill $(cat /tmp/pf-frontend.pid 2>/dev/null) 2>/dev/null || true
                kill $(cat /tmp/pf-backend.pid 2>/dev/null) 2>/dev/null || true
            '''
        }
    }
}
