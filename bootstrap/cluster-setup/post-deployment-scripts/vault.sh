#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
UTILITY_SCRIPTS_DIR="$REPO_ROOT_DIR/utility-scripts"

VAULT_TERRAFORM_DIR="$REPO_ROOT_DIR/iac/vault"
VAULT_INITIAL_CONFIG_FILE="$HOME/.vault-initial.config"
VAULT_K8S_CONFIG_FILE="$HOME/.k8s-configs.yaml"

VAULT_NAMESPACE=${DESTINATION_NAMESPACE:-'devops-system'}
VAULT_POD_NAME=${VAULT_POD_NAME:-'devops-vault-0'}

VAULT_TOKEN_SECRET_NAME=${VAULT_TOKEN_SECRET_NAME:-'devops-vault-token'}
VAULT_AUTO_UNSEAL_SERVICE='unseal-vault.service'

#
# Import utility functions.
#

. "$UTILITY_SCRIPTS_DIR/utilities.sh"

#
# Check if kubectl is installed.
#

if ! command -v kubectl >/dev/null 2>&1; then
  error "kubectl is NOT installed."
fi

# Setting up vault.

## Waiting for vault to be ready.

if sudo systemctl is-active $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
  info "$VAULT_AUTO_UNSEAL_SERVICE is already active."

  sudo systemctl stop $VAULT_AUTO_UNSEAL_SERVICE
fi

info "Waiting for Vault to become running."

until kubectl get pods -n $VAULT_NAMESPACE --no-headers | grep -q $VAULT_POD_NAME &>/dev/null
do
  info " -> Waiting for Vault pod with name containing: $VAULT_POD_NAME in namespace: $VAULT_NAMESPACE to be created. Retrying in 10 seconds..."
  sleep 10
done

until [ -z "$(kubectl get pods -n $VAULT_NAMESPACE --no-headers | grep $VAULT_POD_NAME | awk -F'[/ ]+' '$4 != "Running"')" ]
do
  info "-> Vault is not ready yet. Retrying in 10 seconds..."
  sleep 10
done

info "Waiting for Vault to be ready..."

IS_SEALED='true'

while true
do
  IS_SEALED=$((kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault status 2>/dev/null || true) | grep Sealed | awk -F'[ ]+' '{print $2}')
  case $IS_SEALED in
    'false')
      info " -> Vault is already UNSEALED."
      break
      ;;
    'true')
      info " -> Vault is SEALED."

      if ! sudo systemctl list-unit-files $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
        info " -> Vault is NOT initialized."
        break
      fi

      if sudo systemctl is-active $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
        info " -> $VAULT_AUTO_UNSEAL_SERVICE is already active."
        break
      fi

      if ! sudo systemctl start $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
        info " -> $VAULT_AUTO_UNSEAL_SERVICE is failed to start."
        break
      fi

      info " -> Start $VAULT_AUTO_UNSEAL_SERVICE."
      ;;
    *)
      ;;
  esac

  info " -> Retrying in 15 seconds..."
  sleep 15
done

## Initializing and unseal vault.

VAULT_KEY_THRESHOLD=3
VAULT_KEY_SHARES=5

if $IS_SEALED == 'true'; then
  info "Initializing Vault."

  kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault operator init \
    -key-shares=$VAULT_KEY_SHARES \
    -key-threshold=$VAULT_KEY_THRESHOLD \
    > $VAULT_INITIAL_CONFIG_FILE

  if [ "$(grep 'Unseal Key' $VAULT_INITIAL_CONFIG_FILE | wc -l)" != "$VAULT_KEY_SHARES" ]; then
    rm -f $VAULT_INITIAL_CONFIG_FILE
    helm uninstall vault-vault
    kubectl delete pvc/data-$VAULT_POD_NAME

    error "Vault initialization failed. Please check the Vault pod logs for more details."
  fi

  info "Vault initialized successfully. Unseal keys and root token are stored in $VAULT_INITIAL_CONFIG_FILE."

  info "Unsealing Vault."

  for i in $(seq $VAULT_KEY_THRESHOLD)
  do
    info "Using Unseal Key $i/$VAULT_KEY_THRESHOLD to unseal Vault."
    
    VAULT_KEY="$(cat $VAULT_INITIAL_CONFIG_FILE | grep "Unseal Key $i:" | awk -F'[ ]+' '{print $4}')"
    
    info "Unsealing Vault with Unseal Key $i: $VAULT_KEY"

    kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault operator unseal $VAULT_KEY
    kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault status || true
  done

  info "Vault unsealed successfully."
fi

## Logging into vault.

info "Logging into Vault."

VAULT_ROOT_TOKEN="$(grep 'Initial Root Token:' $VAULT_INITIAL_CONFIG_FILE | tail -n 1 | awk '{print $4}' | sed -E 's/\x1b\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[mGK]//g')"
kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault login "$VAULT_ROOT_TOKEN"

info "Logged into Vault successfully."

# Creating a systemd service file to auto unseal vault on startup.

info "Creating a systemd service file to auto unseal Vault on startup."

VAULT_AUTO_UNSEAL_SERVICE_FILE=/etc/systemd/system/$VAULT_AUTO_UNSEAL_SERVICE
cat <<EOF | sudo tee $VAULT_AUTO_UNSEAL_SERVICE_FILE
[Unit]
Description=Unseal Vault
After=k3s.service

[Install]
WantedBy=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'until [ "\$(kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault status &>/dev/null || echo \$?)" = "2" ]; do \\
    sleep 5; \\
  done'

EOF

## Adding unseal commands to the service file.

for i in $(seq $VAULT_KEY_THRESHOLD)
do
  VAULT_KEY="$(grep "Unseal Key $i:" $VAULT_INITIAL_CONFIG_FILE | tail -n 1 | awk '{print $4}' | sed -E 's/\x1b\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[mGK]//g')"
  awk "{gsub(/done/, \"done \&\& \\\\\n  kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault operator unseal $VAULT_KEY\"); print}" $VAULT_AUTO_UNSEAL_SERVICE_FILE | sudo tee $VAULT_AUTO_UNSEAL_SERVICE_FILE
done

info "Systemd service file created at $VAULT_AUTO_UNSEAL_SERVICE_FILE."

## Enabling the unseal vault service.

info "Enabling the $VAULT_AUTO_UNSEAL_SERVICE."

sudo systemctl daemon-reload
sudo systemctl enable $VAULT_AUTO_UNSEAL_SERVICE

info "Vault auto unseal service enabled successfully."

## Storing K8s Configurations for External Secrets.

K8S_HOST='https://kubernetes.default.svc.cluster.local'
K8S_CA_CERT=$(kubectl config view -o jsonpath='{.clusters[].cluster.certificate-authority-data}' --minify=true --raw)
K8S_TOKEN_REVIEWER_JWT=$(kubectl get secret -n $VAULT_NAMESPACE -o jsonpath='{.data.token}' $VAULT_TOKEN_SECRET_NAME)

cat <<EOF >$VAULT_K8S_CONFIG_FILE
k8s-host: $K8S_HOST
k8s-ca-cert: $K8S_CA_CERT
k8s-token-reviewer-jwt: $K8S_TOKEN_REVIEWER_JWT
EOF

## Applying Terraform configuration for Vault.

if ! command -v terraform >/dev/null 2>&1; then
  warn "Terraform is NOT installed."

  if [ -f /etc/apt/sources.list.d/hashicorp.list ]; then
    info "HashiCorp repository is already added."

    info "Removing existing HashiCorp repository to avoid potential conflicts."
    sudo rm -f /etc/apt/sources.list.d/hashicorp.list
    info "HashiCorp repository removed successfully."
  fi

  if [ -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
    info "HashiCorp GPG keyring is already added."

    info "Removing existing HashiCorp GPG keyring to avoid potential conflicts."
    sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
    info "HashiCorp GPG keyring removed successfully."
  fi

  sudo apt update && sudo apt install -y --no-install-recommends \
    gnupg \
    lsb-release

  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" |\
  sudo tee /etc/apt/sources.list.d/hashicorp.list

  sudo apt update && sudo apt install -y --no-install-recommends \
    terraform

  info "Terraform installation completed."
fi

(
  cd $VAULT_TERRAFORM_DIR && (
    info "Initializing Terraform in $VAULT_TERRAFORM_DIR."

    terraform init -input=false >/dev/null 2>&1

    if [ ! -f $VAULT_TERRAFORM_DIR/variables.tfvars ]; then
      warn "Terraform variables file not found at $VAULT_TERRAFORM_DIR/variables.tfvars."
      exit 1
    fi

    case $(terraform plan -var-file=variables.tfvars -detailed-exitcode >/dev/null 2>&1; echo $?) in
      0)
        info "No changes to apply for Terraform configuration in $VAULT_TERRAFORM_DIR."
        ;;
      2)
        info "Changes detected for Terraform configuration in $VAULT_TERRAFORM_DIR. Applying changes."

        info "Importing existing Vault configurations into Terraform state."
        terraform import -var-file=variables.tfvars 'vault_mount.kv2_secrets_engines["k8s-secrets"]' k8s-secrets >/dev/null 2>&1 || true
        terraform import -var-file=variables.tfvars vault_auth_backend.kubernetes_auth kubernetes >/dev/null 2>&1 || true
        info "Existing Vault configurations imported successfully."

        info "Applying Terraform configuration in $VAULT_TERRAFORM_DIR."
        if ! terraform apply -input=false -auto-approve -var-file=variables.tfvars >/dev/null 2>&1; then
          error "Failed to apply Terraform configuration in $VAULT_TERRAFORM_DIR."
        fi
        info "Terraform configuration in $VAULT_TERRAFORM_DIR applied successfully."
        ;;
      *)
        error "Failed to plan Terraform configuration in $VAULT_TERRAFORM_DIR."
        ;;
    esac
  )
)
