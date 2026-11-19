#!/usr/bin/env bash
# PayFlow DevOps Pipeline - one entry point for every common task.
#
#   ./run.sh                 show help
#   ./run.sh setup           create .venv and install dev dependencies
#   ./run.sh start           API + nginx + Prometheus + Grafana in Docker
#   ./run.sh smoke           end-to-end transaction test through nginx
#   ./run.sh k8s             deploy to a local kind Kubernetes cluster
#   ./run.sh ci-lab-up       Jenkins + TeamCity + Gitea + registry locally
#
# Run "./run.sh help" for the full list.
set -euo pipefail
cd "$(dirname "$0")"

# Use tools installed by ../install.sh (shared ../.venv and ~/.local/bin); nothing to activate.
[[ -x ../.venv/bin/python ]] && PATH="$(cd .. && pwd)/.venv/bin:$PATH"
PATH="$HOME/.local/bin:$PATH"; export PATH

IMAGE="${IMAGE:-payflow-api:local}"
VENV=.venv

c_ok=$'\e[32m'; c_err=$'\e[31m'; c_dim=$'\e[2m'; c_off=$'\e[0m'
[[ -t 1 && -z "${NO_COLOR:-}" ]] || { c_ok=""; c_err=""; c_dim=""; c_off=""; }
say()  { printf '%s>>%s %s\n' "$c_ok" "$c_off" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }
need() { local m=(); for t in "$@"; do command -v "$t" >/dev/null || m+=("$t"); done
         ((${#m[@]} == 0)) || die "missing tool(s): ${m[*]}  (fix: ./run.sh install-deps)"; }
need_docker() {
  need docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin not found ('docker compose')"
  docker info >/dev/null 2>&1 || die "Docker daemon is not running (start Docker Desktop / dockerd)"
}
# Use the project virtualenv when it exists.
[[ -x "$VENV/bin/python" ]] && export PATH="$PWD/$VENV/bin:$PATH"

doctor() {
  local rc=0
  for t in python3 docker curl git shellcheck yamllint ansible-playbook kind kubectl vagrant; do
    if command -v "$t" >/dev/null; then printf '  %sok%s       %s\n' "$c_ok" "$c_off" "$t"
    else printf '  %smissing%s  %s\n' "$c_err" "$c_off" "$t"; rc=1; fi
  done
  docker compose version >/dev/null 2>&1 && printf '  %sok%s       docker compose\n' "$c_ok" "$c_off" \
    || { printf '  %smissing%s  docker compose v2\n' "$c_err" "$c_off"; rc=1; }
  docker info >/dev/null 2>&1 && printf '  %sok%s       docker daemon running\n' "$c_ok" "$c_off" \
    || { printf '  %sdown%s     docker daemon\n' "$c_err" "$c_off"; rc=1; }
  [[ -x "$VENV/bin/pytest" ]] && printf '  %sok%s       .venv (pytest, ruff)\n' "$c_ok" "$c_off" \
    || printf '  %s--%s       .venv not created yet (./run.sh setup)\n' "$c_dim" "$c_off"
  printf '\n%sMinimum: python3 + docker. kind/kubectl only for k8s, ansible/vagrant only for VM deploys.%s\n' "$c_dim" "$c_off"
  return $rc
}

usage() {
  cat <<EOF
PayFlow DevOps Pipeline - run.sh

Usage: ./run.sh <command> [args]

Setup
  install-deps      install every dependency (../install.sh 05)
  doctor             check required tools
  setup              create .venv and install dev dependencies

Develop
  lint               ruff + shellcheck + yamllint
  test               unit tests (pytest)
  run                run the API locally on :8000 (no Docker)

Docker
  build              build the image ($IMAGE)
  start | up         API + nginx + Prometheus + Grafana, wait until healthy
  stop  | down       stop the stack
  logs               follow API logs
  smoke              end-to-end smoke test through nginx (:8080)
  scan               Trivy scan of the image (HIGH/CRITICAL)

Kubernetes (kind)
  k8s [tag]          build, load into kind, deploy, verify (creates cluster)
  k8s-rollback       undo the last rollout
  k8s-delete         delete the kind cluster

Ansible / VMs
  validate           ansible syntax check
  deploy-vagrant     provision the Vagrant VM with Ansible
  health             Linux server triage report

CI lab (Jenkins :8090, TeamCity :8111, Gitea :3001, registry :5000)
  ci-lab-up          start the CI lab
  ci-lab-down        stop the CI lab

  clean              remove .venv, caches and reports
EOF
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  help|-h|--help) usage ;;
  install-deps)
    [[ -x ../install.sh ]] || die "../install.sh not found: it is in the full portfolio repo (git clone https://github.com/Mian-Basam/devops-portfolio)"
    exec ../install.sh 05 "$@" ;;
  doctor)    doctor ;;
  setup|install)
    need python3; say "creating $VENV"
    python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r requirements-dev.txt
    say "done - tools in $VENV are used automatically by ./run.sh" ;;
  lint)
    need ruff shellcheck yamllint
    ruff check app tests; shellcheck scripts/*.sh run.sh; yamllint -c .yamllint.yml .
    say "lint passed" ;;
  test)      need pytest; pytest -q ;;
  run)       need python3; say "API on http://localhost:8000"; python3 -m app.main ;;
  build)     need_docker; docker build --build-arg APP_VERSION=local -t "$IMAGE" . ;;
  start|up)
    need_docker; docker compose up -d --build --wait
    say "API http://localhost:8080/health | Prometheus http://localhost:9090 | Grafana http://localhost:3000" ;;
  stop|down) need_docker; docker compose down ;;
  logs)      need_docker; docker compose logs -f api ;;
  smoke)     need curl; ./scripts/smoke_test.sh "${1:-http://localhost:8080}" ;;
  scan)
    need_docker
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.56.2 \
      image --severity HIGH,CRITICAL --ignore-unfixed "$IMAGE" ;;
  k8s|k8s-apply)  ./scripts/k8s_deploy.sh "$@" ;;
  k8s-rollback)   ./scripts/k8s_deploy.sh --rollback ;;
  k8s-delete)     need kind; kind delete cluster --name payflow ;;
  validate)       need ansible-playbook; ansible-playbook -i ansible/inventory.ini ansible/site.yml --syntax-check ;;
  deploy-vagrant)
    need vagrant ansible-playbook
    vagrant status | grep -q running || vagrant up
    ansible-playbook -i ansible/inventory.vagrant.ini ansible/site.yml ;;
  health)         ./scripts/server_health.sh ;;
  ci-lab-up)
    need_docker; (cd ci-lab && docker compose up -d --build)
    say "Jenkins :8090 (admin/admin) | TeamCity :8111 | Gitea :3001 | registry :5000  - see docs/CI_LAB.md" ;;
  ci-lab-down)    need_docker; (cd ci-lab && docker compose down) ;;
  clean)          rm -rf "$VENV" .pytest_cache reports __pycache__ ./*/__pycache__; say "cleaned" ;;
  *)              usage; die "unknown command: $cmd" ;;
esac
