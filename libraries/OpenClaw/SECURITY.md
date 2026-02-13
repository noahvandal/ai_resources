# OpenClaw Security

This document is a practical security checklist + threat model for self‑hosting OpenClaw.

**Default recommendation:** keep the OpenClaw Gateway **private** (loopback-only) and access it via **SSH tunneling** or **Tailscale**, rather than exposing it directly to the public internet.

> Audience: a capable engineer, but written so a non‑security specialist can follow.

---

## Executive summary (what matters most)

If you only do 7 things, do these:

1) **Do not expose the Gateway publicly** unless you must.
2) Use **SSH keys only** (no password SSH), and disable root login.
3) Enable a firewall (UFW) with **only** SSH (and optionally Tailscale UDP 41641).
4) Keep OpenClaw state (`~/.openclaw`) and your workspace backed up and access‑controlled.
5) Treat all tokens/credentials (Telegram bot token, model API keys, OAuth refresh tokens) as **production secrets**.
6) Keep the machine patched (unattended upgrades) and monitor logs.
7) Assume the agent can read files you allow it to read; avoid placing secrets in its workspace unless required.

---

## Risk → controls table

| Risk / concern | What can go wrong | Mitigating controls (best → acceptable) |
|---|---|---|
| **Public exposure of Gateway** | Remote attacker reaches Gateway UI/API; credential guessing; exploit surface expansion | **Best:** keep Gateway bound to `127.0.0.1` + access via SSH tunnel or Tailscale. **If exposed:** strict auth, TLS, firewall allowlist, rate limits, separate reverse proxy, rotate tokens. |
| **Credential leakage (API keys, bot tokens, OAuth refresh tokens)** | Account takeover, spend, message impersonation, data exfil | Store secrets outside the repo; restrict file permissions; rotate regularly; avoid printing tokens in logs; use least‑privileged keys; consider separate provider accounts for agents. |
| **Weak SSH posture** | VPS compromise via brute force / stolen password | SSH keys only; disable root login; change SSH port (optional); fail2ban; allowlist via firewall/Tailscale where possible. |
| **Supply chain risk (npm/global installs, scripts, updates)** | Malicious or compromised dependency executes on server | Pin versions when possible; verify sources; prefer official OpenClaw docs; keep a changelog; run as unprivileged user; consider containerizing. |
| **Excessive file access by agent** | Agent reads secrets from disk and leaks them via a message | Minimize workspace secrets; principle of least privilege for allowed directories/tools; store secrets in system keyrings/secret managers when possible. |
| **Channel abuse (Telegram/WhatsApp/etc.)** | Unauthorized users trigger actions; spam; social engineering | Lock pairing/approvals; restrict allowed chat IDs; require explicit confirmation for destructive actions; separate “Lead talks to user” model; audit logs. |
| **RCE via tool execution** | If attacker can influence prompts, they can coerce tool exec | Reduce tools available; restrict `exec` patterns; require approvals for risky actions; run agent under dedicated OS user; no root; sandbox where possible. |
| **Data retention / privacy** | Sensitive data stored forever in logs and workspace | Define retention policy; periodically purge logs; avoid storing secrets in plain text; encrypt backups; limit event logs to metadata when possible. |
| **Denial of service / resource exhaustion** | Gateway crashes, OOM, runaway builds, WS storms | Add swap; set CPU/memory limits; systemd restart policies; monitor; run builds with quotas; consider separate machine for heavy workloads. |
| **Backups are missing or insecure** | You lose state or leak it via a backup bucket | Encrypted backups; access controls; test restore; separate backup destination; rotate backup keys. |

---

## Deep dives

### 1) Public exposure of the Gateway

**Best practice:** keep the Gateway reachable only from trusted networks.

**Recommended patterns**

- **SSH tunnel** (simple and reliable)
  - VPS binds Gateway to `127.0.0.1:18789`
  - You forward the port from your laptop:
    - `ssh -N -L 18789:127.0.0.1:18789 openclaw@<server>`

- **Tailscale**
  - Use Tailscale to reach the box privately
  - Prefer: Gateway still loopback-only, then access via SSH (over Tailscale) and tunnel
  - Alternative: bind Gateway to Tailnet interface (only reachable inside Tailnet)

**If you must expose publicly**

- Put it behind a reverse proxy with TLS
- Restrict by IP allowlist (or mTLS)
- Enforce strong auth (token + password if supported)
- Monitor logs and rotate secrets

### 2) Credential leakage

Common secrets involved in OpenClaw setups:

- LLM provider API keys
- Telegram bot token
- OAuth refresh tokens (e.g., Claude Max OAuth)
- Any third-party integrations

Controls:

- Keep secrets out of git repos and out of the agent workspace
- Use file perms: `chmod 600` for credential files
- Rotate tokens regularly (treat compromise as inevitable)
- Prefer separate accounts for automation vs. personal use

### 3) SSH hardening

Minimum:

- `PasswordAuthentication no`
- `PermitRootLogin no`
- UFW allows only your SSH port
- fail2ban enabled

Optional:

- Change SSH port (reduces noise, not a real security boundary)
- Use Tailscale + disable public SSH entirely (advanced)

### 4) Supply chain and update safety

Risks:

- Installing global CLIs and dependencies that run as your user
- Running convenience scripts from the internet

Controls:

- Prefer official docs and known sources
- Keep installs non-root where possible
- Consider Docker if you want reproducible builds and a smaller “host” footprint

### 5) Tool execution and least privilege

If your agent can run shell commands, assume it can:

- Read any file you allow access to
- Exfiltrate via messaging channels (if configured)
- Modify the workspace

Controls:

- Run OpenClaw under a dedicated unprivileged OS user
- Don’t grant tool access to `/root`, `/etc`, or home directories with unrelated secrets
- Add confirmation steps for destructive actions

### 6) Logging, retention, and privacy

Controls:

- Decide what you log (metadata vs. content)
- Purge or rotate logs
- Encrypt backups
- Avoid logging secrets

---

## Suggested baseline (quick checklist)

- [ ] Gateway bound to loopback or Tailnet only
- [ ] SSH keys only; root login disabled
- [ ] UFW enabled; minimal inbound ports
- [ ] fail2ban enabled
- [ ] unattended-upgrades enabled
- [ ] swap configured on small VPS
- [ ] backups enabled + encrypted + restore tested
- [ ] secrets stored safely, rotated periodically
