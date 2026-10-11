# Docker and container deployment files

Docker files live here, while the build context remains the repository root because the image copies the canonical `game/csgo/` payload.

| File | Purpose |
| --- | --- |
| `Dockerfile` | Container image definition. |
| `install_docker.sh` | In-container initialization/installation entrypoint copied into the image. |
| `docker-compose.yml` | Compose definition, including the persistent volume and published game ports. |
| `kubernetes/manifest.yaml` | Legacy upstream Kubernetes manifest kept for reference; it still targets the old KUS image/layout and is **not** the maintained deployment path for this unified repo. |

Run Compose from the repository root:

```bash
docker compose -f docker/docker-compose.yml up --build
```

The root `.dockerignore` intentionally stays at the repository root because that is the configured build context. The Docker entrypoint has not yet been live-tested with this unified private repository.
