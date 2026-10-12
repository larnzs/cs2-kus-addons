# Docker and container deployment files

Docker files live here, while the build context remains the repository root because the image copies the canonical `game/csgo/` payload.

| File | Purpose |
| --- | --- |
| `update.sh` | Host-side unified updater: fast-forwards the repository, updates plugin payloads, rebuilds the image, and runs a one-shot maintenance container to update SteamCMD and safely overlay the persistent game volume. Refuses to update while the CS2 container is running and does not launch a server. |
| `Dockerfile` | Container image definition. |
| `install_docker.sh` | In-container initialization entrypoint; with `UPDATE_ONLY=1`, it updates/overlays and exits without starting CS2. |
| `docker-compose.yml` | Compose definition, including the persistent volume and published game ports. |
| `kubernetes/manifest.yaml` | Legacy upstream Kubernetes manifest kept for reference; it still targets the old KUS image/layout and is not the maintained deployment path. |

Before starting, copy `.env.example` to `.env` and edit it. Keep actual credentials only in `.env`, never commit it. The updater requires this file because Compose loads it for the one-shot maintenance container.

Build and launch normally from the repository root:

```bash
docker compose -f docker/docker-compose.yml up --build
```

Run maintenance from the repository root:

```bash
bash ./docker/update.sh
```

The update path stops if the named `cs2-modded-server` container is running. Stop the server first, run the updater, then start the container separately when ready.
