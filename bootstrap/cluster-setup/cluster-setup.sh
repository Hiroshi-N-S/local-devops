#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT_DIR="$SCRIPT_DIR/../.."
UTILITY_SCRIPTS_DIR="$REPO_ROOT_DIR/utility-scripts"

APP_OF_APPS_DIR="$REPO_ROOT_DIR/app-of-apps"
APPS_DIR="$APP_OF_APPS_DIR/apps"
CICD_DOMAIN_DIR="$APPS_DIR/400_cicd"
ARGOCD_APP_DIR="$CICD_DOMAIN_DIR/argo-cd"

CERT_DIR=$REPO_ROOT_DIR/certs
CERT_FILE_NAME=${CERT_FILE_NAME:-'local-devenv'}

NODE_IP=${NODE_IP:-''}
NODE_HOST=${NODE_HOST:-'devenv.local'}

#
# Import utility functions.
#

. "$UTILITY_SCRIPTS_DIR/utilities.sh"

#
# Function definitions.
#

set_host_entries() {
  while [ -z "$NODE_IP" ]
  do
    echo "NODE_IP is NOT defined."
    read -p "Enter the IP address for $NODE_HOST: " NODE_IP

    echo "NODE_IP: $NODE_IP"
    read -p "Do you want to continue? [Y/n]: " Yn
    if [ "$Yn" != "Y" ]; then
      NODE_IP=''
    fi
  done

  local NFS_HOST=${NFS_HOST:-"nfs.${NODE_HOST}"}
  local NFS_IP=${NFS_IP:-"${NODE_IP:-''}"}

  local VAULT_HOST=${VAULT_HOST:-"vault.${NODE_HOST}"}
  local VAULT_IP=${VAULT_IP:-"${NODE_IP:-''}"}

  local AUTH_HOST=${AUTH_HOST:-"auth.${NODE_HOST}"}
  local AUTH_IP=${AUTH_IP:-"${NODE_IP:-''}"}

  local REGISTRY_HOST=${REGISTRY_HOST:-"registry.${NODE_HOST}"}
  local REGISTRY_IP=${REGISTRY_IP:-"${NODE_IP:-''}"}

  local S3_HOST=${S3_HOST:-"s3.${NODE_HOST}"}
  local S3_IP=${S3_IP:-"${NODE_IP:-''}"}

  #
  # Adding hosts.
  #

  if ! cat /etc/hosts | grep -v '^#' | grep -q "$VAULT_HOST"; then
    info "Adding host entry for $VAULT_HOST to /etc/hosts."
    echo "$VAULT_IP  $VAULT_HOST" | sudo tee -a /etc/hosts
    info "Adding host entry for $VAULT_HOST to /etc/hosts: DONE"
  fi

  if ! cat /etc/hosts | grep -v '^#' | grep -q "$AUTH_HOST"; then
    info "Adding host entry for $AUTH_HOST to /etc/hosts."
    echo "$AUTH_IP  $AUTH_HOST" | sudo tee -a /etc/hosts
    info "Adding host entry for $AUTH_HOST to /etc/hosts: DONE"
  fi

  if ! cat /etc/hosts | grep -v '^#' | grep -q "$REGISTRY_HOST"; then
    info "Adding host entry for $REGISTRY_HOST to /etc/hosts."
    echo "$REGISTRY_IP  $REGISTRY_HOST" | sudo tee -a /etc/hosts
    info "Adding host entry for $REGISTRY_HOST to /etc/hosts: DONE"
  fi

  if ! cat /etc/hosts | grep -v '^#' | grep -q "$S3_HOST"; then
    info "Adding host entry for $S3_HOST to /etc/hosts."
    echo "$S3_IP  $S3_HOST" | sudo tee -a /etc/hosts
    info "Adding host entry for $S3_HOST to /etc/hosts: DONE"
  fi

  #
  # Apply coredns-custom.
  #

  kubectl apply -n kube-system -f - <<EOT
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  custom.server: |
    ${NODE_HOST}:53 {
      errors
      health
      hosts {
        $( [ -z ${NFS_IP}      ] && echo '' || echo "${NFS_IP}    ${NFS_HOST}" )
        $( [ -z ${VAULT_IP}    ] && echo '' || echo "${VAULT_IP}  ${VAULT_HOST}" )
        $( [ -z ${AUTH_IP}     ] && echo '' || echo "${AUTH_IP}    ${AUTH_HOST}" )
        $( [ -z ${REGISTRY_IP} ] && echo '' || echo "${REGISTRY_IP}  ${REGISTRY_HOST}" )
        $( [ -z ${S3_IP}       ] && echo '' || echo "${S3_IP}      ${S3_HOST}" )
        fallthrough
      }
    }
EOT

  info "Restarting the CoreDNS."
  kubectl --namespace kube-system rollout restart deployment coredns
  info "Restarting the CoreDNS: DONE"
}

configure_certificates() {
  info "Generating certificates for the local development environment."
  bash $CERT_DIR/generate-self-signed-cert.sh
  info "Generating certificates for the local development environment: DONE"

  info "Installing the certificate to the system trust store."
  sudo cp -f $CERT_DIR/${CERT_FILE_NAME}.crt /usr/local/share/ca-certificates/${CERT_FILE_NAME}.crt
  sudo update-ca-certificates
  info "Installing the certificate to the system trust store: DONE"

  info "Restarting k3s to apply the new certificate."
  sudo systemctl restart k3s
  info "Restarting k3s to apply the new certificate: DONE"
}

deploy_argocd() {
  if kubectl get crd applications.argoproj.io -o name | grep -q "applications.argoproj.io"; then
    info "Argo CD is already deployed. Skipping deployment."
    return
  fi

  info "Deploying Argo CD."

  local APP_MANIFEST_FILE="$ARGOCD_APP_DIR/application.yaml"

  local DESTINATION_NAMESPACE=$(cat $APP_MANIFEST_FILE | yq -r '.spec.destination.namespace')

  local APP_NAME=$(   cat $APP_MANIFEST_FILE | yq -r '.metadata.name' )
  local CHART_NAME=$( cat $APP_MANIFEST_FILE | yq -r '.spec.sources[] | select(has("chart")) | .chart')
  local REPO_URL=$(   cat $APP_MANIFEST_FILE | yq -r '.spec.sources[] | select(has("chart")) | .repoURL')
  local TARGET_REV=$( cat $APP_MANIFEST_FILE | yq -r '.spec.sources[] | select(has("chart")) | .targetRevision')

  info "Application parameters:"
  info " -> App name             : $APP_NAME"
  info " -> Chart name           : $CHART_NAME"
  info " -> Repository URL       : $REPO_URL"
  info " -> Target revision      : $TARGET_REV"
  info " -> Destination namespace: $DESTINATION_NAMESPACE"

  info "Upgrading the application."
  helm upgrade --install ${APP_NAME} $CHART_NAME \
    --repo $REPO_URL \
    --version $TARGET_REV \
    --namespace $DESTINATION_NAMESPACE \
    --create-namespace \
    --set dex.enabled=false \
    >/dev/null 2>&1
  info "Upgrading the application: DONE"

  info "Waiting for any pods in namespace $DESTINATION_NAMESPACE to be deployed."
  until kubectl get pods -n $DESTINATION_NAMESPACE --no-headers | grep -qv "No resources found"; do
    info " -> Checking for any pods"
    info " -> Retrying in 10 seconds..."
    sleep 10
  done
  info "Waiting for any pods in namespace $DESTINATION_NAMESPACE to be deployed: DONE"

  info "Waiting for all pods in namespace $DESTINATION_NAMESPACE to become running..."
  until [ -z "$(kubectl get pods -n $DESTINATION_NAMESPACE --no-headers | grep -v Completed | awk -F'[/ ]+' '$2 != $3 || $4 != "Running"')" ]
  do
    info " -> Checking if pods are running"
    info " -> Retrying in 10 seconds..."
    sleep 10
  done
  info "Waiting for all pods in namespace $DESTINATION_NAMESPACE to become running...: DONE"
}

deploy_applications() {
  info "Deploying the applications."

  kubectl apply -f $APP_OF_APPS_DIR/projects/project.yaml
  kubectl apply -f $APP_OF_APPS_DIR/bootstrap/application.yaml

  info "Deploying the applications: DONE"

  for script in $(ls -1 $SCRIPT_DIR/post-deployment-scripts/)
  do
    info "Running $script."
    bash $SCRIPT_DIR/post-deployment-scripts/$script
    info "Running $script: DONE"
  done

  info "Waiting for any applications to be deployed."
  until kubectl get application -A --no-headers | grep -qv "No resources found"; do
    info " -> Checking for any applications"
    info " -> Retrying in 10 seconds..."
    sleep 10
  done
  info "Waiting for any applications to be deployed: DONE"

  info "Waiting for all applications to become healthy..."
  until [ -z "$(kubectl get application -A --no-headers | awk -F'[ ]+' '$4 != "Healthy"')" ]
  do
    info " -> Checking if applications are healthy"
    info " -> Retrying in 10 seconds..."
    sleep 10
  done
  info "Waiting for all applications to become healthy: DONE"
}

delete_all_resources() {
  local NAMESPACES=$(
    kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' \
      | tr ' ' '\n' \
      | grep -vE '^(kube-system|kube-public|kube-node-lease|default)$'
  )

  for NAMESPACE in $NAMESPACES
  do
    info "Deleting namespace $NAMESPACE."
    kubectl delete all --all -n $NAMESPACE
    info "Deleting namespace $NAMESPACE: DONE"
  done
}

#
# Main.
#

MODE=${1:-deploy}
case $MODE in
  "deploy")
    set_host_entries
    configure_certificates
    deploy_argocd
    deploy_applications
    ;;
  "delete")
    delete_all_resources
    ;;
  *)
    error "Invalid mode: $MODE"
    ;;
esac

exit 0
