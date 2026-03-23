# myservers

Manage personal servers with Docker Compose. Nothing else.

## What this is

A complete approach to configuring and maintaining a few personal servers:

- **OS bootstrap** — one-time setup scripts (cloud-init or manual)
  for swap, SSH, basic firewall, Docker, automatic OS updates, and alerting.
- **All services in Docker Compose** — from system services (firewall, DNS, mail, VPN)
  to self-hosted apps (Nextcloud, Gitea, Ollama — whatever you run).
- **Encrypted secrets in git** — managed by [fnox](https://fnox.jdx.dev/),
  supporting multiple backends (age, KeePass, 1Password, Hashicorp Vault, and more).
- **Automated security updates** — OS packages via unattended-upgrades,
  Docker images via Renovate, with daily CI builds to catch breakage early.
- **Monitoring and alerting** — Netdata for both OS and containers,
  system alerts via shared Postfix spool.

Works for both new servers (bootstrap from scratch)
and existing ones (adopt incrementally, one service at a time).

The **only required tool** for this approach is `docker compose`.

No Ansible. No Terraform. No Kubernetes. No Swarm.
Those tools solve real problems — but if you run a couple of VPS boxes
and a home server, their complexity isn't justified.

### Example implementation in this repo

The example configs use specific services (Postfix, Netdata, nftables, etc.),
but the **approach** is general — you can replace any service
with an alternative, as long as it solves the same problem
(mail delivery for both Docker and OS services/cron tasks,
monitoring both OS and Docker, firewall).

The example implementation also uses the [mise](https://mise.jdx.dev/) tool
for running the deploy task both locally and on the remote server.
This is just for better UX; if you don't like it, you can remove it.

Another tool used is [fnox](https://fnox.jdx.dev/) for encrypting secrets.
It's optional (if you don't need secrets).
Previously, I used [git-secret](https://sobolevn.me/git-secret/),
but decrypted secrets in local files may eventually leak to an AI agent.
There are probably other suitable options for managing secrets.

## What this is NOT

- **Not a deployment tool for your own applications.**
  This project is for **operating** servers — installing and configuring
  software you didn't write (reverse proxy, mail, VPN, monitoring)
  and self-hosted apps you don't develop (Ollama, EteSync, Jackett).
  If you develop an app and deploy new versions frequently, use
  [Kamal](https://kamal-deploy.org/), [Coolify](https://coolify.io/),
  or your CI/CD pipeline.
- **Not a PaaS.** No web dashboard, no API, no agent running on your server.
- **Not a framework.** It's a pattern with a thin deploy script.
  Fork it, delete the example servers, add your own.

## Who this is for

- You're a **developer** who also runs a few personal servers
  and wants to manage them with tools you already know (Docker Compose, bash, git)
  rather than learning Ansible or Terraform.
- You manage 1–5 personal servers (cloud VPS, home server, or both).
- You want your server config in git — reviewable, reproducible, infrastructure as code.
- You're tired of Ansible playbooks for what amounts to
  "run these containers with these env vars."
- You might use AI coding assistants and want secrets properly isolated
  from the AI agent's environment.

> [!NOTE]
> Note on professional admins/DevOps:
> If you already use Ansible or Terraform daily at work,
> you'll likely prefer those familiar tools for your personal servers too —
> even if they're overkill. This project targets developers
> for whom Docker Compose is the familiar tool, not Ansible.

### Operator vs developer

The boundary is your **role**, not the type of software:

|                 | Operator (this project)              | Developer (Kamal, CI/CD)  |
| --------------- | ------------------------------------ | ------------------------- |
| What you deploy | Someone else's software, your config | Your own code             |
| How often       | Rarely (days to weeks)               | Often (hours to days)     |
| Trigger         | Manual, watched                      | Automated on push         |
| Updates         | Aggressively (security-first)        | When the project needs it |

Running Ollama on your home server is an **operator** task —
you configure it, not develop it.
Deploying your SaaS app 5 times a day is a **developer** task.
This project handles the first case.

## Who this is NOT for

- Teams managing production infrastructure (use Terraform/Pulumi).
- Anyone who needs auto-scaling, rolling deploys, or multi-region (use Kubernetes).
- People deploying their own applications frequently (use Kamal or CI/CD).
- People looking for a web UI to manage servers (use Coolify/Dokploy).

## How it works

### Server bootstrap

Each **new** server starts with a one-time setup script
that prepares the OS for container-based management:

- Swap and zswap for servers with limited RAM.
- Set up hostname.
- SSH hardening (key-only auth, no passwords).
- Basic nftables firewall (allows only ssh) compatible with Docker networking
  (pre-creates Docker chains so nftables container restarts are idempotent).
- Postfix on the host for system email
  (`/var/spool/postfix` shared with containerized Postfix later).
- systemd failure handler that emails you when any service crashes.
- Automatic OS security updates with email notifications.
- Docker engine installation and configuration.
- Other tools used by deploy (mise), if any.
- (Optional) Your favorite CLI tools, configured as you like.

For **cloud servers**, this is a cloud-init user-data script
provided at instance creation.
For **non-cloud new servers** (VPS, home server), run the script manually once.
This script is not idempotent — it is designed to run exactly once on a fresh OS.

For **existing servers** only setup you need to start using the project
is a Docker engine installation and configuration (if not installed yet).
It even may be a rootless docker running by some non-root user account.

### Gradual adoption

You don't have to start from scratch.
If you have an existing server configured manually over the years,
you can adopt this project incrementally:

1. Create a `srv/NAME/` directory with `destination` and a minimal
   `docker-compose.yml` covering just one or two services.
2. Deploy. The existing OS config stays untouched.
3. Gradually move more services into the compose file over time.

This is how the home server setup works in this project:
the OS was configured manually long ago,
and Docker services are being added one by one.
You can also run a separate user's rootless Docker instance on the same host
as a distinct "server" entry.

### Server configuration

Each server is a directory under `srv/`:

```text
fnox.toml                   # (Optional) Shared fnox providers setup
srv/
├── README.md               # (Optional) Documentation for your infrastructure
├── primary/                # Cloud VPS: DNS, mail, VPN, reverse proxy
│   ├── destination         # SSH target: root@primary.example.com
│   ├── docker-compose.yml
│   ├── mise.toml           # Mise config (setup fnox, load host-facts.sh)
│   ├── host-facts.sh       # (Optional) Runtime host discovery (IPs, UIDs)
│   ├── fnox.toml           # (Optional) Encrypted secrets
│   └── bootstrap.sh        # (Optional for existing servers)
├── secondary/              # Another cloud VPS: secondary DNS and mail
│   └── ...
└── homelab/                # Existing home server
    └── ...
```

Deploy server "primary" in one command:

```sh
mise run deploy primary
```

This will:

1. Rsync `srv/primary/` to the server's `~/.myserver/`.
2. Copy the root `fnox.toml` to the server as `~/.myserver/fnox.local.toml`
   (provides fnox provider config for decryption).
3. Send `FNOX_AGE_KEY` via SSH `SendEnv` for secret decryption on the server.
   (You may need to change this if you'll use other fnox providers.)
4. Run `mise exec -- docker compose build` and `mise exec -- docker compose up --wait`
   (mise loads secrets via fnox and sources `host-facts.sh` automatically).

Deploy is always manual — you watch the output,
verify healthchecks pass, and roll back with `git checkout @~` + redeploy if not.

### Idempotency

Server configuration is idempotent: re-running deploy produces the same result.
This is mostly handled by `docker compose`, but there are several other key patterns:

- **Firewall** — the nftables container pre-creates Docker's filter chains
  and uses priority rules to run _before_ Docker's NAT.
  Restarting the container re-applies firewall rules
  without conflicting with Docker's iptables/nftables.
- **Shared Postfix spool** — `/var/spool/postfix` on the host is initialized
  once by `bootstrap.sh`, then bind-mounted into the Postfix container.
  System daemons (cron, unattended-upgrades) and container services
  share the same mail queue.
- **WireGuard** — the entrypoint traps EXIT to run `wg-quick down`,
  ensuring clean interface teardown on container stop.

### Security updates

Keeping all software up to date is critical for personal servers
where you don't have a security team watching CVEs.

| Layer                             | Mechanism                         | Frequency |
| --------------------------------- | --------------------------------- | --------- |
| OS packages                       | unattended-upgrades (automatic)   | Daily     |
| Docker Compose images             | Renovate PRs                      | Daily     |
| Docker base images in Dockerfiles | Renovate PRs                      | Daily     |
| Alpine packages in Dockerfiles    | Renovate PRs                      | Daily     |
| Custom packages in Dockerfiles    | Renovate PRs (need manual regexp) | Daily     |
| GitHub Actions                    | Renovate PRs                      | Daily     |

Daily CI builds catch broken Dockerfiles early:
if an Alpine package version is removed (often due to a security fix),
the CI build fails, alerting you to update the pin.

### Monitoring

[Netdata](https://www.netdata.cloud/) runs with host networking and PID namespace access,
monitoring both the OS and all containers:

- System metrics (CPU, memory, disk, network).
- Docker container health and resource usage
  (via docker-socket-proxy, not a direct Docker socket mount).
- Postfix mail queue (via shared `/var/spool/postfix`).
- Service-specific checks (Caddy, WireGuard, DNS).

Alerts go via Telegram (or any Netdata-supported channel).
System-level failures (crashed systemd services, failed OS updates)
go via email through the shared Postfix.

## Quick start

### Prerequisites

- SSH access to your server(s) as root (or a user with docker access).
- Server with Docker installed
  (see `bootstrap.sh` examples, or install Docker manually).
- [mise](https://mise.jdx.dev/) installed locally and on server.

### 1. Fork and clone

Fork this repository into a **private** repo — even though secrets are encrypted,
the configs contain sensitive details (IP addresses, hostnames, service topology)
that you probably don't want public.

```sh
git clone https://github.com/YOUR_USER/myservers
cd myservers
```

### 2. Set up secrets

Secrets are managed by [fnox](https://fnox.jdx.dev/).
fnox supports multiple secret providers — age encryption (local),
KeePass (local), 1Password, Hashicorp Vault, and others.
See [fnox documentation](https://fnox.jdx.dev/providers/overview.html) to choose your provider.

Example with age (simplest for local use):

```sh
# Generate an age key.
age-keygen -o ~/.config/fnox/age.txt

# Update fnox.toml (in the repo root) with your public key (from age-keygen output).
```

The deploy script reads the key from `~/.config/fnox/age.txt`
and sends it to the server via SSH `SendEnv`.
The root `mise.toml` sets `FNOX_AGE_KEY = false`
to prevent the age key from leaking through environment variable (if you'll set it).
AI agents are explicitly prohibited from running fnox command.

> [!NOTE]
> Each server's sshd must be configured with `AcceptEnv FNOX_AGE_KEY`
> (included in the bootstrap scripts).
> For interactive use on the server, configure your SSH client
> with `SendEnv FNOX_AGE_KEY` and set the key in your local environment.

### 3. Add your server

Create a directory under `srv/` for each server you want to manage.
Relative paths below are relative to this directory.

```sh
mkdir srv/someserver
echo "root@someserver.example.com" >srv/someserver/destination
```

- `./destination` — SSH target (e.g. `root@example.com`).
  This user must have access to docker.
- `./docker-compose.yml` — all services for the server.
  See the example servers (`srv/example-*`) for patterns.
- `./mise.toml` — Mise config: fnox plugin/tools and env loading (secrets + host facts).
- `./host-facts.sh` (optional) — runtime host discovery script for `docker-compose.yml` variables
  that must be **computed on the target server** (IPs, UIDs, etc.).
  Must be a shell script which `export` variables as result.
  Sourced automatically by mise via `_.source` in `mise.toml`.
- `./fnox.toml` (optional, created automatically by `fnox set`) — encrypted secrets.
- `./bootstrap.sh` (optional) — one-time OS setup script.
  Provide it as user-data when creating a cloud server,
  or run it manually on a non-cloud server.

If need secrets, configure the fnox provider and recipients in `fnox.toml` (at the repo root),
then add secrets in `./fnox.toml`:

```sh
cd srv/someserver
fnox set MY_SECRET_VAR # prompts for value, encrypts and stores
```

Secrets are available as environment variables for `docker compose` during deploy.
Some services expect secrets as **files**, not environment variables.
For these, use Docker BuildKit secret mounts: define the secret in `docker-compose.yml`
(`secrets:` + `build.secrets`) and consume it in the Dockerfile with `RUN --mount=type=secret`.

Document server-specific details (IPs, hostnames, VPN topology, quirks)
in `srv/README.md` for your own reference.

### 4. Deploy

```sh
mise run deploy someserver
```

## Day-to-day workflow

| Task                    | Command                                |
| ----------------------- | -------------------------------------- |
| Deploy a server         | `mise run deploy SERVER`               |
| Add/update a secret     | `(cd srv/SERVER && fnox set VAR_NAME)` |
| Test one server's build | `mise run test:docker-build SERVER`    |
| Run all tests           | `mise run test`                        |
| Run all linters         | `mise run lint`                        |
| Format code             | `mise run fmt`                         |

## Testing

`mise run test` builds Docker images for all servers locally, without deploying.
The test script provides fake values for all secrets (no real encryption key needed)
and uses `DEVEL=true` (set in root `mise.toml`) so `host-facts.sh` uses fallback values
for host-specific settings (IPs, UIDs) unavailable off the target server.

CI runs the same checks via `mise run ci` (fmt + lint + test).

## Design decisions

**Manual deploy only.**
For personal servers, you want to watch `docker compose up` output and verify healthchecks.
Automated deployment of server configuration is a risk that doesn't pay off at this scale.
Redundancy (primary + secondary DNS/mail) covers the window of a failed deploy.

**One docker-compose.yml per server.**
All services for a server live in one compose file.
This is intentional — at this scale, splitting into multiple compose files
adds complexity without benefit.

**No abstraction over Docker Compose.**
`docker-compose.yml` files are plain Docker Compose, not templates or generated.
If you know Docker Compose, you know this project.

**Healthchecks everywhere.**
Every container declares a healthcheck.
`docker compose up --wait` blocks until all services are healthy,
giving you immediate feedback on deploy success.

**Secrets decrypted on the server, not locally.**
Encrypted in git via fnox.
The age key is sent via SSH `SendEnv` at deploy time;
secrets are decrypted by fnox on the server.
No plaintext secrets are stored on disk (locally or on the server).
AI agents are explicitly prohibited from running `fnox` decryption commands.

## Troubleshooting

Deploy rsyncs your server directory to `~/.myserver/` on the target host.
To debug on the server, `cd ~/.myserver` — mise automatically loads the environment
(secrets + host facts) if `FNOX_AGE_KEY` is available:

```sh
cd ~/.myserver
docker compose ps
docker compose logs caddy         # check a specific service
docker compose up -d --wait caddy # start a single service
```

For interactive sessions, configure SSH `SendEnv FNOX_AGE_KEY`
on your client so the key is available when you SSH in.

## Similar projects and resources

Most "homelab docker compose" projects focus on running self-hosted apps
but don't containerize system infrastructure (firewall, mail, DNS, VPN)
or include OS bootstrap and security update automation.

- [splitbrain/infra-bitters](https://github.com/splitbrain/infra-bitters)
  ([blog post](https://www.splitbrain.org/blog/2024-09/23-personal_server_with_docker_compose)) —
  closest in philosophy: one person, one server, everything in Docker Compose, configs in git.
  Simpler scope (no cloud-init, no encrypted secrets, no firewall/VPN/mail).
- [homeinfra-org/infra](https://github.com/homeinfra-org/infra) —
  homelab docker-compose with HTTPS, DDNS, backups.
  Focused on homelab behind NAT (Cloudflare tunnels).
- [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)
  ([guide](https://www.simplehomelab.com/ultimate-docker-server-1-os-preparation/)) —
  comprehensive 30-part guide on building a Docker server with 60+ apps.
  No IaC approach or deploy automation.

## Alternatives and trade-offs

| If you need…                        | Consider instead    |
| ----------------------------------- | ------------------- |
| Managing 10+ servers or a team      | Ansible, Terraform  |
| Auto-scaling, zero-downtime deploys | Kubernetes, Nomad   |
| Deploying your own apps from CI/CD  | Kamal, Coolify      |
| A web UI for server management      | Coolify, Dokploy    |
| Fully automated server provisioning | Terraform + Ansible |

This project intentionally trades automation and scale
for simplicity and direct control.
If you find yourself adding abstractions on top of it,
you've probably outgrown it — and that's fine.
