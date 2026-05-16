#!/bin/sh
set -euo pipefail

K3S_VERSION=${K3S_VERSION:-"v1.35.4+k3s1"}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT_DIR="$SCRIPT_DIR/../.."
UTILITY_SCRIPTS_DIR="$REPO_ROOT_DIR/utility-scripts"

K3S_CONFIGS_DIR="$SCRIPT_DIR/k3s-configs"

#
# Import utility functions.
#

. "$UTILITY_SCRIPTS_DIR/utilities.sh"

#
# Running distribution-specific configuration before installing K3s.
#

DISTRO=$(source /etc/os-release; echo "${ID}-${VERSION_ID}")

if [ ! -f "$SCRIPT_DIR/distribution-configs/${DISTRO}.sh" ]; then
  error "Unsupported distribution: ${DISTRO}"
fi

info "Running distribution-specific configuration for ${DISTRO}."

. "$SCRIPT_DIR/distribution-configs/${DISTRO}.sh"

#
# Installing K3s on the control plane node.
#

if ! command -v k3s >/dev/null 2>&1; then
  sudo mkdir -p /etc/rancher/k3s
  for config_file in "$K3S_CONFIGS_DIR"/*.yaml; do
    sudo cp "$config_file" /etc/rancher/k3s/
    sudo chown root:root /etc/rancher/k3s/$(basename "$config_file")
    sudo chmod 644 /etc/rancher/k3s/$(basename "$config_file")
  done

  info "K3s is NOT installed. Installing K3s on the control plane node."

  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s -

  mkdir -p ~/.kube
  ln -nfs /etc/rancher/k3s/k3s.yaml ~/.kube/config

  info "K3s installation on the control plane node completed."

  info "Waiting for any pods to be deployed."
  until kubectl get pods -n kube-system --no-headers 2>&1 | grep -qv "No resources found"; do
    info " -> Checking for any pods"
    info " -> Retrying in 10 seconds..."
    sleep 10
  done
  info "Waiting for any pods to be deployed: DONE"

  info "Waiting for all pods to become running..."
  until [ -z "$(kubectl get pods -n kube-system --no-headers | grep -v Completed | awk -F'[/ ]+' '$2 != $3 || $4 != "Running"')" ]
  do
    info " -> Checking if pods are running"
    info " -> Retrying in 10 seconds..."
    sleep 10
  done
  info "Waiting for all pods to become running...: DONE"
fi
