#!/bin/sh
set -euo pipefail

VELERO_VER=${VELERO_VER:-'1.16.2'}

# Creating missing /dev/kmsg to avoid k3s installation errors.

if [ ! -e /dev/kmsg ]; then
  info "Creating /dev/kmsg as a symlink to /dev/console to avoid k3s installation errors."

  sudo ln -s /dev/console /dev/kmsg
  echo 'L /dev/kmsg - - - - /dev/console' | sudo tee /etc/tmpfiles.d/kmsg.conf

  info " -> /dev/kmsg created successfully."
fi

# Installing dependencies for K3s.

info "Installing dependencies for K3s."

sudo apt update && sudo apt upgrade -y && sudo apt install -y --no-install-recommends \
  curl \
  ca-certificates

info "Dependencies for K3s installed successfully."

# Installing helm.

if ! command -v helm >/dev/null 2>&1; then
  info "Helm is NOT installed. Installing Helm."

  sudo apt-get install curl gpg apt-transport-https --yes
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt update
  sudo apt install -y --no-install-recommends helm

  info " -> Helm installation completed."
fi

# Installing velero

if ! command -v velero >/dev/null 2>&1; then
  info "Velero is NOT installed. Installing Velero."

  VELERO_PKG_NAME="velero-v${VELERO_VER}-linux-$(dpkg --print-architecture)"
  curl -fsSL https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VER}/${VELERO_PKG_NAME}.tar.gz |\
    sudo tar -zxv -C /usr/local/bin --strip-components 1 ${VELERO_PKG_NAME}/velero
  sudo chmod +x /usr/local/bin/velero

  info " -> Velero installation completed."
fi
