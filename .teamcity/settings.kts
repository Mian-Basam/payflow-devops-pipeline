import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.dockerSupport
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

/*
 * TeamCity versioned settings (Kotlin DSL).
 * Build chain:  Test  ->  Build & Push image  ->  Deploy to staging
 * VCS root is the Bitbucket repo configured in the project.
 */
version = "2024.03"

project {
    params {
        param("env.REGISTRY", "registry.local:5000")
        param("env.IMAGE_NAME", "payflow-api")
    }
    buildType(Test)
    buildType(BuildImage)
    buildType(DeployStaging)
}

object Test : BuildType({
    name = "1. Lint & Test"
    vcs { root(DslContext.settingsRoot) }

    steps {
        script {
            name = "Unit tests"
            scriptContent = """
                python3 -m venv .venv && . .venv/bin/activate
                pip install -q -r requirements-dev.txt
                ruff check app tests
                pytest -q --junitxml=reports/junit.xml
                shellcheck scripts/*.sh
            """.trimIndent()
        }
    }
    triggers { vcs { branchFilter = "+:*" } }
    features {
        feature {
            type = "xml-report-plugin"
            param("xmlReportParsing.reportType", "junit")
            param("xmlReportParsing.reportDirs", "reports/*.xml")
        }
    }
})

object BuildImage : BuildType({
    name = "2. Build & Push Image"
    vcs { root(DslContext.settingsRoot) }
    buildNumberPattern = "%build.counter%"

    steps {
        script {
            name = "docker build + push"
            scriptContent = """
                TAG=%build.number%-${'$'}(git rev-parse --short HEAD)
                docker build --build-arg APP_VERSION=${'$'}TAG -t ${'$'}REGISTRY/${'$'}IMAGE_NAME:${'$'}TAG .
                docker push ${'$'}REGISTRY/${'$'}IMAGE_NAME:${'$'}TAG
                echo "##teamcity[setParameter name='env.IMAGE_TAG' value='${'$'}TAG']"
            """.trimIndent()
        }
    }
    dependencies { snapshot(Test) { onDependencyFailure = FailureAction.FAIL_TO_START } }
    features { dockerSupport { cleanupPushedImages = true } }
})

object DeployStaging : BuildType({
    name = "3. Deploy to Staging"
    type = Type.DEPLOYMENT
    vcs { root(DslContext.settingsRoot) }

    steps {
        script {
            name = "ansible deploy"
            scriptContent = """
                ansible-playbook -i ansible/inventory.ini ansible/site.yml \
                  --limit staging -e app_image=${'$'}REGISTRY/${'$'}IMAGE_NAME:%dep.${BuildImage.id}.env.IMAGE_TAG%
                ./scripts/smoke_test.sh http://app01.stg.local
            """.trimIndent()
        }
    }
    dependencies {
        snapshot(BuildImage) {}
    }
    triggers { vcs { branchFilter = "+:main" } }
})
