# OpenClaw Quickstart (VPS + SSH tunnel)

Goal: get from “fresh Ubuntu VPS” → “OpenClaw Gateway UI loads locally in your browser.”

> This uses the safest *default* pattern: Gateway bound to loopback on the VPS, accessed via an SSH tunnel.

## Prereqs

- A VPS running **Ubuntu 22.04 or 24.04**
- SSH access
- A local terminal on your laptop

## Step 1 — Create an SSH key (if you don’t already have one)

On your laptop, check for an existing key:

```bash
ls -la ~/.ssh
```

If you don’t see something like `id_ed25519` + `id_ed25519.pub`, create one:

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

Now copy the public key (you’ll paste it during VPS setup):

```bash
cat ~/.ssh/id_ed25519.pub
```

## Step 2 — SSH into your VPS as root

```bash
ssh root@<server-ip>
```

## Step 3 — Run the setup script

On the VPS:

```bash
apt update && apt install -y curl

curl -fsSL https://raw.githubusercontent.com/noahvandal/ai_resources/main/libraries/OpenClaw/setup.sh -o setup.sh
sudo bash setup.sh
```

During setup, you’ll be prompted to **paste your SSH public key** (recommended).

The script will:
- create a non-root `openclaw` user
- add your SSH key to `~openclaw/.ssh/authorized_keys`
- install basic security tooling (UFW, fail2ban, unattended upgrades)
- install Node 22 + pnpm
- install the OpenClaw CLI

**Important:** Don’t close your root SSH session until you confirm you can log in as the new non-root user.

## Step 4 — Log in as the non-root user

From your laptop:

```bash
ssh -p 22 openclaw@<server-ip>
```

(If you changed the SSH port in the script prompts, use that port.)

## Step 5 — Run OpenClaw onboarding

On the VPS (as the non-root user):

```bash
openclaw onboard --install-daemon
```

You’ll be prompted for:
- model provider keys (Anthropic/OpenAI/etc.)
- channel setup (Telegram/WhatsApp/etc.)
- gateway auth/token

## Step 6 — Open the Gateway UI via SSH tunnel

On your laptop:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@<server-ip>
```

Then open:

- http://127.0.0.1:18789/

## What “success” looks like

- The page loads and asks for your token (or shows the UI)
- `openclaw status` reports the gateway running

If you get stuck: see [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md).
