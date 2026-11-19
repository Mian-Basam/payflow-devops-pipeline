.PHONY: help install test lint run build up down logs smoke health validate k8s-apply k8s-rollback deploy-vagrant clean ci-lab-up ci-lab-down scan

IMAGE ?= payflow-api:local

help:            ## show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

install:         ## create venv + dev deps
	python3 -m venv .venv && .venv/bin/pip install -q -r requirements-dev.txt

lint:            ## ruff + shellcheck + yamllint
	ruff check app tests
	shellcheck scripts/*.sh
	yamllint -c .yamllint.yml .

test:            ## unit tests
	pytest -q

run:             ## run the API locally on :8000
	python -m app.main

build:           ## build docker image
	docker build --build-arg APP_VERSION=local -t $(IMAGE) .

up:              ## start app + nginx + prometheus + grafana
	docker compose up -d --build --wait
	@echo "API: http://localhost:8080  Prometheus: http://localhost:9090  Grafana: http://localhost:3000"

down:            ## stop the stack
	docker compose down

logs:            ## tail app logs
	docker compose logs -f api

smoke:           ## end-to-end smoke test against the stack
	./scripts/smoke_test.sh http://localhost:8080

health:          ## Linux server triage report
	./scripts/server_health.sh

validate:        ## static checks for ansible + k8s
	ansible-playbook -i ansible/inventory.ini ansible/site.yml --syntax-check

k8s-apply:       ## build, load into kind and deploy (creates the cluster if needed)
	./scripts/k8s_deploy.sh

k8s-rollback:    ## undo the last k8s rollout
	./scripts/k8s_deploy.sh --rollback

deploy-vagrant:  ## provision the Vagrant VM with Ansible
	ansible-playbook -i ansible/inventory.vagrant.ini ansible/site.yml

clean:
	rm -rf .venv .pytest_cache reports __pycache__ */__pycache__

ci-lab-up:       ## start Jenkins, TeamCity, Gitea and a registry locally
	cd ci-lab && docker compose up -d --build
ci-lab-down:     ## stop the CI lab
	cd ci-lab && docker compose down
scan:            ## Trivy vulnerability scan of the image
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.56.2 image --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE)
