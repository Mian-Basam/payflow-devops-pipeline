# Kubernetes

## Manifests (`k8s/`)

| File | Object | Key settings |
|---|---|---|
| `namespace.yaml` | Namespace `payflow` | isolates resources |
| `configmap.yaml` | ConfigMap | `LOG_LEVEL`, injected with `envFrom` |
| `deployment.yaml` | Deployment | 2 replicas; `RollingUpdate` with `maxUnavailable: 0`, `maxSurge: 1`; liveness `/health`, readiness `/ready`; requests/limits; `runAsNonRoot`; `preStop` sleep; `revisionHistoryLimit: 5` |
| `service.yaml` | Service (NodePort 30080) | stable address in front of the pods |
| `hpa.yaml` | HorizontalPodAutoscaler | 2–5 replicas at 70% CPU (needs metrics-server) |
| `kustomization.yaml` | Kustomize | `kubectl apply -k k8s/` |
| `kind-config.yaml` | kind cluster | 1 control plane + 2 workers, port 30080 mapped to the host |

## Workflow

```bash
make k8s-apply          # create kind cluster (if needed), build, load, deploy, verify
make k8s-rollback       # kubectl rollout undo
```

`scripts/k8s_deploy.sh` builds the image tagged with the git SHA, loads it
into the kind nodes (no registry needed), applies the manifests, sets the
image, waits for `rollout status`, then runs the health check and smoke
test and **asserts the running version equals the tag**.

## Why the rollout has zero downtime

* `maxUnavailable: 0`: an old pod is removed only after a new one is **Ready**.
* Readiness probe: traffic goes only to pods that answer `/ready`.
* `preStop: sleep 5`: when a pod is terminated, endpoint removal and
  SIGTERM happen at the same time. The pause keeps the old pod serving
  until the Service has stopped routing to it.

CI proves it: 300 requests during a v1 → v2 rollout, all must be `200`.

## Liveness vs readiness

| Probe | Question | On failure |
|---|---|---|
| Liveness `/health` | Is the process stuck? | container restarted |
| Readiness `/ready` | Can it take traffic now? | removed from Service endpoints, not restarted |

## kubectl troubleshooting

```bash
kubectl -n payflow get pods -o wide
kubectl -n payflow describe pod <pod>          # events: image pull, probe failures, OOMKilled
kubectl -n payflow logs <pod> --previous       # logs of the crashed container
kubectl -n payflow get events --sort-by=.lastTimestamp
kubectl -n payflow rollout history deploy/payflow-api
kubectl -n payflow port-forward deploy/payflow-api 8000:8000
kubectl -n payflow exec -it deploy/payflow-api -- sh
```

| Status | Meaning | Look at |
|---|---|---|
| `ImagePullBackOff` | image not found / no access | image name/tag, `kind load`, registry credentials |
| `CrashLoopBackOff` | container keeps exiting | `logs --previous` |
| `Running` but `0/1 READY` | readiness probe failing | `describe pod` events, the `/ready` endpoint |
| `OOMKilled` | exceeded memory limit | raise the limit or fix the leak |
| `Pending` | cannot schedule | `describe pod`: insufficient CPU/memory, node selectors |
