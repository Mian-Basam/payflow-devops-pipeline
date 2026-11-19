# PayFlow: End-to-End CI/CD and Release Engineering

[![CI](https://github.com/Mian-Basam/payflow-devops-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/Mian-Basam/payflow-devops-pipeline/actions)
![Jenkins](https://img.shields.io/badge/Jenkins-JCasC-D24939?logo=jenkins&logoColor=white)
![TeamCity](https://img.shields.io/badge/TeamCity-Kotlin%20DSL-000000?logo=teamcity&logoColor=white)
![Bitbucket](https://img.shields.io/badge/Bitbucket-Pipelines-0052CC?logo=bitbucket&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326CE5?logo=kubernetes&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy-scanned-1904DA)
![Level](https://img.shields.io/badge/level-advanced-red)

> The **capstone** of the portfolio: a complete delivery system for a
> fintech-style transaction service, from `git push` to a tested,
> scanned, approved and monitored release on Linux servers **or**
> Kubernetes, with a **runnable local CI lab**.
>
> **Portfolio level 5 of 5**: brings together Linux (1), Docker (2), Ansible (3) and monitoring (4).

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Purpose of the project](#2-purpose-of-the-project)
3. [Architecture](#3-architecture)
4. [Pipeline stages](#4-pipeline-stages)
5. [Tools and technologies](#5-tools-and-technologies)
6. [File structure](#6-file-structure)
7. [How to run: `run.sh`](#7-how-to-run-runsh)
8. [Quick start](#8-quick-start)
9. [Run the pipelines for real (CI lab)](#9-run-the-pipelines-for-real-ci-lab)
10. [Deployment strategies](#10-deployment-strategies)
11. [API reference](#11-api-reference)
12. [Monitoring](#12-monitoring)
13. [Testing](#13-testing)
14. [Security](#14-security)
15. [Skills demonstrated](#15-skills-demonstrated)
16. [Further documentation](#16-further-documentation)

---

## 1. Introduction

**PayFlow** is a small Flask API that creates, reads and settles payment
transactions. It stands in for a real fintech microservice; the
application is kept simple on purpose, because the subject of this
project is **everything around it**: how a change is built, tested,
secured, released, rolled back and monitored.

The delivery flow:

**Bitbucket / Gitea → Jenkins or TeamCity → lint + unit tests → Docker
image → Trivy security scan → private registry → manual approval →
Ansible deployment with canary and automatic rollback → smoke test →
Prometheus / Grafana monitoring**

The same image also deploys to **Kubernetes** (a local `kind` cluster)
with rolling updates, probes, autoscaling and one-command rollback.

The same pipeline is written for **four CI tools** (Jenkins, TeamCity,
Bitbucket Pipelines, GitHub Actions) to show that the concepts carry over,
and the `ci-lab/` folder starts Jenkins, TeamCity, a Git server and a
registry locally so the pipelines can actually be executed.

## 2. Purpose of the project

**Problem it solves.** Manual releases are slow and risky: someone builds
on their laptop, copies files to a server, restarts the service, and finds
out from users that it is broken. A good delivery pipeline makes every
release **automatic, repeatable, verified and reversible**.

**Goals**

| Goal | How the project meets it |
|---|---|
| Every change is tested | Lint, 11 unit tests and static checks run on every push |
| Build once, deploy the same artifact everywhere | One Docker image tagged with the build/commit SHA, pushed to a registry |
| Ship secure images | Non-root multi-stage image; Trivy fails the build on fixable HIGH/CRITICAL CVEs |
| Control production releases | Manual approval gate before production |
| Release without breaking users | Canary on a second port, health checks, automatic rollback; Kubernetes rolling update with `maxUnavailable: 0` |
| Know it works after deploy | Smoke test creates, reads and settles a real transaction |
| See problems in production | Prometheus metrics, alert rules and a Grafana dashboard |
| Be tool-agnostic | Same stages in Jenkins, TeamCity, Bitbucket and GitHub Actions |

**Who it is for:** engineers learning CI/CD, release engineering and
Kubernetes, and anyone preparing for DevOps/platform roles that use
Jenkins, TeamCity or Bitbucket on-premises.

**Where it fits:** it combines everything from the earlier projects:
Bash ops scripts (1), container design (2), Ansible server configuration
(3) and Prometheus/Grafana monitoring (4).

## 3. Architecture

```
 Developer ── git push ──▶ Bitbucket / Gitea
                               │ webhook / poll
                               ▼
          ┌──────────────── CI server (Jenkins or TeamCity) ────────────────┐
          │ 1 Lint & unit tests   ruff · pytest (JUnit) · shellcheck        │
          │ 2 Build image         multi-stage, non-root, tagged build-sha   │
          │ 3 Security scan       Trivy: fail on fixable HIGH/CRITICAL      │
          │ 4 Push                private registry (registry.local:5000)    │
          │ 5 Approve             manual gate for production                │
          │ 6 Deploy              Ansible → canary → health → promote       │
          │ 7 Smoke test          create → read → settle a transaction      │
          └───────────────────────────────┬─────────────────────────────────┘
                                          │
              ┌───────────────────────────┴───────────────────────────┐
              ▼                                                       ▼
   On-prem Linux servers (VMs)                           Kubernetes (kind / any cluster)
   nginx → payflow-api container                         Deployment ×2 → Service (NodePort)
   deploy.sh: canary :8001 → live :8000                  rolling update, probes, HPA,
   automatic rollback, deploy history                    `rollout undo`
              │                                                       │
              └──────────── Prometheus scrape /metrics ───────────────┘
                                   │
                         Grafana dashboard + alert rules
```

Full detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## 4. Pipeline stages

| # | Stage | Jenkins | TeamCity | Bitbucket | GitHub Actions |
|---|---|---|---|---|---|
| 1 | Lint + unit tests + JUnit report | ✅ | ✅ build 1 | ✅ | ✅ |
| 2 | Build image (tag = build-sha) | ✅ | ✅ build 2 | ✅ | ✅ |
| 3 | Trivy vulnerability scan | ✅ | – | – | ✅ (+ IaC scan) |
| 4 | Push to registry | ✅ (not on PRs) | ✅ | ✅ | – |
| 5 | Manual approval for production | ✅ `input` | deployment build type | `deployment:` env | – |
| 6 | Deploy with Ansible | ✅ | ✅ build 3 | ✅ | – |
| 7 | Smoke test | ✅ | ✅ | – | ✅ |
| – | Container + full stack + Kubernetes tests | – | – | – | ✅ |

The same logic is expressed in four CI tools on purpose, to show the
concepts carry over: stages, artifacts, credentials, approvals, and
snapshot dependencies. Explained in [docs/CI_CD.md](docs/CI_CD.md).

## 5. Tools and technologies

### Required to run

| Tool | Version | Used for | Install |
|---|---|---|---|
| Python | 3.12 (3.10+ works) | the API and its tests | python.org / `brew install python` |
| Docker Engine / Docker Desktop | 24+ | image build, app stack, Trivy, CI lab | [docs.docker.com](https://docs.docker.com/get-docker/) |
| Docker Compose plugin | v2 | app stack and CI lab | included with Docker Desktop |
| curl | any | smoke test, health checks | preinstalled |
| git | any | image tags, CI lab | preinstalled |

About **2 GB** free RAM for the app stack; about **6 GB** more for the CI
lab (Jenkins + TeamCity).

### Optional, per feature

| Tool | Needed for | Install |
|---|---|---|
| kind + kubectl | Kubernetes deploy (`./run.sh k8s`) | `brew install kind kubectl` |
| Ansible 2.15+ | `./run.sh validate`, `./run.sh deploy-vagrant` | `pip install ansible` |
| Vagrant + VirtualBox | the `app01` VM for Ansible deploys | vagrantup.com, virtualbox.org |
| Trivy | image scan (`./run.sh scan`) | nothing to install: runs as a Docker image |

### Required to develop and test

| Tool | Used for | Install |
|---|---|---|
| pytest, ruff | unit tests, Python lint | `./run.sh setup` (creates `.venv`) |
| ShellCheck | script lint | `brew install shellcheck` / `apt install shellcheck` |
| yamllint | YAML lint | `pip install yamllint` |
| hadolint, kubeconform, promtool | extra static checks in CI | optional locally |

### Technology stack

| Category | Technologies |
|---|---|
| Application | Python 3.12, Flask 3, Gunicorn, prometheus-client, JSON logging |
| Containers | Docker (multi-stage, non-root, HEALTHCHECK), Docker Compose, Docker registry |
| CI/CD | Jenkins (declarative pipeline, JCasC, Job DSL), TeamCity (Kotlin DSL), Bitbucket Pipelines, GitHub Actions, Gitea |
| Security | Trivy (image + IaC scan), hadolint, credential stores |
| Deployment | Ansible (roles: common, docker, app), Bash canary deploy with rollback, Vagrant |
| Kubernetes | Deployment, Service, ConfigMap, HPA, Namespace, kustomize, kind |
| Web / proxy | Nginx |
| Monitoring | Prometheus, alert rules, Grafana (provisioned dashboard) |
| Quality | pytest, ruff, ShellCheck, yamllint |

## 6. File structure

```
05-payflow-devops-pipeline/
├── run.sh                                # ★ single entry point: ./run.sh help
├── Makefile                              # make install | test | up | smoke | k8s-apply | ci-lab-up ...
├── README.md                             # this document
│
├── app/                                  # the application
│   ├── __init__.py
│   └── main.py                           # Flask API: transactions, /health, /ready, /metrics, JSON logs
├── tests/
│   ├── __init__.py
│   └── test_app.py                       # 11 unit tests (lifecycle, validation, metrics)
├── requirements.txt                      # runtime: flask, prometheus-client, gunicorn
├── requirements-dev.txt                  # + pytest, ruff
│
├── Dockerfile                            # multi-stage build, non-root (UID 10001), HEALTHCHECK
├── .dockerignore
├── docker-compose.yml                    # local "mini data center": api + nginx + Prometheus + Grafana
├── nginx/
│   └── nginx.conf                        # reverse proxy; blocks /metrics from public traffic
│
├── Jenkinsfile                           # declarative pipeline: lint → test → build → scan → push → approve → deploy → smoke
├── .teamcity/
│   └── settings.kts                      # TeamCity Kotlin DSL: build chain with snapshot dependencies
├── bitbucket-pipelines.yml               # Bitbucket: test, build & push, staging/production deployments
├── .github/workflows/ci.yml              # GitHub Actions: tests, image, Trivy, full stack, Kubernetes
│
├── ci-lab/                               # run the pipelines locally
│   ├── docker-compose.yml                # Jenkins :8090, TeamCity server + agent :8111, Gitea :3001, registry :5000
│   ├── README.md
│   └── jenkins/
│       ├── Dockerfile                    # Jenkins + Docker CLI, Python, ShellCheck, Ansible
│       ├── plugins.txt                   # plugins baked into the image
│       └── casc/jenkins.yaml             # Jenkins Configuration as Code + Job DSL (job pre-created)
│
├── scripts/
│   ├── deploy.sh                         # canary on :8001 → promote to :8000 → auto-rollback, deploy history
│   ├── healthcheck.sh                    # polls /health and /ready with retries
│   ├── smoke_test.sh                     # create → read → settle a transaction
│   ├── k8s_deploy.sh                     # build, load into kind, apply, verify; --rollback
│   ├── server_health.sh                  # Linux server triage report
│   └── log_scan.sh                       # summarise errors in JSON logs
│
├── ansible/                              # server provisioning and deployment
│   ├── site.yml                          # provision + deploy playbook
│   ├── inventory.ini                     # on-prem hosts (staging / production)
│   ├── inventory.vagrant.ini             # local VM from the Vagrantfile
│   ├── group_vars/all.yml                # app name, image, ports, deploy user, packages, firewall
│   ├── requirements.yml                  # Ansible collections
│   ├── ansible.cfg
│   └── roles/
│       ├── common/                       # base packages, deploy user, SSH hardening, UFW
│       ├── docker/                       # Docker engine + log rotation
│       └── app/                          # app dirs, deploy scripts, env file (payflow.env.j2), deploy
├── Vagrantfile                           # app01 VM (192.168.56.11) to test Ansible deploys
├── ansible.cfg                           # points Ansible at ansible/
│
├── k8s/                                  # Kubernetes manifests
│   ├── namespace.yaml                    # payflow namespace
│   ├── configmap.yaml                    # app settings
│   ├── deployment.yaml                   # 2 replicas, probes, preStop, resources, runAsNonRoot
│   ├── service.yaml                      # NodePort service
│   ├── hpa.yaml                          # CPU-based autoscaling
│   ├── kustomization.yaml                # ties the manifests together
│   └── kind-config.yaml                  # local cluster: 1 control plane + 2 workers
│
├── monitoring/
│   ├── prometheus.yml                    # scrape config
│   ├── alert-rules.yml                   # PayflowApiDown, PayflowHigh5xxRate, PayflowSlowRequests
│   └── grafana/
│       ├── provisioning/datasources/prometheus.yml
│       ├── provisioning/dashboards/dashboards.yml
│       └── dashboards/payflow.json       # "PayFlow API" dashboard
│
├── docs/
│   ├── ARCHITECTURE.md                   # components, environments, artifact flow, versioning
│   ├── CI_CD.md                          # every stage; Jenkins vs TeamCity vs Bitbucket mapping
│   ├── CI_LAB.md                         # running the CI lab step by step
│   ├── DEPLOYMENT.md                     # Ansible + canary deploy, rollback, Vagrant testing
│   ├── KUBERNETES.md                     # manifests, kind workflow, kubectl troubleshooting
│   └── RUNBOOK.md                        # operating procedures, failed-build triage
│
├── .hadolint.yaml                        # Dockerfile lint settings
├── .yamllint.yml                         # YAML lint rules
└── .gitignore
```

## 7. How to run: `run.sh`

`run.sh` is the single entry point for this project and does not need
`make`. After `./run.sh setup`, it automatically uses the tools inside
`.venv` (no need to activate it).

| Command | What it does |
|---|---|
| `./run.sh help` | List all commands |
| `./run.sh doctor` | Check Python, Docker, kind, kubectl, Ansible, Vagrant |
| `./run.sh setup` | Create `.venv` and install dev dependencies |
| `./run.sh lint` | ruff + ShellCheck + yamllint |
| `./run.sh test` | Unit tests |
| `./run.sh run` | Run the API locally on :8000 (no Docker) |
| `./run.sh build` | Build the Docker image |
| `./run.sh start` | API + nginx + Prometheus + Grafana, waits until healthy |
| `./run.sh logs` | Follow API logs |
| `./run.sh smoke [url]` | End-to-end transaction test (default `http://localhost:8080`) |
| `./run.sh scan` | Trivy scan of the image |
| `./run.sh k8s [tag]` | Build, load into kind, deploy and verify (creates the cluster) |
| `./run.sh k8s-rollback` | Undo the last rollout |
| `./run.sh k8s-delete` | Delete the kind cluster |
| `./run.sh validate` | Ansible syntax check |
| `./run.sh deploy-vagrant` | Start the VM if needed and deploy with Ansible |
| `./run.sh health` | Linux server triage report |
| `./run.sh ci-lab-up` / `ci-lab-down` | Start / stop Jenkins, TeamCity, Gitea and the registry |
| `./run.sh stop` | Stop the app stack |
| `./run.sh clean` | Remove `.venv`, caches and reports |

From the portfolio root you can also run `./run.sh 05 <command>`.

## 8. Quick start

```bash
git clone https://github.com/Mian-Basam/payflow-devops-pipeline.git
cd payflow-devops-pipeline

./run.sh doctor                 # 1. check tools
./run.sh setup                  # 2. virtualenv with dev dependencies
./run.sh lint && ./run.sh test  # 3. static checks + 11 unit tests
./run.sh start                  # 4. app behind nginx + Prometheus + Grafana
./run.sh smoke                  # 5. end-to-end transaction through nginx
```

| URL | What |
|---|---|
| http://localhost:8080/health | API via nginx |
| http://localhost:9090 | Prometheus |
| http://localhost:3000 | Grafana, "PayFlow API" dashboard |

## 9. Run the pipelines for real (CI lab)

```bash
./run.sh ci-lab-up      # Jenkins :8090, TeamCity :8111, Gitea :3001, registry :5000
```

1. In Gitea, create user `devops` and repo `payflow-devops-pipeline`, then push this repo to it.
2. Jenkins (admin/admin) already has the **payflow-pipeline** job: it was
   created by Job DSL inside the JCasC file, with no clicks. Run
   **Build with Parameters**.
3. TeamCity: create a project from the Gitea URL, and TeamCity imports
   `.teamcity/settings.kts` (versioned settings). Authorise the agent and run the chain.

Step-by-step with what to expect: [docs/CI_LAB.md](docs/CI_LAB.md)

## 10. Deployment strategies

### Linux servers: canary + automatic rollback (`scripts/deploy.sh`)

```
start new version on :8001 ─▶ health OK? ─no─▶ remove canary, live untouched, exit 1
                                  │yes
                                  ▼
             swap onto live :8000 ─▶ health OK? ─no─▶ redeploy previous image (rollback)
                                  │yes
                                  ▼
                   record in /var/lib/payflow/deploy_history.log
```

Verified with a simulated broken release: the canary failed its health
checks and the live version kept serving.

```
[deploy] deploying payflow-api:broken (previous: payflow-api:v2)
[deploy] starting canary on :8001
[healthcheck] http://localhost:8001 FAILED after 10 attempts
[deploy] ERROR: canary failed health checks; live version untouched
```

### Kubernetes: rolling update (`./run.sh k8s`)

`maxUnavailable: 0`, readiness gates traffic, and a `preStop` delay lets
endpoints drain before shutdown. CI asserts **zero non-200 responses**
during a v1 → v2 rollout, then checks that `rollout undo` brings back v1.

Details: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md), [docs/KUBERNETES.md](docs/KUBERNETES.md)

## 11. API reference

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness: the process is up |
| GET | `/ready` | Readiness: ready to receive traffic |
| GET | `/metrics` | Prometheus metrics (blocked at nginx for public traffic) |
| POST | `/api/v1/transactions` | Create a transaction: `{"amount": 100, "currency": "PKR"}` |
| GET | `/api/v1/transactions/<id>` | Read a transaction |
| PATCH | `/api/v1/transactions/<id>` | Change status: `pending`, `settled` or `declined` |

## 12. Monitoring

The app exports request counts by status, a latency histogram, and
business counters. Prometheus alert rules cover **API down**
(`PayflowApiDown`), **5xx > 5%** (`PayflowHigh5xxRate`) and **p95 >
500ms** (`PayflowSlowRequests`). Grafana is provisioned with the "PayFlow
API" dashboard. For the full observability platform, see Project 4.

## 13. Testing

| Level | What | Where |
|---|---|---|
| Unit | 11 pytest tests (lifecycle, validation, metrics) | `tests/` |
| Static | ruff, shellcheck, yamllint, hadolint, `ansible --syntax-check`, kubeconform, promtool | `./run.sh lint`, `./run.sh validate`, CI |
| Container | image runs, health + smoke test | CI `docker` job |
| Stack | compose up `--wait`, smoke through nginx, Prometheus ready | CI |
| Security | Trivy image + IaC config scan | CI `security-scan` job |
| Kubernetes | kind cluster, deploy, zero-downtime rollout, rollback | CI `kubernetes` job |
| Deploy logic | canary + rollback exercised with a simulated broken image | `scripts/deploy.sh` |

## 14. Security

* Non-root containers (UID 10001); `runAsNonRoot` in Kubernetes; resource limits.
* Images scanned by Trivy; builds fail on fixable HIGH/CRITICAL CVEs.
* Credentials only through the CI credential store (`withCredentials`, TeamCity parameters, Bitbucket secured variables), never in the repo.
* Servers hardened by Ansible: UFW default deny, key-only SSH, no root login.
* `/metrics` blocked at nginx for public traffic.
* Production deploys require manual approval.

## 15. Skills demonstrated

Jenkins (declarative pipelines, JCasC, Job DSL, credentials, `input`
approvals) · TeamCity (Kotlin DSL, build chains, snapshot dependencies) ·
Bitbucket Pipelines · Git workflow · Docker and private registries ·
DevSecOps (Trivy) · Ansible deployment · canary releases and automatic
rollback · Kubernetes (Deployments, probes, HPA, rolling updates, kind) ·
Prometheus/Grafana · Bash · runbooks and documentation.

## 16. Further documentation

| Document | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, environments, artifact flow, versioning |
| [docs/CI_CD.md](docs/CI_CD.md) | Every stage explained; Jenkins vs TeamCity vs Bitbucket mapping; build triage |
| [docs/CI_LAB.md](docs/CI_LAB.md) | Running Jenkins/TeamCity/Gitea/registry locally, step by step |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Ansible + canary deploy, rollback, Vagrant testing |
| [docs/KUBERNETES.md](docs/KUBERNETES.md) | Manifests explained, kind workflow, kubectl troubleshooting |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Operating procedures and failed-build triage table |

---

**Author:** Basil Ahtisham · [LinkedIn](https://linkedin.com/in/mianbasil) · [GitHub](https://github.com/Mian-Basam)
