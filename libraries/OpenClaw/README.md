# OpenClaw (Start Here)

This folder contains practical, copy/paste‑friendly resources for running **OpenClaw**.

## Who this is for

- **New to OpenClaw:** start with **Quickstart**.
- **Some experience:** skim **VPS Setup** + **Security** and jump into the setup script.

## Recommended setup paths

### 1) VPS + SSH tunnel (recommended default)
Best balance of simplicity and safety.

- Guide: [`SETUP_OPENCLAW_VPS.md`](./SETUP_OPENCLAW_VPS.md)
- Script: [`setup.sh`](./setup.sh)

### 2) VPS + Tailscale
Best when you want remote access without exposing services publicly.

- Security notes: [`SECURITY.md`](./SECURITY.md)
- Troubleshooting: [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md)

### 3) Docker on a VPS
Best if you want reproducible deployments and cleaner dependency isolation.

- See: [`SETUP_OPENCLAW_VPS.md`](./SETUP_OPENCLAW_VPS.md) (Docker section)

## Quick links

- Quickstart: [`QUICKSTART.md`](./QUICKSTART.md)
- Troubleshooting: [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md)
- Security / threat model: [`SECURITY.md`](./SECURITY.md)
- Glossary: [`GLOSSARY.md`](./GLOSSARY.md)

## What you should expect (high level)

1) Provision an Ubuntu VPS
2) Run `setup.sh` to harden the box + install OpenClaw
3) Run `openclaw onboard --install-daemon` to configure models/channels
4) Access the Gateway UI via SSH tunnel or Tailscale
