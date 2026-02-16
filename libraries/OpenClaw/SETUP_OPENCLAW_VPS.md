# OpenClaw VPS Setup (Basic Guide)

This guide walks you through the **easiest, lowest-drama** way to self-host OpenClaw on a VPS (Ubuntu 24.04 recommended), including basic hardening and safe remote access.

> Philosophy: **keep the Gateway private** (loopback-only) and access it via **SSH tunnel** or **Tailscale**. Avoid exposing the Gateway publicly unless you know exactly why you need it.

## 0) What you’re building

- A small VPS (Hetzner/DigitalOcean/etc.) running:
  - Node.js 22+
  - OpenClaw Gateway as a service (systemd)
  - Persistent state in `~/.openclaw/`
- Optional: Tailscale for easy, secure remote access

## 1) Pick where to host (quick recommendations)

### Paid + easiest UX
- **DigitalOcean / Linode / Vultr**: simplest dashboards, predictable networking.
- A 1 vCPU / 1GB RAM box *works*, but **2GB RAM** is more comfortable.

### Best value
- **Hetzner**: excellent price/performance.

### Free (more finicky)
- **Oracle Cloud Always Free (ARM)**: great specs for $0, but setup can be more annoying and some binaries are arch-specific.

**OS:** Ubuntu 24.04 LTS is the default recommendation.

## 2) VPS hardening checklist (minimum viable)

Do these before you start wiring bots/channels:

1. **Create a non-root user** (e.g. `openclaw`) and use SSH keys.
2. **Disable root SSH login**.
3. **Disable password auth** (use SSH keys only).
4. Enable automatic security updates:
   - `unattended-upgrades`
5. Turn on a firewall (UFW):
   - allow `OpenSSH`
   - (optional) allow Tailscale UDP 41641
6. Install and enable **fail2ban**.
7. Add **swap** on low-memory VPSes (1–2GB RAM).

## 3) Install dependencies

- Node.js **22+**
- `git`, `curl`, `ca-certificates`

Then install OpenClaw (global):

```bash
npm i -g openclaw@latest
openclaw --version
```

## 4) Run OpenClaw onboarding

Run the interactive wizard:

```bash
openclaw onboard --install-daemon
```

This typically walks you through:
- Gateway token / auth
- Model provider keys (Claude/OpenAI/etc.)
- Channel config (Telegram/WhatsApp/etc.)
- Installing a background service

## 5) Access the Control UI (recommended patterns)

### Option A (recommended): SSH tunnel
Keep Gateway bound to loopback on the VPS.

On your laptop:
```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@YOUR_VPS_IP
```
Then open:
- `http://127.0.0.1:18789/`

### Option B: Tailscale (recommended for "remote but private")
Install Tailscale on the VPS and your laptop, then access via MagicDNS/IP.

**Two good patterns:**

1) **Keep OpenClaw bound to loopback** (127.0.0.1) and use Tailscale for admin access + SSH into the box, then run the same SSH tunnel as above.

2) **Bind OpenClaw to the Tailnet interface** (so it’s reachable only inside your Tailnet). Depending on your OpenClaw config, that can look like either:
- running the Gateway on a Tailnet bind address, or
- using **Tailscale Serve** to publish an HTTPS URL that still targets a loopback-only service.

If you do choose to expose ports publicly, treat it like a real production service: TLS, strict auth, firewall rules, monitoring.

## 6) Docker-based option (when you want maximum reproducibility)

If you prefer containerized deployments (and are comfortable with Docker), running OpenClaw via **Docker Compose** can be a great option:

- Easier to reproduce the same setup across VPS providers
- Cleaner dependency isolation
- Straightforward upgrades/rollbacks

Key idea: **persist** the OpenClaw state directory (`~/.openclaw`) as a host-mounted volume, otherwise you’ll lose credentials/state on container rebuild.

Recommended next step:
- Follow the official OpenClaw Docker guidance and adapt it to your VPS + persistence needs.

## 7) Where state lives (backup!)

Everything important is in:
- `~/.openclaw/` (config, tokens, sessions)
- `~/.openclaw/workspace/` (your agent workspace files)

Back it up periodically:

```bash
tar -czf openclaw-backup.tgz ~/.openclaw
```

## 8) Common “gotchas”

- **RAM/OOM:** add swap or upgrade the VPS.
- **PATH/systemd:** if a service can’t find `node`/`openclaw`, check the systemd unit environment.
- **OAuth CLIs:** Gmail/Google CLIs may require browser-based auth; do this over SSH with port-forwarding or use device-code flows if supported.
- **Tailscale expectations:** Tailscale doesn’t automatically secure an app that’s bound to `0.0.0.0` on the public interface. Prefer loopback-only + Serve, or bind specifically to the Tailnet.

## 9) Quick commands

```bash
# Gateway status
openclaw status
openclaw gateway status

# systemd user service logs (if installed as user unit)
journalctl --user -u openclaw-gateway.service -f

# restart
openclaw gateway restart
```

---

## Next step

Use the automation script in this folder:
- `libraries/OpenClaw/setup.sh`

It hardens the VPS and installs OpenClaw, then stops and prompts you for the manual steps (keys/tokens/OAuth).
