# CI/CD Pipelines

## Stage by stage

### 1. Lint and unit tests
`ruff` (Python), `shellcheck` (Bash) and `pytest` with a JUnit XML report.
Jenkins publishes it with `junit`, TeamCity with the XML report feature,
and Bitbucket reads `test-results/`. The report shows **which test failed**
in the CI UI without digging through logs.

### 2. Build image
`docker build --build-arg APP_VERSION=$TAG -t $REGISTRY/payflow-api:$TAG .`
Multi-stage keeps build tools out of the runtime image.

### 3. Security scan
Trivy scans OS packages and Python dependencies. `--ignore-unfixed` avoids
failing on CVEs nobody can fix yet. `--exit-code 1` makes the stage fail.
GitHub Actions also runs a **config scan** of the Dockerfile, Kubernetes
manifests and Compose file.

### 4. Push
Skipped for pull requests (`when { not { changeRequest() } }`), so
unmerged code never reaches the registry. Credentials come from the CI
credential store.

### 5. Approve (production only)
Jenkins `input` pauses the build until a person clicks **Deploy**.

### 6. Deploy
`ansible-playbook ... --limit $TARGET_ENV -e app_image=$IMAGE` runs
`deploy.sh` on each host (canary, health check, promote, rollback). See
[DEPLOYMENT.md](DEPLOYMENT.md).

### 7. Smoke test
`scripts/smoke_test.sh` creates, reads and settles a transaction through
the real entry point.

## The same concepts in each tool

| Concept | Jenkins | TeamCity | Bitbucket Pipelines |
|---|---|---|---|
| Pipeline definition in git | `Jenkinsfile` | `.teamcity/settings.kts` (versioned settings) | `bitbucket-pipelines.yml` |
| Unit of work | `stage` | Build configuration (build type) | `step` |
| Ordering | stage order | **snapshot dependencies** (build chain) | step order |
| Pass data between steps | `env`, `stash`, artifacts | `##teamcity[setParameter]`, artifact dependencies | artifacts |
| Secrets | Credentials + `withCredentials` | password parameters | secured repository variables |
| Approval | `input` | deployment build type / manual trigger | `trigger: manual` on a deployment step |
| Trigger | SCM polling / webhook | VCS trigger | push / PR |
| Agents | `agent any` / labels | agent requirements | `image:` + `services: [docker]` |
| Configuration as code | **JCasC + Job DSL** (`ci-lab/jenkins/casc`) | Kotlin DSL | YAML |

## Branch strategy

* Pull requests run **lint and test** only (Bitbucket `pull-requests`, Jenkins `changeRequest()`).
* Merges to `main` run the full chain to **staging**.
* Production is the same build, promoted with `TARGET_ENV=production` and approval.

## Troubleshooting a failed build

1. **Read the first error, not the last.** Later errors are often consequences.
2. Identify the stage, then use the triage table in [RUNBOOK.md](RUNBOOK.md#failed-build).
3. Reproduce locally with the same command (each stage is a plain shell command: `make lint test`, `docker build .`).
4. Check what changed: `git log <last-green>..<red>`, plus dependency and base image updates.
5. Infrastructure vs code: if the same commit passed before, suspect the agent (disk full, Docker daemon, network, expired credentials).
6. Escalate to the dev team with the failing test name, log excerpt and commit, or fix the infrastructure yourself.

Common causes seen in practice:

| Symptom | Likely cause |
|---|---|
| `No space left on device` on agent | Old images/build cache: `docker system prune -af` on the agent |
| `unauthorized` on push | Registry credentials expired or wrong credentials ID |
| Tests pass locally, fail in CI | Missing env var, different Python version, test order dependency |
| Trivy fails suddenly with no code change | New CVE published for a base image package: rebuild on a patched base image |
| `Permission denied` on `/var/run/docker.sock` | CI user not in the `docker` group |
