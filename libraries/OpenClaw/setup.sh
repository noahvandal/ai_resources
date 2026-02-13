#!/usr/bin/env bash
set -euo pipefail

# OpenClaw VPS bootstrap (Ubuntu 22.04/24.04)
# - Basic hardening (user, sshd, ufw, fail2ban, unattended upgrades)
# - Installs Node.js 22, pnpm, and OpenClaw
# - Leaves you at the point where you must enter API keys/tokens (interactive)

# Usage:
#   curl -fsSL <raw-url> | sudo bash
# or:
#   sudo bash setup.sh

if [[ ${EUID:-0} -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARNING: %s\n" "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

DEFAULT_USER="openclaw"
DEFAULT_SSH_PORT="22"

read -r -p "Create/use non-root user [${DEFAULT_USER}]: " OC_USER
OC_USER=${OC_USER:-$DEFAULT_USER}

read -r -p "SSH port [${DEFAULT_SSH_PORT}] (keep 22 unless you know why): " SSH_PORT
SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

read -r -p "Disable password SSH auth? [Y/n]: " DISABLE_PW
DISABLE_PW=${DISABLE_PW:-Y}

read -r -p "Disable root SSH login? [Y/n]: " DISABLE_ROOT
DISABLE_ROOT=${DISABLE_ROOT:-Y}

read -r -p "Install Tailscale? [y/N]: " INSTALL_TS
INSTALL_TS=${INSTALL_TS:-N}

read -r -p "Add swap file (recommended for 1–2GB RAM)? [Y/n]: " ADD_SWAP
ADD_SWAP=${ADD_SWAP:-Y}

log "Updating apt + installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg lsb-release \
  ufw fail2ban unattended-upgrades apt-listchanges \
  jq

log "Creating user: ${OC_USER} (if missing)"
if ! id -u "$OC_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$OC_USER"
fi

log "Adding ${OC_USER} to sudo group"
usermod -aG sudo "$OC_USER"

log "Configuring SSHD"
SSHD_CFG="/etc/ssh/sshd_config"
cp -a "$SSHD_CFG" "${SSHD_CFG}.bak.$(date +%s)"

# Ensure includes are respected; we will write our overrides to a drop-in.
mkdir -p /etc/ssh/sshd_config.d
OVR=/etc/ssh/sshd_config.d/99-openclaw-hardening.conf
cat > "$OVR" <<EOF
# OpenClaw hardening overrides
Port ${SSH_PORT}
Protocol 2

# Strong defaults
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding yes

# Auth
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

if [[ "$DISABLE_ROOT" =~ ^[Yy]$ ]]; then
  echo "PermitRootLogin no" >> "$OVR"
fi

# If user wants to keep passwords, flip the two lines.
if [[ ! "$DISABLE_PW" =~ ^[Yy]$ ]]; then
  sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$OVR"
  sed -i 's/^KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' "$OVR"
  warn "Password SSH auth kept enabled. Consider disabling it after you confirm key access works."
fi

# Ensure sshd is happy before restarting.
sshd -t
systemctl restart ssh

log "Configuring UFW firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow "${SSH_PORT}/tcp"

if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
  # Tailscale uses UDP 41641 by default.
  ufw allow 41641/udp
fi

ufw --force enable

log "Configuring fail2ban (basic sshd jail)"
JAIL_LOCAL=/etc/fail2ban/jail.local
cat > "$JAIL_LOCAL" <<'EOF'
[DEFAULT]
# Ban time in seconds (1h)
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
EOF
systemctl enable --now fail2ban

log "Enabling unattended upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades || true
systemctl enable --now unattended-upgrades || true

if [[ "$ADD_SWAP" =~ ^[Yy]$ ]]; then
  if ! swapon --show | grep -q .; then
    log "Adding 2G swapfile (/swapfile)"
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q '^/swapfile ' /etc/fstab; then
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  else
    log "Swap already present; skipping"
  fi
fi

log "Installing Node.js 22 (NodeSource)"
# NodeSource repo
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

require_cmd node
require_cmd npm

log "Installing pnpm"
corepack enable || true
corepack prepare pnpm@latest --activate || npm i -g pnpm

log "Installing OpenClaw (global)"
pnpm add -g openclaw@latest || npm i -g openclaw@latest

log "OpenClaw version"
openclaw --version || true

if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
  echo
  echo "Next step (manual): run 'tailscale up' and authenticate."
  echo "Then consider keeping OpenClaw Gateway loopback-only and accessing via Tailnet."
fi

cat <<EOF

============================================================
MANUAL STEPS (you must do these)
============================================================

1) On your laptop: add your SSH key for user '${OC_USER}'
   - Copy your public key:
       ssh-copy-id -p ${SSH_PORT} ${OC_USER}@<server-ip>

   Verify you can log in as the non-root user before you close your current session:
       ssh -p ${SSH_PORT} ${OC_USER}@<server-ip>

2) Run OpenClaw onboarding as '${OC_USER}':

   sudo -iu ${OC_USER}
   openclaw onboard --install-daemon

   This is where you'll enter:
   - Model API keys (OpenAI/Anthropic/etc.)
   - Telegram bot token / WhatsApp login / other channels

3) Recommended access pattern:
   - Keep gateway bound to 127.0.0.1
   - Use SSH tunnel from your laptop:
       ssh -N -L 18789:127.0.0.1:18789 -p ${SSH_PORT} ${OC_USER}@<server-ip>
     then open http://127.0.0.1:18789

NOTES
- If you changed SSH port, remember to update your client.
- If you enabled password auth, disable it once key auth works.
- Want Docker instead? See SETUP_OPENCLAW_VPS.md for a Docker-based option.

Done.
EOF
