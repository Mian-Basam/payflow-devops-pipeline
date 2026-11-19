# CI Lab

Runs Jenkins, TeamCity, a Git server and a Docker registry locally so the
pipelines in this repo can be executed for real.

```bash
cd ci-lab
docker compose up -d --build
```

| Service | URL | First login |
|---|---|---|
| Gitea | http://localhost:3001 | register a user named `devops` (first user becomes admin) |
| Jenkins | http://localhost:8090 | admin / admin (from JCasC) |
| TeamCity | http://localhost:8111 | follow the first-start wizard, then authorise `lab-agent-1` |
| Registry | http://localhost:5000/v2/_catalog | – |

See [../docs/CI_LAB.md](../docs/CI_LAB.md) for the full walkthrough.
