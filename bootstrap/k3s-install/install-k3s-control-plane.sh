#!/bin/sh
set -euo pipefail

K3S_VERSION=${K3S_VERSION:-"v1.35.4+k3s1"}

SCRIPT_DIR=$(dirname "$0")
K3S_CONFIGS_DIR="$SCRIPT_DIR/k3s-configs"

# Running distribution-specific configuration before installing K3s.

DISTRO=$(source /etc/os-release; echo "${ID}-${VERSION_ID}")

if [ ! -f "$SCRIPT_DIR/distribution-configs/${DISTRO}.sh" ]; then
  printf "\e[31m[ERROR] %s\e[m\n" "Unsupported distribution: ${DISTRO}"
  exit 1
fi

printf "\e[32m[INFO] %s\e[m\n" "Running distribution-specific configuration for ${DISTRO}."

. "$SCRIPT_DIR/distribution-configs/${DISTRO}.sh"

# Installing K3s on the control plane node.

if ! command -v k3s >/dev/null 2>&1; then
  sudo mkdir -p /etc/rancher/k3s
  for config_file in "$K3S_CONFIGS_DIR"/*.yaml; do
    sudo cp "$config_file" /etc/rancher/k3s/
    sudo chown root:root /etc/rancher/k3s/$(basename "$config_file")
    sudo chmod 644 /etc/rancher/k3s/$(basename "$config_file")
  done

  printf "\e[32m[INFO] %s\e[m\n" "K3s is NOT installed. Installing K3s on the control plane node."

  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s -

  mkdir -p ~/.kube
  ln -s /etc/rancher/k3s/k3s.yaml ~/.kube/config

  printf "\e[32m[INFO] %s\e[m\n" "K3s installation on the control plane node completed."
fi
