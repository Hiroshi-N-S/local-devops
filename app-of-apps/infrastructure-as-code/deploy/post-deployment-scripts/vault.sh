#!/bin/bash
set -euo pipefail

VAULT_HOST=${VAULT_HOST:-'vault.devenv.local'}
VAULT_NAMESPACE=${VAULT_NAMESPACE:-'devops-system'}
VAULT_POD_NAME=${VAULT_POD_NAME:-'devops-vault-0'}
VAULT_TOKEN_SECRET_NAME=${VAULT_TOKEN_SECRET_NAME:-'devops-vault-token'}
VAULT_AUTO_UNSEAL_SERVICE='unseal-vault.service'

SCRIPT_DIR=$(dirname "$0")

TERRAFORM_DIR=$(cd $SCRIPT_DIR/../terraform && pwd)
VAULT_TERRAFORM_DIR=$TERRAFORM_DIR/vault
VAULT_INITIAL_CONFIG_FILE=$VAULT_TERRAFORM_DIR/.vault-initial.config
VAULT_K8S_CONFIG_FILE=$VAULT_TERRAFORM_DIR/.k8s-configs.yaml

if ! command -v kubectl >/dev/null 2>&1; then
  printf "\e[31m[ERROR] %s\e[m\n" "kubectl is NOT installed."
  exit 1
fi

# Setting up vault.

## Waiting for vault to be ready.

if sudo systemctl is-active $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
  printf "\e[32m[INFO] %s\e[m\n" "$VAULT_AUTO_UNSEAL_SERVICE is already active."

  sudo systemctl stop $VAULT_AUTO_UNSEAL_SERVICE
fi

printf "\e[32m[INFO] %s\e[m\n" "Waiting for Vault to become running."

until [ -z "$(kubectl get pods -n $VAULT_NAMESPACE --no-headers | grep $VAULT_POD_NAME | awk -F'[/ ]+' '$4 != "Running"')" ]
do
  printf "\e[32m[INFO] %s\e[m\n" "-> Vault is not ready yet. Retrying in 10 seconds..."
  sleep 10
done

printf "\e[32m[INFO] %s\e[m\n" "Waiting for Vault to be ready..."

IS_SEALED='true'

while true
do
  IS_SEALED=$((kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault status 2>/dev/null || true) | grep Sealed | awk -F'[ ]+' '{print $2}')
  case $IS_SEALED in
    'false')
      printf "\e[32m[INFO] %s\e[m\n" " -> Vault is already UNSEALED."
      break
      ;;
    'true')
      printf "\e[32m[INFO] %s\e[m\n" " -> Vault is SEALED."

      if ! sudo systemctl list-unit-files $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
        printf "\e[32m[INFO] %s\e[m\n" " -> Vault is NOT initialized."
        break
      fi

      if sudo systemctl is-active $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
        printf "\e[32m[INFO] %s\e[m\n" " -> $VAULT_AUTO_UNSEAL_SERVICE is already active."
        break
      fi

      if ! sudo systemctl start $VAULT_AUTO_UNSEAL_SERVICE &>/dev/null; then
        printf "\e[32m[INFO] %s\e[m\n" " -> $VAULT_AUTO_UNSEAL_SERVICE is failed to start."
        break
      fi

      printf "\e[32m[INFO] %s\e[m\n" " -> Start $VAULT_AUTO_UNSEAL_SERVICE."
      ;;
    *)
      ;;
  esac

  printf "\e[32m[INFO] %s\e[m\n" " -> Retrying in 15 seconds..."
  sleep 15
done

## Initializing and unseal vault.

VAULT_KEY_THRESHOLD=3
VAULT_KEY_SHARES=5

if $IS_SEALED == 'true'; then
  printf "\e[32m[INFO] %s\e[m\n" "Initializing Vault."

  if [ ! -d $VAULT_TERRAFORM_DIR ]; then
    printf "\e[32m[INFO] %s\e[m\n" "Creating Terraform work directory at $VAULT_TERRAFORM_DIR."
    mkdir -p $VAULT_TERRAFORM_DIR
    printf "\e[32m[INFO] %s\e[m\n" "Terraform work directory created successfully."
  fi

  kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault operator init \
    -key-shares=$VAULT_KEY_SHARES \
    -key-threshold=$VAULT_KEY_THRESHOLD \
    > $VAULT_INITIAL_CONFIG_FILE

  if [ "$(grep 'Unseal Key' $VAULT_INITIAL_CONFIG_FILE | wc -l)" != "$VAULT_KEY_SHARES" ]; then
    printf "\e[31m[ERROR]\e[m %s\n" "Vault initialization failed. Please check the Vault pod logs for more details."

    rm -f $VAULT_INITIAL_CONFIG_FILE
    helm uninstall vault-vault
    kubectl delete pvc/data-$VAULT_POD_NAME
    exit 1
  fi

  printf "\e[32m[INFO] %s\e[m\n" "Vault initialized successfully. Unseal keys and root token are stored in $VAULT_INITIAL_CONFIG_FILE."

  printf "\e[32m[INFO] %s\e[m\n" "Unsealing Vault."

  for i in $(seq $VAULT_KEY_THRESHOLD)
  do
    printf "\e[32m[INFO] %s\e[m\n" "Using Unseal Key $i/$VAULT_KEY_THRESHOLD to unseal Vault."
    
    VAULT_KEY="$(cat $VAULT_INITIAL_CONFIG_FILE | grep "Unseal Key $i:" | awk -F'[ ]+' '{print $4}')"
    
    printf "\e[32m[INFO] %s\e[m\n" "Unsealing Vault with Unseal Key $i: $VAULT_KEY"

    kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault operator unseal $VAULT_KEY
    kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault status || true
  done

  printf "\e[32m[INFO] %s\e[m\n" "Vault unsealed successfully."
fi

## Logging into vault.

printf "\e[32m[INFO] %s\e[m\n" "Logging into Vault."

VAULT_ROOT_TOKEN="$(grep 'Initial Root Token:' $VAULT_INITIAL_CONFIG_FILE | tail -n 1 | awk '{print $4}' | sed -E 's/\x1b\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[mGK]//g')"
kubectl exec -n $VAULT_NAMESPACE -i $VAULT_POD_NAME -- vault login "$VAULT_ROOT_TOKEN"

printf "\e[32m[INFO] %s\e[m\n" "Logged into Vault successfully."

# Creating a systemd service file to auto unseal vault on startup.

printf "\e[32m[INFO] %s\e[m\n" "Creating a systemd service file to auto unseal Vault on startup."

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

printf "\e[32m[INFO] %s\e[m\n" "Systemd service file created at $VAULT_AUTO_UNSEAL_SERVICE_FILE."

## Enabling the unseal vault service.

printf "\e[32m[INFO] %s\e[m\n" "Enabling the $VAULT_AUTO_UNSEAL_SERVICE."

sudo systemctl daemon-reload
sudo systemctl enable $VAULT_AUTO_UNSEAL_SERVICE

printf "\e[32m[INFO] %s\e[m\n" "Vault auto unseal service enabled successfully."

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
  printf "\e[33m[WARNING] %s\e[m\n" "Terraform is NOT installed."

  if [ -f /etc/apt/sources.list.d/hashicorp.list ]; then
    printf "\e[32m[INFO] %s\e[m\n" "HashiCorp repository is already added."

    printf "\e[32m[INFO] %s\e[m\n" "Removing existing HashiCorp repository to avoid potential conflicts."
    sudo rm -f /etc/apt/sources.list.d/hashicorp.list
    printf "\e[32m[INFO] %s\e[m\n" "HashiCorp repository removed successfully."
  fi

  if [ -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
    printf "\e[32m[INFO] %s\e[m\n" "HashiCorp GPG keyring is already added."

    printf "\e[32m[INFO] %s\e[m\n" "Removing existing HashiCorp GPG keyring to avoid potential conflicts."
    sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
    printf "\e[32m[INFO] %s\e[m\n" "HashiCorp GPG keyring removed successfully."
  fi

  sudo apt update && sudo apt install -y --no-install-recommends \
    gnupg \
    lsb-release

  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" |\
  sudo tee /etc/apt/sources.list.d/hashicorp.list

  sudo apt update && sudo apt install -y --no-install-recommends \
    terraform

  printf "\e[32m[INFO] %s\e[m\n" "Terraform installation completed."
fi

(
  cd $VAULT_TERRAFORM_DIR && (
    printf "\e[32m[INFO] %s\e[m\n" "Initializing Terraform in $VAULT_TERRAFORM_DIR."

    terraform init -input=false

    if [ ! -f $VAULT_TERRAFORM_DIR/variables.tfvars ]; then
      printf "\e[33m[WARNING] %s\e[m\n" "Terraform variables file not found at $VAULT_TERRAFORM_DIR/variables.tfvars."
      exit 1
    fi

    if terraform plan -var-file=variables.tfvars -detailed-exitcode >/dev/null 2>&1; then
      printf "\e[32m[INFO] %s\e[m\n" "No changes to apply for Terraform configuration in $VAULT_TERRAFORM_DIR."
    else
      printf "\e[32m[INFO] %s\e[m\n" "Applying Terraform configuration in $VAULT_TERRAFORM_DIR."
      terraform apply -input=false -auto-approve -var-file=variables.tfvars
      printf "\e[32m[INFO] %s\e[m\n" "Terraform configuration in $VAULT_TERRAFORM_DIR applied successfully."      
    fi
  )
)
