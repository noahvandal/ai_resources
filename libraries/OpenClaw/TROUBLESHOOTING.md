# OpenClaw Troubleshooting

This is a grab bag of common “it doesn’t work” issues when self-hosting OpenClaw.

## 1) Gateway UI won’t load

### Check: is the gateway running?

On the VPS:

```bash
openclaw status
openclaw gateway status
```

If you installed the daemon as a **systemd user service**, check logs:

```bash
journalctl --user -u openclaw-gateway.service -f
```

### Check: are you using an SSH tunnel?

If the gateway binds to `127.0.0.1`, it is **not** reachable from the internet directly.
From your laptop:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@<server-ip>
```

Then open:
- http://127.0.0.1:18789/

## 2) “Connection refused” / port not reachable

Common causes:

- you forgot the SSH tunnel
- the gateway is bound to loopback (by design)
- the gateway isn’t running
- you changed the gateway port

On the VPS:

```bash
ss -lntp | rg 18789 || true
```

## 3) The gateway service starts then stops

This often means:

- missing runtime dependency
- PATH issues inside systemd
- out of memory

Check logs:

```bash
journalctl --user -u openclaw-gateway.service -n 200 --no-pager
```

If OOM is suspected:

```bash
free -h
journalctl -k -n 200 --no-pager | rg -i "oom|killed" || true
```

## 4) Out of memory (OOM) / random SIGKILL

Symptoms:
- the process suddenly dies
- builds die with exit code 137

Fixes:
- add swap (2GB is common for small VPS)
- upgrade RAM (2GB+ recommended)
- reduce concurrency for builds

## 5) Claude rate limits show null / token expired

If you’re using Claude Max OAuth usage checks and they appear expired:

- run the Claude CLI in a real terminal session (TTY) on the host
- then retry your usage check

(Exact commands vary by environment; the important part is that the CLI refreshes auth.)

## 6) UFW/Firewall broke SSH

If you changed SSH ports, make sure UFW allows the new port.

On the VPS:

```bash
ufw status verbose
```

If you’re locked out, use your VPS provider’s console access to fix UFW rules.

## 7) `ssh-copy-id` prompts for a password / “No identities found”

We avoid relying on `ssh-copy-id` in this repo, because on hardened servers:
- password auth is disabled (so ssh-copy-id can't authenticate via password)
- many users don't have a key yet ("No identities found")

Instead:

1) Make sure you have a key locally:
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

2) Copy your public key:
```bash
cat ~/.ssh/id_ed25519.pub
```

3) Re-run the VPS setup script and paste the key when prompted.

If your previous run got interrupted, that’s fine — it’s designed to resume safely:

```bash
sudo bash setup.sh
```

If you must install it manually as root, append it to:
- `/home/openclaw/.ssh/authorized_keys`

## 8) pnpm global install error (ERR_PNPM_NO_GLOBAL_BIN_DIR)

On fresh machines, pnpm can’t always figure out where to put global binaries.

In this repo’s setup script, we avoid this by installing OpenClaw globally with **npm**.

If you do want pnpm globals later, run:

```bash
pnpm setup
# restart your shell
```

## 9) OAuth / “needs browser” logins

Some tools (Gmail/OAuth flows) require browser interaction.
Common workarounds:

- do the auth from a machine with a browser
- use SSH port forwarding
- use device-code flows if supported

