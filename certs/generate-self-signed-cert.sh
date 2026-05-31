#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
UTILITY_SCRIPTS_DIR="$REPO_ROOT_DIR/utility-scripts"

CERT_FILE_NAME=${CERT_FILE_NAME:-'local-devenv'}
CERT_EXPIRATION_DAYS=${CERT_EXPIRATION_DAYS:-3650}

COMMON_NAME=${COMMON_NAME:-'devenv.local'}
COUNTRY_NAME=${COUNTRY_NAME:-'JP'}
STATE_NAME=${STATE_NAME:-'Osaka'}
LOCALITY_NAME=${LOCALITY_NAME:-'Osaka'}
ORGANIZATION_NAME=${ORGANIZATION_NAME:-'Personal'}

#
# Import utility functions.
#

. "$UTILITY_SCRIPTS_DIR/utilities.sh"

#
# Check if the certificate is already expired.
#

if [ -e $SCRIPT_DIR/$CERT_FILE_NAME.crt ]; then
  # Check if expiring within 30 days / 2,592,000 seconds.
  if openssl x509 -in $SCRIPT_DIR/$CERT_FILE_NAME.crt -checkend 2592000 > /dev/null; then
     info "Certificate is valid and not expired: $SCRIPT_DIR/$CERT_FILE_NAME.crt"
     info "Skipping certificate generation."
     exit 0
  fi

  warn "Certificate is expired: $SCRIPT_DIR/$CERT_FILE_NAME.crt"
  warn "Regenerating the certificate."

  info "Cleaning up old certificates in $SCRIPT_DIR."
  rm -rf $SCRIPT_DIR/$CERT_FILE_NAME{.crt,.key,-ca.crt,-ca.key}
  info "Cleaning up old certificates in $SCRIPT_DIR: DONE"
fi

#
# Remove all other files in $SCRIPT_DIR except the script itself.
#

info "Cleaning up old certificates in $SCRIPT_DIR."
ls $SCRIPT_DIR | grep -ivE "$(basename $0)" | xargs rm -rf || true
info "Cleaning up old certificates in $SCRIPT_DIR: DONE"

#
# Generate a self-signed certificate for local development environment.
#

info "Generating certificates for local development environment."

info "Certificate file name       : $CERT_FILE_NAME"
info "Common Name (CN)            : $COMMON_NAME"
info "Country Name (C)            : $COUNTRY_NAME"
info "State or Province Name (ST) : $STATE_NAME"
info "Locality Name (L)           : $LOCALITY_NAME"
info "Organization Name (O)       : $ORGANIZATION_NAME"

info "Generating a private key."
openssl genrsa -out $SCRIPT_DIR/$CERT_FILE_NAME-ca.key 4096
info "Generating a private key: DONE"

info "Generating a self-signed certificate instead of a CSR (Certificate Signing Request)."
openssl req -new -x509 -sha512 \
  -days $CERT_EXPIRATION_DAYS \
  -key $SCRIPT_DIR/$CERT_FILE_NAME-ca.key \
  -out $SCRIPT_DIR/$CERT_FILE_NAME-ca.crt \
  -subj "/C=$COUNTRY_NAME/ST=$STATE_NAME/L=$LOCALITY_NAME/O=$ORGANIZATION_NAME/CN=$COMMON_NAME"
info "Generating a self-signed certificate instead of a CSR (Certificate Signing Request): DONE"

info "Generating an x509 v3 extension file for the local development environment."
cat <<EOF >$SCRIPT_DIR/v3.ext
authorityKeyIdentifier = keyid,issuer
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = @alt_names

[alt_names]
DNS.1                  = $COMMON_NAME
DNS.2                  = *.$COMMON_NAME
EOF
info "Generating an x509 v3 extension file for the local development environment: DONE"

info "Generating a private key and a CSR (Certificate Signing Request) for the local development environment."
openssl req -newkey rsa:4096 -nodes -sha512 \
  -keyout $SCRIPT_DIR/$CERT_FILE_NAME.key \
  -out $SCRIPT_DIR/$CERT_FILE_NAME.csr \
  -subj "/C=$COUNTRY_NAME/ST=$STATE_NAME/L=$LOCALITY_NAME/O=$ORGANIZATION_NAME/CN=$COMMON_NAME"
info "Generating a private key and a CSR (Certificate Signing Request) for the local development environment: DONE"

info "Signing the certificate with the $CERT_FILE_NAME-ca."
openssl x509 -req -sha512 -days $CERT_EXPIRATION_DAYS \
  -in $SCRIPT_DIR/$CERT_FILE_NAME.csr \
  -out $SCRIPT_DIR/$CERT_FILE_NAME.crt \
  -CA $SCRIPT_DIR/$CERT_FILE_NAME-ca.crt \
  -CAkey $SCRIPT_DIR/$CERT_FILE_NAME-ca.key \
  -CAcreateserial \
  -extfile $SCRIPT_DIR/v3.ext
info "Signing the certificate with the CA: DONE"

info "Cleaning up temporary files."
rm -rf $SCRIPT_DIR/v3.ext $SCRIPT_DIR/$CERT_FILE_NAME-ca.srl $SCRIPT_DIR/$CERT_FILE_NAME.csr
info "Cleaning up temporary files: DONE"
