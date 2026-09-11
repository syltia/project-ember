#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

echo "--- 1. Updating Debian ---"
apt update
apt upgrade -y

echo "--- 2. Installing base development tools ---"
apt install -y \
    build-essential \
    cmake \
    ninja-build \
    clang \
    lldb \
    gdb \
    git \
    curl \
    wget \
    tmux \
    pkg-config \
    ca-certificates \
    gnupg \
    unzip \
    zip \
    libssl-dev \
    zlib1g-dev

if ! command -v ufw >/dev/null 2>&1; then
    echo "--- Installing UFW ---"
    apt install -y ufw
else
    echo "--- UFW is already installed ---"
fi

echo "--- 3. Installing PostgreSQL ---"
apt install -y \
    postgresql \
    postgresql-contrib \
    libpq-dev

systemctl enable postgresql
systemctl start postgresql

echo "--- 4. Verifying PostgreSQL ---"
if ! pg_isready >/dev/null 2>&1; then
    echo "PostgreSQL is not ready."
    exit 1
fi

POSTGRES_VERSION=$(sudo -u postgres psql -Atqc "SHOW server_version;")
echo "PostgreSQL is online: $POSTGRES_VERSION"

echo "--- 5. Configuring SSH ---"
if grep -q '^#PermitRootLogin prohibit-password' /etc/ssh/sshd_config; then
    sed -i '0,/^#PermitRootLogin prohibit-password/s//PermitRootLogin yes/' /etc/ssh/sshd_config
elif grep -q '^PermitRootLogin ' /etc/ssh/sshd_config; then
    sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
else
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
fi

systemctl restart ssh

echo "--- 6. Configuring UFW firewall ---"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 3724/tcp comment 'WoW Auth'
ufw allow 8085/tcp comment 'WoW World'
ufw --force enable
ufw status verbose

echo "--- 7. Configuring GRUB ---"
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=1/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
update-grub

echo "--- 8. Configuring static IP from current network values ---"
INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
CURRENT_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet )\d+(\.\d+){3}' | head -n1)
GATEWAY=$(ip route | awk '/default/ {print $3; exit}')

if [ -n "$INTERFACE" ] && [ -n "$CURRENT_IP" ] && [ -n "$GATEWAY" ]; then
    echo "Applying static IP: $CURRENT_IP on interface $INTERFACE (Gateway: $GATEWAY)"

    cat <<EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet static
    address $CURRENT_IP
    netmask 255.255.255.0
    gateway $GATEWAY
    dns-domain azeroth.eras
    dns-nameservers 8.8.8.8 1.1.1.1
EOF

    systemctl restart networking.service
else
    echo "Could not determine the current network configuration. Static IP step skipped."
fi

echo "--- 9. Creating Ember workspace ---"
mkdir -p /root/ember/{src,build,logs,sql}

echo "--- 10. Creating useful aliases ---"
cat <<'EOF' >> /root/.bashrc

# Project Ember
alias ember='cd /root/ember'
alias psql-ember='sudo -u postgres psql'
alias pgstatus='systemctl status postgresql --no-pager'
alias pgrestart='systemctl restart postgresql'
alias qqq='shutdown now'
EOF

echo "=================================================================="
echo "Project Ember base VM is ready."
echo "Debian + PostgreSQL installed successfully."
echo "UFW enabled: SSH 22/tcp, WoW Auth 3724/tcp, WoW World 8085/tcp."
echo "Workspace: /root/ember"
echo "No AzerothCore/MySQL/MariaDB components were installed by this script."
echo "=================================================================="
