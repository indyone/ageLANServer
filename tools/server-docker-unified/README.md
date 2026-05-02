# server-docker-unified

A single-container Docker setup for ageLANServer. This is an alternative to
[`tools/server-docker`](../server-docker), which runs `genCert` and `server`
as two separate services. Here both are bundled into one image that handles
everything automatically on startup.

## How it works

### Image structure

The image is built in three stages:

1. **Compiler** — A single Go build stage compiles both the `server-genCert`
   and `server` modules using a combined `go.work` workspace.
2. **Compressor** — Both binaries are compressed with UPX (LZMA) to reduce the
   final image size.
3. **Runtime** — An Alpine Linux base contains the two compressed binaries, the
   server's static resources, and the entrypoint script.

### First-run certificate generation

On every container start, the entrypoint runs `genCert` before starting the
server:

- **First run** — certificates do not exist yet; `genCert` generates them into
  the mounted certificates volume and exits with code `0`.
- **Subsequent runs** — certificates already exist; `genCert` exits with code
  `8` (`ErrCertCreateExisting`), which the entrypoint treats as success and
  skips silently.
- **Any other exit code** — treated as a real error; the container stops and
  prints the exit code.

Because the certificates volume is mounted from outside the container, they
persist across restarts and image updates.

### Game selection

Each container runs **one game**. Set the `GAMES` environment variable to the
game you want to serve. To support multiple titles, run one container per game
(they share the same image).

| Value    | Game                                   | Default |
|----------|----------------------------------------|---------|
| `age1`   | Age of Empires: Definitive Edition     | ❌ |
| `age2`   | Age of Empires II: Definitive Edition  | ✅ |
| `age3`   | Age of Empires III: Definitive Edition | ❌ |
| `age4`   | Age of Empires IV: Anniversary Edition | ❌ |
| `athens` | Age of Mythology: Retold               | ❌ |

> **age4 and athens require a battle server.** These titles will not start
> without at least one battle server entry in `config.toml`. See
> [`server/BattleServers.md`](../../server/BattleServers.md)
> for setup instructions, then set `GAMES` to that value once configured.

### Networking

#### Single game — host networking

For a single game the simplest setup is `host` network mode. The container
shares the host's network stack and can bind port 443 and the UDP discovery
port (31978) directly on the host NIC.

> **Note:** On non-Linux hosts (Windows, macOS), Docker runs inside a VM and
> host networking may not work correctly for UDP broadcasts. Linux is the
> recommended host OS, which makes this setup well-suited for Linux-based
> NAS/server platforms.

#### Multiple games — ipvlan (recommended)

With `host` networking every container shares the **same** IP address, so
running two containers simultaneously will cause a port 443 conflict — the
second container fails to start. The same applies to the UDP discovery port
31978.

The solution is **ipvlan L2**: each container is assigned its own IP address
on the LAN while sharing the host's MAC address. This works without enabling
promiscuous mode on the host NIC and is compatible with managed switches that
enforce port security. macvlan is an alternative but requires promiscuous mode.

**One-time setup — create an ipvlan network** (adjust subnet, gateway, and
parent interface to match your LAN):

```bash
docker network create -d ipvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  -o ipvlan_mode=l2 \
  age-lan
```

**Run one container per game**, each with a unique static IP:

```bash
docker run -d \
  --name ageLANServer-age2 \
  --network age-lan --ip 192.168.1.201 \
  --restart unless-stopped \
  -v /path/to/age2/certificates:/app/resources/certificates \
  -v /path/to/age2/config:/app/resources/config \
  -v /path/to/age2/logs:/app/logs \
  -e GAMES=age2 \
  ghcr.io/indyone/agelanserver:latest

docker run -d \
  --name ageLANServer-age3 \
  --network age-lan --ip 192.168.1.202 \
  --restart unless-stopped \
  -v /path/to/age3/certificates:/app/resources/certificates \
  -v /path/to/age3/config:/app/resources/config \
  -v /path/to/age3/logs:/app/logs \
  -e GAMES=age3 \
  ghcr.io/indyone/agelanserver:latest
```

> **Each game needs its own volume paths** for certificates, config, and logs
> so they do not interfere with each other.

---

## Usage

### Option A — Pull the pre-built image

A pre-built image is published to the GitHub Container Registry:

```bash
docker pull ghcr.io/indyone/agelanserver:latest
```

Run it (example for Age of Empires II: DE, the default):

```bash
docker run -d \
  --name ageLANServer-age2 \
  --network host \
  --restart unless-stopped \
  -v /path/to/certificates:/app/resources/certificates \
  -v /path/to/config:/app/resources/config \
  -v /path/to/logs:/app/logs \
  -e GAMES=age2 \
  ghcr.io/indyone/agelanserver:latest
```

Replace `/path/to/certificates`, `/path/to/config`, and `/path/to/logs` with
directories on your host. The certificates directory must be writable; the
config directory can be empty to start with. To run more than one game, repeat
the command with a different `GAMES` value and unique volume paths per game.

---

### Option B — Build from source

All commands must be run from the **repository root**, not from this directory,
because the Dockerfile copies source from `server/`, `server-genCert/`, and
`common/`.

```bash
# Clone the repo (or your fork)
git clone https://github.com/indyone/ageLANServer.git
cd ageLANServer

# Build
docker build \
  -t ghcr.io/indyone/agelanserver:latest \
  -f tools/server-docker-unified/Dockerfile \
  .
```

---

### Option C — Docker Compose

A `compose.yml` is included in this directory. Run it from the repository root:

```bash
docker compose -f tools/server-docker-unified/compose.yml up -d
```

To build the image before starting:

```bash
docker compose -f tools/server-docker-unified/compose.yml up -d --build
```

Docker named volumes are used by default (`certs`, `config`, `logs`). To use
host paths instead, replace the volume entries in `compose.yml`:

```yaml
volumes:
  - /path/to/certificates:/app/resources/certificates
  - /path/to/config:/app/resources/config
  - /path/to/logs:/app/logs
```

---

## Configuration

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GAMES`  | Yes      | The single game to serve. Valid values: `age1`, `age2`, `age3`, `age4`, `athens`. Run one container per game for multiple titles. |

### Volumes

| Container path               | Required | Description |
|------------------------------|----------|-------------|
| `/app/resources/certificates`| Yes      | SSL certificates. Generated automatically on first run. Must be writable. |
| `/app/resources/config`      | No       | Drop a `config.toml` here to override server defaults. Must be writable (the entrypoint seeds per-game config files into this directory on first run). |
| `/app/logs`                  | Yes      | Server log output. Must be writable. |

### Server configuration via config.toml

On first run the entrypoint seeds a fully commented `config.toml.example` into
the config volume. To customise the server, rename it to `config.toml` and
uncomment or adjust the settings you need. The file covers authentication,
announce behaviour, per-game host bindings, battle servers, and more.

> **Note:** Leave `Games.Enabled` empty in `config.toml`. Game selection is
> handled by the `GAMES` environment variable, which takes precedence.

### Advanced server flags

Any extra flags supported by the `server` binary can be appended after the
image name (or set in `compose.yml` under `command:`). For example, to see all 
available flags:

```bash
docker run --rm ghcr.io/indyone/agelanserver:latest --help
```
