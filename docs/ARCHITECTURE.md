# Architecture

## Components

| Component | Technology | Purpose |
|---|---|---|
| payflow-api | Python 3.12, Flask, Gunicorn | Transaction service: create, read and settle transactions |
| Reverse proxy | Nginx 1.27 | Public entry point; blocks `/metrics` |
| Source control | Bitbucket (prod) / Gitea (lab) | Git hosting, pull requests, webhooks |
| CI | Jenkins or TeamCity | Builds, tests, scans and deploys |
| Registry | Docker Registry v2 | Stores versioned images |
| Config management | Ansible | Server baseline + application deploy |
| Runtime A | Docker on Linux VMs | Classic on-prem target |
| Runtime B | Kubernetes | Orchestrated target |
| Monitoring | Prometheus + Grafana | Metrics, alerts, dashboards |

## Environments

| Env | Hosts | How it is deployed | Approval |
|---|---|---|---|
| local | your machine | `make up` (Compose) | – |
| staging | `app01.stg.local` | pipeline, automatically on `main` | none |
| production | `app01/02.prod.local` | pipeline with `TARGET_ENV=production` | manual `input` |
| kubernetes | kind cluster | `make k8s-apply` / CI | – |

## Artifact flow and versioning

```
commit abc1234 → build #57 → image registry.local:5000/payflow-api:57-abc1234
                                  │
                       the SAME image is promoted
                       staging ──▶ production
```

* **Build once, deploy many.** Production runs the exact image that passed staging.
* The tag `BUILD_NUMBER-GITSHA` maps every running container back to its build and commit.
* The version is baked into the image (`APP_VERSION`) and reported by `/health`, so deploys can verify what is actually running.

## Network (on-prem)

```
users ─▶ :80 nginx ─▶ :8000 payflow-api (container)
                         ▲
Prometheus ──────────────┘ /metrics (internal only)
CI server ── SSH 22 ─▶ app hosts (deploy user, key auth)
```

## Failure handling

| Failure | Behaviour |
|---|---|
| Tests fail | Pipeline stops; nothing is built or deployed |
| Image has fixable HIGH/CRITICAL CVE | Pipeline stops before push |
| New version fails health on canary port | Canary removed; live untouched |
| New version fails health after swap | Previous image redeployed automatically |
| Pod fails readiness in Kubernetes | Rollout pauses; old pods keep serving (`maxUnavailable: 0`) |
| Process crashes in production | Docker `--restart unless-stopped` / Kubernetes restarts it; Prometheus alert fires |
