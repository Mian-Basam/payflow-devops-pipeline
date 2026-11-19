# CI Lab Walkthrough

The lab runs every CI component locally with Docker Compose so the
pipelines can actually be executed.

```bash
make ci-lab-up      # first build of the Jenkins image takes a few minutes
```

| Service | URL | Notes |
|---|---|---|
| Gitea (Git server, Bitbucket stand-in) | http://localhost:3001 | first registered user becomes admin |
| Jenkins | http://localhost:8090 | admin / admin, fully configured by JCasC |
| TeamCity | http://localhost:8111 | first-start wizard (internal DB is fine for a lab) |
| Docker registry | http://localhost:5000/v2/_catalog | no auth (lab only) |

## 1. Put the code in Gitea

1. Register user **devops**.
2. Create repository **payflow-devops-pipeline** (empty).
3. Push:

```bash
git remote add lab http://localhost:3001/devops/payflow-devops-pipeline.git
git push lab main
```

## 2. Jenkins: configured entirely as code

`ci-lab/jenkins/` contains:

* `Dockerfile`: Jenkins LTS plus the Docker CLI, Python, ShellCheck and Ansible; plugins from `plugins.txt` are installed at build time.
* `casc/jenkins.yaml`: admin user, credentials (`registry-creds`), system message, and the **payflow-pipeline** job defined with Job DSL.

Open Jenkins and you will see **payflow-pipeline** without having clicked
anything. Run *Build with Parameters* (`SKIP_DEPLOY` defaults to true in
the lab). Expected stage view:

```
Checkout ✔  Lint & Unit tests ✔  Build image ✔  Security scan ✔  Push image ✔  (deploy stages skipped)
```

Then check the registry: `curl localhost:5000/v2/payflow-api/tags/list`.

Change the configuration by editing `casc/jenkins.yaml` and restarting
Jenkins (`docker compose restart jenkins`). The controller is reproducible
from git, which is the point of configuration as code.

## 3. TeamCity: Kotlin DSL

1. Finish the setup wizard and create an admin user.
2. **Agents → Unauthorized → lab-agent-1 → Authorize**.
3. **Create project → From a repository URL**: `http://gitea:3000/devops/payflow-devops-pipeline.git`.
4. TeamCity detects `.teamcity/settings.kts`. Choose **Import settings from VCS**.
5. Three build configurations appear, linked as a chain:
   `1. Lint & Test → 2. Build & Push Image → 3. Deploy to Staging`.
6. Set `env.REGISTRY` to `localhost:5000` at the project level and run build 2.
   TeamCity automatically runs build 1 first (snapshot dependency).

## 4. Break it on purpose

| Experiment | Expected result |
|---|---|
| Make a test fail and push | Jenkins stage *Lint & Unit tests* red; JUnit report shows the test |
| Add `exit 1` to `scripts/smoke_test.sh` | Lint passes; smoke stage fails |
| Stop the registry: `docker compose stop registry` | *Push image* fails with a connection error, which is an infra failure, not code |
| Fill the agent disk | Builds fail with `no space left on device` (see the triage table) |

Practising these makes failed-build triage routine.

## Clean up

```bash
make ci-lab-down
cd ci-lab && docker compose down -v    # also delete data
```
