# PayFlow API – Operations Runbook

Short, practical procedures for the on-call / release engineer.

## Release flow

```
commit -> Bitbucket -> CI (Jenkins or TeamCity)
        lint + unit tests -> docker build -> push to registry.local
        -> Ansible deploy (canary on :8001 -> health check -> promote to :8000)
        -> smoke test -> done
```

Production deploys in Jenkins pause at **Approve production** for a manual OK.

## Deploy manually

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml \
  --limit staging -e app_image=registry.local:5000/payflow-api:<tag>
```

Only the `app` role:  add `--tags deploy`.

## Roll back

`deploy.sh` rolls back automatically if the new version fails health checks
after the swap. To roll back by hand, redeploy the previous tag:

```bash
cat /var/lib/payflow/deploy_history.log          # find previous tag
/opt/payflow/scripts/deploy.sh registry.local:5000/payflow-api:<previous-tag>
```

Kubernetes: `make k8s-rollback` (`kubectl rollout undo`).

## Failed build

| Stage that failed | First thing to check |
|---|---|
| Lint & Unit tests | Open the JUnit report in the build; run `make lint test` locally on the same commit |
| Build image | Did `requirements.txt` change? Is the base image pullable from the agent? `docker build .` locally |
| Push image | Registry reachable from agent? (`curl -k https://registry.local:5000/v2/`), credentials `registry-creds` still valid |
| Deploy (Ansible) | Re-run with `-vv`; check SSH to host (`ssh deploy@<host>`), disk space on host |
| Smoke test | `curl http://<host>/health`; `docker logs payflow-api --tail 100` on the host |

Escalate to the owning dev team when a test fails on a commit that passes
locally for them, or the failure is in application logic rather than infra.

## API down

1. `./scripts/healthcheck.sh http://<host>:8000 3 2`
2. On the host: `docker ps -a | grep payflow`, `docker logs --tail 100 payflow-api`
3. `./scripts/server_health.sh` – check disk, memory, load, DNS
4. Errors in logs: `docker logs payflow-api 2>&1 | ./scripts/log_scan.sh -`
5. If the last deploy caused it: roll back (above).

## Monitoring

* Prometheus scrapes `/metrics` every 15s.
* Grafana dashboard **PayFlow API**: request rate by status, p95 latency,
  5xx ratio, transactions created.
* Alerts (`monitoring/alert-rules.yml`): API down (1m), 5xx > 5% (5m),
  p95 latency > 500ms (10m).

## Network quick checks

```bash
ss -ltnp | grep 8000          # is the port listening?
curl -v http://<host>/health  # TCP + HTTP path end to end
getent hosts app01.stg.local  # DNS resolution
ip route                      # default gateway
```
