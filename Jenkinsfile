// Declarative pipeline: lint -> test -> build image -> push -> deploy (Ansible) -> smoke test
pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    parameters {
        choice(name: 'TARGET_ENV', choices: ['staging', 'production'], description: 'Inventory group to deploy to')
        booleanParam(name: 'SKIP_DEPLOY', defaultValue: false, description: 'Build and test only')
    }

    environment {
        REGISTRY   = "${env.REGISTRY ?: 'registry.local:5000'}"   // on-prem registry (CI lab sets localhost:5000)
        IMAGE_NAME = 'payflow-api'
        IMAGE_TAG  = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
        IMAGE      = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Lint & Unit tests') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install -q -r requirements-dev.txt
                    ruff check app tests
                    pytest -q --junitxml=reports/junit.xml
                '''
                sh 'shellcheck scripts/*.sh'
            }
            post { always { junit 'reports/junit.xml' } }
        }

        stage('Build image') {
            steps {
                sh "docker build --build-arg APP_VERSION=${IMAGE_TAG} -t ${IMAGE} ."
            }
        }

        stage('Security scan (Trivy)') {
            steps {
                // Fail the build on fixable HIGH/CRITICAL vulnerabilities in the image
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                      -v trivy-cache:/root/.cache aquasec/trivy:0.56.2 image \
                      --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
                      --format table "$IMAGE" | tee reports/trivy.txt
                '''
            }
            post { always { archiveArtifacts artifacts: 'reports/trivy.txt', allowEmptyArchive: true } }
        }

        stage('Push image') {
            when { not { changeRequest() } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry-creds',
                                 usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
                    sh '''
                        echo "$REG_PASS" | docker login "$REGISTRY" -u "$REG_USER" --password-stdin
                        docker push "$IMAGE"
                    '''
                }
            }
        }

        stage('Approve production') {
            when { expression { params.TARGET_ENV == 'production' && !params.SKIP_DEPLOY } }
            steps { input message: "Deploy ${IMAGE} to production?", ok: 'Deploy' }
        }

        stage('Deploy (Ansible)') {
            when { expression { !params.SKIP_DEPLOY } }
            steps {
                sshagent(credentials: ['deploy-ssh-key']) {
                    sh """
                        ansible-playbook -i ansible/inventory.ini ansible/site.yml \
                          --limit ${params.TARGET_ENV} \
                          -e app_image=${IMAGE}
                    """
                }
            }
        }

        stage('Smoke test') {
            when { expression { !params.SKIP_DEPLOY } }
            steps {
                script {
                    def host = params.TARGET_ENV == 'production' ? 'app01.prod.local' : 'app01.stg.local'
                    sh "./scripts/smoke_test.sh http://${host}"
                }
            }
        }
    }

    post {
        success { echo "Released ${IMAGE} to ${params.TARGET_ENV}" }
        failure {
            echo 'Build failed - see console output and docs/RUNBOOK.md#failed-build'
            // mail to: 'devops@example.com', subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}", body: env.BUILD_URL
        }
        always { sh 'docker image prune -f || true' }
    }
}
