#!/bin/bash
set -euo pipefail

YQ_VER=${YQ_VER:-'4.52.4'}
APP_PREFIX=${APP_PREFIX:-'devops'}

SCRIPT_DIR=$(dirname "$0")
REPO_ROOT_DIR=$(cd $SCRIPT_DIR/../../.. && pwd)

POST_DEPLOYMENT_SCRIPTS_DIR=$SCRIPT_DIR/post-deployment-scripts

APP_OF_APPS_DIR=$(cd $SCRIPT_DIR/../.. && pwd)
PROJ_DIR=$APP_OF_APPS_DIR/projects
APPS_DIR=$APP_OF_APPS_DIR/applications

NODE_IP=${NODE_IP:-''}
NODE_HOST=${NODE_HOST:-'devenv.local'}

DEPLOY_MODE=${DEPLOY_MODE:-'INSTALL'}
DEPLOY_TARGET=${DEPLOY_TARGET:-'DEVELOP'}

#
# Evaluate arguments
#

for arg in "$@"; do
  case $arg in
    "--help")
      printf "\e[32m[INFO] %s\e[m\n" "Usage: $0 [--delete, --product]"
      exit 0
      ;;
    "--delete")
      printf "\e[32m[INFO] %s\e[m\n" "Deleting the applications."
      DEPLOY_MODE="DELETE"
      ;;
    "--product")
      printf "\e[32m[INFO] %s\e[m\n" "Deploying to the product"
      DEPLOY_TARGET="PRODUCT"
      ;;
    *)
      printf "\e[31m[ERROR] %s\e[m\n" "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

if [ $DEPLOY_MODE != "DELETE" ]; then
  while [ -z "$NODE_IP" ]
  do
    printf "\e[33m[WARN] %s\e[m\n" "NODE_IP is NOT defined."
    printf "Enter the IP address for $NODE_HOST: "
    read -r NODE_IP

    printf "\e[32m[INFO] %s\e[m\n" "NODE_IP: $NODE_IP"
    printf "Do you want to continue? [Y/n]: "
    read -r Yn
    if [ "$Yn" != "Y" ]; then
      NODE_IP=''
    fi
  done
fi

NFS_HOST=${NFS_HOST:-"nfs.${NODE_HOST}"}
NFS_IP=${NFS_IP:-"${NODE_IP:-''}"}
VAULT_HOST=${VAULT_HOST:-"vault.${NODE_HOST}"}
VAULT_IP=${VAULT_IP:-"${NODE_IP:-''}"}
AUTH_HOST=${AUTH_HOST:-"auth.${NODE_HOST}"}
AUTH_IP=${AUTH_IP:-"${NODE_IP:-''}"}
REGISTRY_HOST=${REGISTRY_HOST:-"registry.${NODE_HOST}"}
REGISTRY_IP=${REGISTRY_IP:-"${NODE_IP:-''}"}
S3_HOST=${S3_HOST:-"s3.${NODE_HOST}"}
S3_IP=${S3_IP:-"${NODE_IP:-''}"}

#
# Adding hosts.
#

if ! cat /etc/hosts | grep -v '^#' | grep -q "$VAULT_HOST"; then
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $VAULT_HOST to /etc/hosts."
  echo "$VAULT_IP  $VAULT_HOST" | sudo tee -a /etc/hosts
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $VAULT_HOST to /etc/hosts: DONE"
fi

if ! cat /etc/hosts | grep -v '^#' | grep -q "$AUTH_HOST"; then
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $AUTH_HOST to /etc/hosts."
  echo "$AUTH_IP  $AUTH_HOST" | sudo tee -a /etc/hosts
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $AUTH_HOST to /etc/hosts: DONE"
fi

if ! cat /etc/hosts | grep -v '^#' | grep -q "$REGISTRY_HOST"; then
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $REGISTRY_HOST to /etc/hosts."
  echo "$REGISTRY_IP  $REGISTRY_HOST" | sudo tee -a /etc/hosts
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $REGISTRY_HOST to /etc/hosts: DONE"
fi

if ! cat /etc/hosts | grep -v '^#' | grep -q "$S3_HOST"; then
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $S3_HOST to /etc/hosts."
  echo "$S3_IP  $S3_HOST" | sudo tee -a /etc/hosts
  printf "\e[32m[INFO] %s\e[m\n" "Adding host entry for $S3_HOST to /etc/hosts: DONE"
fi

#
# Installing dependencies.
#

printf "\e[32m[INFO] %s\e[m\n" "Installing dependencies."
if ! command -v yq >/dev/null 2>&1; then
  printf "\e[33m[WARN] %s\e[m\n" "yq is NOT defined."
  printf "\e[32m[INFO] %s\e[m\n" " -> Installing yq."
  YQ_PKG_NAME="yq_linux_$(dpkg --print-architecture)"
  sudo curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/${YQ_PKG_NAME}
  sudo chmod +x /usr/local/bin/yq
  printf "\e[32m[INFO] %s\e[m\n" " -> Installing yq: DONE"
fi
if ! command -v jq >/dev/null 2>&1; then
  printf "\e[33m[WARN] %s\e[m\n" "jq is NOT defined."
  printf "\e[32m[INFO] %s\e[m\n" " -> Installing jq."
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends jq
  printf "\e[32m[INFO] %s\e[m\n" " -> Installing jq: DONE"
fi
printf "\e[32m[INFO] %s\e[m\n" "Installing dependencies: DONE"

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
        $( [ -z ${NFS_IP}   ] && echo '' || echo "${NFS_IP}  ${NFS_HOST}" )
        $( [ -z ${VAULT_IP} ] && echo '' || echo "${VAULT_IP}  ${VAULT_HOST}" )
        fallthrough
      }
      template ANY ANY ${NODE_HOST} {
        answer "{{ .Name }} 60 IN A ${NODE_IP}"
        fallthrough
      }
    }
EOT

printf "\e[32m[INFO] %s\e[m\n" "Restart the CoreDNS."
kubectl --namespace kube-system rollout restart deployment coredns
printf "\e[32m[INFO] %s\e[m\n" "Restart the CoreDNS: DONE"

#
# Deploy applications.
#

printf "\e[32m[INFO] %s\e[m\n" "Deploying the applications."
APP_MANIFESTS=$([ $DEPLOY_MODE == "DELETE" ] && ls -r $APPS_DIR/*.yaml || ls $APPS_DIR/*.yaml)

for MODE in $DEPLOY_MODE $DEPLOY_TARGET
do
  case $MODE in
    "DEVELOP")
      printf "\e[32m[INFO] %s\e[m\n" "-> Deploying an Argo CD Project."
      kubectl apply -f $PROJ_DIR/project.yaml
      printf "\e[32m[INFO] %s\e[m\n" "-> Deploying an Argo CD Project: DONE"
      ;;
    "PRODUCT")
      printf "\e[32m[INFO] %s\e[m\n" "-> Deploying an Argo CD Project."
      kubectl apply -f $PROJ_DIR/project.yaml
      printf "\e[32m[INFO] %s\e[m\n" "-> Deploying an Argo CD Project: DONE"

      printf "\e[32m[INFO] %s\e[m\n" "-> Deploying an Argo CD Application."
      kubectl apply -f $APP_OF_APPS_DIR/application.yaml
      printf "\e[32m[INFO] %s\e[m\n" "-> Deploying an Argo CD Application: DONE"

      continue
      ;;
    *)
      # Skip
      ;;
  esac

  for APP_MANIFEST in $APP_MANIFESTS
  do
    APP_FULL_NAME=$(basename "$APP_MANIFEST" .yaml)
    APP_NAME=$(echo "$APP_FULL_NAME" | cut -d'_' -f2-)
    DESTINATION_NAMESPACE=$(cat $APP_MANIFEST | yq -r '.spec.destination.namespace')

    cat $APP_MANIFEST  | yq -o=json | jq -r '
      .spec.sources[]
      | has("chart") as $isChart
      | has("path") as $isGit
      | has("ref") as $hasRef
      | if $isChart then "chart"
        elif $isGit then "git"
        elif $hasRef then "ref"
        else "unknown"
        end
    ' |\
    while read -r APP_SOURCE_TYPE
    do
      case $APP_SOURCE_TYPE in
        "chart")
          printf "\e[32m[INFO] %s\e[m\n" "-> Application $APP_FULL_NAME is a Helm chart."

          CHART_NAME=$( cat $APP_MANIFEST | yq -r '.spec.sources[] | select(has("chart")) | .chart')
          REPO_URL=$(   cat $APP_MANIFEST | yq -r '.spec.sources[] | select(has("chart")) | .repoURL')
          TARGET_REV=$( cat $APP_MANIFEST | yq -r '.spec.sources[] | select(has("chart")) | .targetRevision')
          VALUES_FILE=$(cat $APP_MANIFEST | yq -r '.spec.sources[] | select(has("chart")) | .helm.valueFiles[]')

          VALUES_FILE_PATH=$(echo "$VALUES_FILE" | sed -e "s|\$valueFiles|$REPO_ROOT_DIR/|g")
          if [ ! -f "$VALUES_FILE_PATH" ]; then
            printf "\e[31m[ERROR] %s\e[m\n" "  -> Values file not found: $VALUES_FILE_PATH"
            exit 1
          fi

          printf "\e[32m[INFO] %s\e[m\n" "   -> Chart name           : $CHART_NAME"
          printf "\e[32m[INFO] %s\e[m\n" "   -> Repository URL       : $REPO_URL"
          printf "\e[32m[INFO] %s\e[m\n" "   -> Target revision      : $TARGET_REV"
          printf "\e[32m[INFO] %s\e[m\n" "   -> Values file          : $VALUES_FILE"
          printf "\e[32m[INFO] %s\e[m\n" "   -> Destination namespace: $DESTINATION_NAMESPACE"

          case $MODE in
            "INSTALL")
              printf "\e[32m[INFO] %s\e[m\n" "   -> Deploying the application: $APP_NAME."
              helm upgrade --install ${APP_PREFIX}-${APP_NAME} $CHART_NAME \
                --repo $REPO_URL \
                --version $TARGET_REV \
                --values $VALUES_FILE_PATH \
                --namespace $DESTINATION_NAMESPACE \
                --create-namespace
              printf "\e[32m[INFO] %s\e[m\n" "   -> Deploying the application: $APP_NAME: DONE"
              ;;
            "DELETE")
              printf "\e[32m[INFO] %s\e[m\n" "   -> Deleting the application: $APP_NAME."
              helm delete ${APP_PREFIX}-${APP_NAME} --namespace $DESTINATION_NAMESPACE || true
              printf "\e[32m[INFO] %s\e[m\n" "   -> Deleting the application: $APP_NAME: DONE"
              ;;
            "DEVELOP")
              printf "\e[32m[INFO] %s\e[m\n" "   -> Deploying the Argo CD Application: $APP_NAME."
              cat $APP_MANIFEST |\
                yq 'del(.spec.sources[] | select(.ref == "valueFiles"))' |\
                yq 'del(.spec.sources[].helm.valueFiles)' |\
                yq ".spec.sources[].helm.values += load_str(\"$VALUES_FILE_PATH\")" |\
              kubectl apply -f -
              printf "\e[32m[INFO] %s\e[m\n" "   -> Deploying the Arfo CD Application: $APP_NAME: DONE"
              ;;
            "PRODUCT")
              # Skip
              ;;
            *)
              printf "\e[31m[ERROR] %s\e[m\n" "   -> Unknown deploy mode: $MODE"
              exit 1
              ;;
          esac
          ;;
        "git")
          printf "\e[32m[INFO] %s\e[m\n" "-> Application $APP_FULL_NAME is a Git repository."

          MANIFESTS_PATH=$(cat $APP_MANIFEST | yq -r '.spec.sources[] | select(has("path")) | .path')
          MANIFESTS_DIR="$REPO_ROOT_DIR/$MANIFESTS_PATH"
          if [ ! -d "$MANIFESTS_DIR" ]; then
            printf "\e[31m[ERROR] %s\e[m\n" "  -> Manifests directory not found: $MANIFESTS_DIR"
            exit 1
          fi

          printf "\e[32m[INFO] %s\e[m\n" "   -> Manifests directory  : $MANIFESTS_PATH"
          printf "\e[32m[INFO] %s\e[m\n" "   -> Destination namespace: $DESTINATION_NAMESPACE"

          case $MODE in
            "INSTALL")
              for MANIFEST_FILE in $MANIFESTS_DIR/*.yaml
              do
                MANIFEST_NAME=$(basename "$MANIFEST_FILE" .yaml)
                printf "\e[32m[INFO] %s\e[m\n" "      -> Applying manifest: $MANIFEST_NAME"
                kubectl apply -f $MANIFEST_FILE --namespace $DESTINATION_NAMESPACE
                printf "\e[32m[INFO] %s\e[m\n" "      -> Applying manifest: $MANIFEST_NAME: DONE"
              done
              ;;
            "DELETE")
              for MANIFEST_FILE in $MANIFESTS_DIR/*.yaml
              do
                MANIFEST_NAME=$(basename "$MANIFEST_FILE" .yaml)
                printf "\e[32m[INFO] %s\e[m\n" "      -> Deleting manifest: $MANIFEST_NAME"
                kubectl delete -f $MANIFEST_FILE --namespace $DESTINATION_NAMESPACE || true
                printf "\e[32m[INFO] %s\e[m\n" "      -> Deleting manifest: $MANIFEST_NAME: DONE"
              done
              ;;
            "DEVELOP")
              # Skip
              ;;
            "PRODUCT")
              # Skip
              ;;
            *)
              printf "\e[31m[ERROR] %s\e[m\n" "      -> Unknown deploy mode: $MODE"
              exit 1
              ;;
          esac
          ;;
        "ref")
          # Skip the 'ref' field as it is not a source type but a reference to a specific version in Git.
          ;;
        *)
          printf "\e[32m[INFO] %s\e[m\n" "   -> Application $APP_FULL_NAME is an unknown type."
          exit 1
          ;;
      esac
    done

    if [ $MODE != "INSTALL" ]; then
      continue
    fi

    if cat $APP_MANIFEST | yq '.spec.sources[] | has("path")' | grep -q true; then
      printf "\e[32m[INFO] %s\e[m\n" "   -> Application $APP_FULL_NAME has a git source."

      if [ $(kubectl get pods -n $DESTINATION_NAMESPACE --no-headers | grep -c $APP_NAME) -eq 0 ]; then
        printf "\e[32m[INFO] %s\e[m\n" "      -> No pods found for application $APP_NAME in namespace $DESTINATION_NAMESPACE after deployment."
        continue
      else
        printf "\e[32m[INFO] %s\e[m\n" "      -> Pods found for application $APP_NAME in namespace $DESTINATION_NAMESPACE after deployment."
      fi
    fi

    printf "\e[32m[INFO] %s\e[m\n" "      -> Waiting for pods in namespace $DESTINATION_NAMESPACE to be deployed."
    until kubectl get pods -n $DESTINATION_NAMESPACE --no-headers | grep -q $APP_NAME
    do
      printf "\e[32m[INFO] %s\e[m\n" "         -> Checking for pods with name containing: $APP_NAME in namespace: $DESTINATION_NAMESPACE"
      printf "\e[32m[INFO] %s\e[m\n" "         -> Retrying in 10 seconds..."
      sleep 10
    done
    printf "\e[32m[INFO] %s\e[m\n" "      -> Waiting for pods in namespace $DESTINATION_NAMESPACE to be deployed: DONE"

    if [ -f $POST_DEPLOYMENT_SCRIPTS_DIR/$APP_NAME.sh ]; then
      printf "\e[32m[INFO] %s\e[m\n" "      -> Running post-deployment script for $APP_NAME."
      source $POST_DEPLOYMENT_SCRIPTS_DIR/$APP_NAME.sh
      printf "\e[32m[INFO] %s\e[m\n" "      -> Running post-deployment script for $APP_NAME: DONE"
    fi

    printf "\e[32m[INFO] %s\e[m\n" "      -> Waiting for pods in namespace $DESTINATION_NAMESPACE to become running..."
    until [ -z "$(kubectl get pods -n $DESTINATION_NAMESPACE --no-headers | grep $APP_NAME | grep -v Completed | awk -F'[/ ]+' '$2 != $3 || $4 != "Running"')" ]
    do
      printf "\e[32m[INFO] %s\e[m\n" "         -> Checking if pods with name containing: $APP_NAME in namespace: $DESTINATION_NAMESPACE are running"
      printf "\e[32m[INFO] %s\e[m\n" "         -> Retrying in 10 seconds..."
      sleep 10
    done
    printf "\e[32m[INFO] %s\e[m\n" "      -> Waiting for pods in namespace $DESTINATION_NAMESPACE to become running...: DONE"
  done
done
printf "\e[32m[INFO] %s\e[m\n" "Deploying the applications: DONE"

#
# Restart CoreDNS
#

printf "\e[32m[INFO] %s\e[m\n" "Restart CoreDNS and Traefik."
kubectl --namespace kube-system rollout restart deployment coredns traefik
printf "\e[32m[INFO] %s\e[m\n" "Restart CoreDNS and Traefik: DONE"

printf "\e[32m[INFO] %s\e[m\n" "All applications are deployed successfully."

exit 0
