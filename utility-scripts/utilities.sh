#!/bin/bash
set -euo pipefail

debug() {
  printf "\e[36m[DEBUG] %s\e[m\n" "$@"
}

info() {
  printf "\e[32m[INFO] %s\e[m\n" "$@"
}

warn() {
  printf "\e[33m[WARN] %s\e[m\n" "$@"
}

error() {
  printf "\e[31m[ERROR] %s\e[m\n" "$@"
  exit 1
}
