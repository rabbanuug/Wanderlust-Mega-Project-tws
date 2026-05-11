@Library('Shared') _
pipeline {
    agent {label 'Node'}

    environment {
        SONAR_HOME = tool "Sonar"
        DOCKER_USER = "rabbanug1"
        NVD_API_KEY = credentials('nvd-api-key')
    }

    parameters {
        string(name: 'FRONTEND_DOCKER_TAG', defaultValue: 'latest', description: 'Setting docker image for latest push')
        string(name: 'BACKEND_DOCKER_TAG', defaultValue: 'latest', description: 'Setting docker image for latest push')
    }

    stages {
        stage("Validate Parameters") {
            steps {
                script {
                    if (params.FRONTEND_DOCKER_TAG == '' || params.BACKEND_DOCKER_TAG == '') {
                        error("FRONTEND_DOCKER_TAG and BACKEND_DOCKER_TAG must be provided.")
                    }
                }
            }
        }

        stage("Workspace cleanup") {
            steps {
                script {
                    cleanWs()
                }
            }
        }

        stage('Git: Code Checkout') {
            steps {
                script {
                    code_checkout("https://github.com/rabbanuug/Wanderlust-Mega-Project-tws.git", "main")
                }
            }
        }

        stage("Trivy: Filesystem scan") {
            steps {
                script {
                    trivy_scan()
                }
            }
        }

        stage("OWASP: Dependency check") {
            steps {
                script {
                    owasp_dependency()
                }
            }
        }

        stage("SonarQube: Code Analysis") {
            steps {
                script {
                    sonarqube_analysis("Sonar", "wanderlust", "wanderlust")
                }
            }
        }

        stage("SonarQube: Code Quality Gates") {
            steps {
                script {
                    sonarqube_code_quality()
                }
            }
        }

        stage('Exporting environment variables') {
            // AWS EKS  → updatebackendnew.sh  / updatefrontendnew.sh  (fetches EC2 public IP)
            // Local k3s → updatebackendlocal.sh / updatefrontendlocal.sh (uses localhost)
            parallel {
                stage("Backend env setup") {
                    steps {
                        script {
                            dir("Automations") {
                                sh "bash updatebackendlocal.sh"
                            }
                        }
                    }
                }
                stage("Frontend env setup") {
                    steps {
                        script {
                            dir("Automations") {
                                sh "bash updatefrontendlocal.sh"
                            }
                        }
                    }
                }
            }
        }

        stage("Docker: Setup Buildx") {
            steps {
                sh """
                    docker buildx inspect multiarch > /dev/null 2>&1 \
                        || docker buildx create --name multiarch --driver docker-container --use
                    docker buildx use multiarch
                    docker buildx inspect --bootstrap
                """
            }
        }

        stage("Docker: Login") {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-creds',
                        usernameVariable: 'DOCKER_LOGIN_USER',
                        passwordVariable: 'DOCKER_LOGIN_PASS')]) {
                    sh "echo \$DOCKER_LOGIN_PASS | docker login -u \$DOCKER_LOGIN_USER --password-stdin"
                }
            }
        }

        stage("Docker: Build & Push Images") {
            parallel {
                stage("Backend") {
                    steps {
                        dir('backend') {
                            sh """
                                docker buildx build \
                                    --platform linux/arm64 \
                                    -t ${env.DOCKER_USER}/wanderlust-backend-beta:${params.BACKEND_DOCKER_TAG} \
                                    --push .
                            """
                        }
                    }
                }
                stage("Frontend") {
                    steps {
                        dir('frontend') {
                            sh """
                                docker buildx build \
                                    --platform linux/arm64 \
                                    -t ${env.DOCKER_USER}/wanderlust-frontend-beta:${params.FRONTEND_DOCKER_TAG} \
                                    --push .
                            """
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: '*.xml', followSymlinks: false
            build job: "Wanderlust-CD", parameters: [
                string(name: 'FRONTEND_DOCKER_TAG', value: "${params.FRONTEND_DOCKER_TAG}"),
                string(name: 'BACKEND_DOCKER_TAG', value: "${params.BACKEND_DOCKER_TAG}")
            ]
        }
    }
}
