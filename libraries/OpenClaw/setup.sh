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

echo
echo "SSH KEY SETUP (recommended)"
echo "- On your laptop, generate a key if you don't have one:"
echo "    ssh-keygen -t ed25519 -C \"your_email@example.com\""
echo "- Then copy your public key:"
echo "    cat ~/.ssh/id_ed25519.pub"
echo
echo "Paste the full line (starts with 'ssh-ed25519 ...') when prompted below."
echo
read -r -p "Paste your SSH public key for the new '${OC_USER}' user (ed25519 .pub). Leave blank to skip for now: " SSH_PUBKEY
SSH_PUBKEY=${SSH_PUBKEY:-}

log "Updating apt + installing base packages"
# We update the package list so Ubuntu knows about the latest security updates,
# then install the basic tools we need for the rest of this script.
#
# - curl/git/ca-certificates: downloading + cloning
# - ufw: simple firewall
# - fail2ban: bans brute-force SSH attempts
# - unattended-upgrades: automatic security updates
# - jq: useful JSON utility (handy for debugging)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg lsb-release \
  ufw fail2ban unattended-upgrades apt-listchanges \
  jq

log "Creating user: ${OC_USER} (if missing)"
# We prefer running services as a non-root user for safety.
# This creates a new user if it doesn't exist.
if ! id -u "$OC_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$OC_USER"
fi

log "Adding ${OC_USER} to sudo group"
# Allows the user to run administrative commands via sudo.
usermod -aG sudo "$OC_USER"

if [[ -n "$SSH_PUBKEY" ]]; then
  log "Authorizing your SSH public key for user: ${OC_USER}"
  # This avoids relying on ssh-copy-id (which requires a working login method).
  # We install the key *before* hardening SSH so we don't lock you out.
  HOME_DIR="/home/${OC_USER}"
  SSH_DIR="${HOME_DIR}/.ssh"
  AUTH_KEYS="${SSH_DIR}/authorized_keys"

  install -d -m 700 -o "$OC_USER" -g "$OC_USER" "$SSH_DIR"
  touch "$AUTH_KEYS"
  chown "$OC_USER":"$OC_USER" "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"

  # Append the key if it's not already present
  if ! grep -Fqx "$SSH_PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
    echo "$SSH_PUBKEY" >>"$AUTH_KEYS"
  fi
else
  warn "No SSH public key provided. You'll need to add one later before disabling password/root SSH."
fi

log "Configuring SSHD"
# SSH is how you'll log into the server.
# Here we apply safer defaults:
# - optionally move SSH to a different port
# - disable password logins (use SSH keys)
# - optionally disable root login
#
# IMPORTANT: Make sure you have a working SSH key login before you apply strict settings.
# We install your public key earlier in this script to make that easier.
#
# We write our settings as a drop-in file so it’s easy to find and revert.
SSHD_CFG="/etc/ssh/sshd_config"
cp -a "$SSHD_CFG" "${SSHD_CFG}.bak.$(date +%s)"

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

# Sanity-check the SSH configuration before restarting the SSH service.
# If this check fails, we STOP rather than risk locking you out.
sshd -t
systemctl restart ssh

log "Configuring UFW firewall"
# UFW is Ubuntu's easy firewall tool.
# We block all inbound traffic by default, then allow only what we need.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow inbound SSH so you can log in.
ufw allow "${SSH_PORT}/tcp"

if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
  # Tailscale typically uses UDP 41641 for peer-to-peer connections.
  ufw allow 41641/udp
fi

ufw --force enable

log "Configuring fail2ban (basic sshd jail)"
# fail2ban watches logs and bans IPs that repeatedly fail login.
# This helps against noisy automated SSH brute-force attempts.
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
# unattended-upgrades automatically installs important security patches.
# On a VPS this is one of the simplest "set it and forget it" safety wins.
dpkg-reconfigure -f noninteractive unattended-upgrades || true
systemctl enable --now unattended-upgrades || true

if [[ "$ADD_SWAP" =~ ^[Yy]$ ]]; then
  # Swap gives the server a little "overflow" memory.
  # It can prevent sudden crashes on small VPSes (1–2GB RAM).
  if ! swapon --show | grep -q .; then
    log "Adding 2G swapfile (/swapfile)"
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Make swap persist across reboots.
    if ! grep -q '^/swapfile ' /etc/fstab; then
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  else
    log "Swap already present; skipping"
  fi
fi

log "Installing Node.js 22 (NodeSource)"
# OpenClaw runs on Node.js.
# We install Node.js 22 using the official NodeSource repo for Ubuntu.
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

require_cmd node
require_cmd npm

log "Installing pnpm"
# pnpm is a fast Node.js package manager.
# We enable it via Corepack (built into modern Node).
#
# Note: pnpm's *global* installs can fail on fresh machines if PNPM_HOME isn't set
# (ERR_PNPM_NO_GLOBAL_BIN_DIR). To keep this script beginner-friendly, we do NOT
# rely on pnpm for global installs.
corepack enable || true
corepack prepare pnpm@latest --activate || npm i -g pnpm

log "Installing OpenClaw (global)"
# We install OpenClaw using npm because npm's global bin path is configured by default.
# This avoids pnpm global-bin-dir setup issues on fresh VPSes.
npm i -g openclaw@latest

log "OpenClaw version"
openclaw --version || true

if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
  log "Installing Tailscale"
  # Tailscale is an easy way to access your server privately without opening
  # extra public firewall ports.
  curl -fsSL https://tailscale.com/install.sh | sh
  echo
  echo "Next step (manual): run 'tailscale up' and authenticate."
  echo "Then consider keeping OpenClaw Gateway loopback-only and accessing via Tailnet."
fi

cat <<EOF

============================================================
MANUAL STEPS (you must do these)
============================================================

1) Verify SSH key login works for user '${OC_USER}'

   On your laptop, if you **don't already have an SSH key**, create one:

       ssh-keygen -t ed25519 -C "your_email@example.com"

   Then test login:

       ssh -p ${SSH_PORT} ${OC_USER}@<server-ip>

   Notes:
   - If you pasted your public key when this script prompted you, this should work immediately.
   - If you skipped the key prompt, add your key to /home/${OC_USER}/.ssh/authorized_keys as root.

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
