# Deployment

## On-prem servers with Ansible

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml \
  --limit staging -e app_image=registry.local:5000/payflow-api:57-abc1234
```

| Role | Does |
|---|---|
| `common` | baseline packages, deploy user, chrony, UFW (22/80/8000), SSH hardening |
| `docker` | Docker engine + Compose, log rotation (`max-size 20m`, 5 files), deploy user in `docker` group |
| `app` | ships scripts, writes env file, runs `deploy.sh` **only if the image changed**, final health check |

The deploy step is idempotent: it reads `/var/lib/payflow/current_image`
and skips when the requested image is already live.

## deploy.sh: canary with automatic rollback

```
./scripts/deploy.sh registry.local:5000/payflow-api:<tag>
```

1. Records the currently live image (`current_image`).
2. Starts the new image as `payflow-api-canary` on **:8001**.
3. `healthcheck.sh` polls `/health` and `/ready` (10 tries, 3s apart).
   * Fail: canary removed, live untouched, exit 1.
4. Replaces the live container on **:8000** with the new image.
5. Health check again.
   * Fail: **rollback** to the previous image, verify, exit 1.
6. Success: writes `current_image` and appends to `deploy_history.log`.

Environment overrides: `APP_NAME`, `LIVE_PORT`, `STAGE_PORT`, `STATE_DIR`.

### Verified scenarios

Tested with a stub Docker CLI that starts real app processes:

| Scenario | Result |
|---|---|
| First deploy v1 | live = v1 |
| Upgrade v1 → v2 | canary OK → promoted → live = v2 |
| Broken image | canary fails 10 checks → removed → **live still v2** |

## Manual rollback

```bash
cat /var/lib/payflow/deploy_history.log
/opt/payflow/scripts/deploy.sh registry.local:5000/payflow-api:<previous-tag>
```

## Testing deployments on a VM

```bash
vagrant up                 # Ubuntu VM at 192.168.56.11
make deploy-vagrant        # ansible with inventory.vagrant.ini
```

Use `vagrant snapshot save app01 clean` before experiments and
`vagrant snapshot restore app01 clean` to reset.
