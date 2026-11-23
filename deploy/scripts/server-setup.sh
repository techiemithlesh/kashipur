#!/usr/bin/env bash
# One-time hardening + Docker install for a fresh Ubuntu 22.04/24.04 VPS (Hostinger KVM).
# Run as root:   curl -fsSL <raw url> -o server-setup.sh   (or scp it)   then: bash server-setup.sh
#
# What it does:
#   - creates a 'deploy' user (SSH key login only) and copies root's authorized_keys to it
#   - disables root SSH login and password authentication (only after verifying a key exists)
#   - firewall (ufw): allow 22, 80, 443 only
#   - fail2ban for SSH, unattended security upgrades, swap if none
#   - Docker Engine + compose plugin, with log rotation defaults
#   - /opt/swm owned by deploy
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
APP_DIR="${APP_DIR:-/opt/swm}"

[ "$(id -u)" = "0" ] || { echo "Run as root" >&2; exit 1; }

echo "==> Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl git ufw fail2ban unattended-upgrades gnupg

echo "==> Deploy user"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
if [ -s /root/.ssh/authorized_keys ] && [ ! -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]; then
  install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
fi

echo "==> SSH hardening"
if [ -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]; then
  cat > /etc/ssh/sshd_config.d/10-swm-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
# Needed for pgAdmin/psql SSH tunnels to 127.0.0.1:5432.
AllowTcpForwarding local
X11Forwarding no
MaxAuthTries 3
AllowUsers $DEPLOY_USER
EOF
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
  echo "    Root login and passwords disabled. Log in as: ssh $DEPLOY_USER@<server-ip>"
else
  echo "    !! No SSH key found for $DEPLOY_USER; NOT disabling password login."
  echo "    !! Add your public key to /home/$DEPLOY_USER/.ssh/authorized_keys and re-run."
fi

echo "==> Firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable
# Note: Docker-published ports bypass ufw. That's why only Caddy publishes public ports
# and PostgreSQL is bound to 127.0.0.1 in docker-compose.prod.yml.

echo "==> fail2ban + automatic security updates"
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Swap"
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Docker"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck source=/dev/null
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
mkdir -p /etc/docker
[ -f /etc/docker/daemon.json ] || cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true
}
EOF
systemctl enable --now docker
systemctl restart docker
usermod -aG docker "$DEPLOY_USER"

echo "==> App directory"
install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR"

echo "Done. Next: log in as $DEPLOY_USER and follow deploy/README.md (clone repo into $APP_DIR)."
