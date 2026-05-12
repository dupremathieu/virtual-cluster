#!/usr/bin/env bash
# One-shot configuration of fence_virtd on the sandbox host.
# Supported host OS: Fedora / Ubuntu
# Runs the TCP listener on port 1229 with the libvirt backend.
set -euo pipefail

FENCE_KEY="${1:-/etc/cluster/fence_virt.key}"
FENCE_CONF="/etc/fence_virt.conf"

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

OS=$(detect_os)

case "$OS" in
  fedora)
    echo "→ Detected Fedora host"
    sudo dnf install -y \
      fence-virt fence-virtd fence-virtd-tcp fence-virtd-libvirt
    ;;
  ubuntu|debian)
    echo "→ Detected Ubuntu/Debian host"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
      fence-virt fence-virtd
    ;;
  *)
    echo "ERROR: unsupported OS '$OS'. Please install fence-virt packages manually."
    echo "  Fedora:  dnf install fence-virt fence-virtd fence-virtd-tcp fence-virtd-libvirt"
    echo "  Ubuntu:  apt install fence-virt fence-virtd"
    exit 1
    ;;
esac

# Generate shared key if it doesn't exist
if [ ! -f "$FENCE_KEY" ]; then
  echo "→ Generating shared key at $FENCE_KEY"
  sudo mkdir -p "$(dirname "$FENCE_KEY")"
  sudo dd if=/dev/urandom bs=32 count=1 of="$FENCE_KEY" 2>/dev/null
  sudo chmod 0400 "$FENCE_KEY"
else
  echo "→ Key already exists at $FENCE_KEY (not overwriting)"
fi

# Write fence_virtd configuration
echo "→ Writing $FENCE_CONF"
{
  if [ "$OS" = "fedora" ]; then
    MODULE_PATH="/usr/lib64/fence-virt"
  else
    MODULE_PATH="/usr/lib/x86_64-linux-gnu/fence-virt"
  fi
  sudo tee "$FENCE_CONF" > /dev/null <<EOCONF
fence_virtd {
    listener = "tcp";
    backend = "libvirt";
    module_path = "$MODULE_PATH";
}

listeners {
    tcp {
        key_file = "$FENCE_KEY";
        port = "1229";
        address = "0.0.0.0";
        family = "ipv4";
    }
}

backends {
    libvirt {
        uri = "qemu:///system";
    }
}
EOCONF
}

sudo chmod 0644 "$FENCE_CONF"

# Start and enable fence_virtd
echo "→ Starting fence_virtd"
sudo systemctl enable --now fence_virtd 2>/dev/null || true
sudo systemctl status fence_virtd --no-pager || true

# Open firewall port
echo "→ Opening firewall port 1229/tcp"
if [ "$OS" = "fedora" ]; then
  sudo firewall-cmd --zone=libvirt --add-rich-rule='rule family="ipv4" port port="1229" protocol="tcp" accept' 2>/dev/null || true
  sudo firewall-cmd --zone=libvirt --add-rich-rule='rule family="ipv4" port port="1229" protocol="tcp" accept' --permanent 2>/dev/null || true
elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
  sudo ufw allow 1229/tcp 2>/dev/null || true
fi

echo ""
echo "fence_virtd is now running on $(hostname)."
echo "Next, push the key to VMs:"
echo "  make fence-key-push"
echo "  make ansible-setup-ha"
