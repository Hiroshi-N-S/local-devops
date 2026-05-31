#!/bin/sh
set -euo pipefail

# Installing dependencies.

info "Installing dependencies."

sudo apt update && sudo apt upgrade -y && sudo apt install -y --no-install-recommends \
  yq

info "Dependencies installed successfully."
