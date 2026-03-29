#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$0")

CERT_FILE_NAME=${CERT_FILE_NAME:-'local-devenv'}
CERT_EXPIRATION_DAYS=${CERT_EXPIRATION_DAYS:-3650}

COMMON_NAME=${COMMON_NAME:-'devenv.local'}
COUNTRY_NAME=${COUNTRY_NAME:-'JP'}
STATE_NAME=${STATE_NAME:-'Osaka'}
LOCALITY_NAME=${LOCALITY_NAME:-'Osaka'}
ORGANIZATION_NAME=${ORGANIZATION_NAME:-'Personal'}

if [ -e $SCRIPT_DIR/$CERT_FILE_NAME.crt ]; then
  printf "\e[32m[INFO] %s\e[m\n" "Certificate already exists: $SCRIPT_DIR/$CERT_FILE_NAME.crt"
  printf "\e[32m[INFO] %s\e[m\n" "Skipping certificate generation."
  exit 0
fi

printf "\e[32m[INFO] %s\e[m\n" "Cleaning up old certificates in $SCRIPT_DIR."
ls $SCRIPT_DIR | grep -ivE "$(basename $0)" | xargs rm -rf || true
printf "\e[32m[INFO] %s\e[m\n" "Cleaning up old certificates in $SCRIPT_DIR: DONE"

printf "\e[32m[INFO] %s\e[m\n" "Generating certificates for local development environment."

printf "\e[32m[INFO] %s\e[m\n" "Certificate file name       : $CERT_FILE_NAME"
printf "\e[32m[INFO] %s\e[m\n" "Common Name (CN)            : $COMMON_NAME"
printf "\e[32m[INFO] %s\e[m\n" "Country Name (C)            : $COUNTRY_NAME"
printf "\e[32m[INFO] %s\e[m\n" "State or Province Name (ST) : $STATE_NAME"
printf "\e[32m[INFO] %s\e[m\n" "Locality Name (L)           : $LOCALITY_NAME"
printf "\e[32m[INFO] %s\e[m\n" "Organization Name (O)       : $ORGANIZATION_NAME"

printf "\e[32m[INFO] %s\e[m\n" "Generating a private key."
openssl genrsa -out $SCRIPT_DIR/$CERT_FILE_NAME-ca.key 4096
printf "\e[32m[INFO] %s\e[m\n" "Generating a private key: DONE"

printf "\e[32m[INFO] %s\e[m\n" "Generating a self-signed certificate instead of a CSR (Certificate Signing Request)."
openssl req -new -x509 -sha512 \
  -days $CERT_EXPIRATION_DAYS \
  -key $SCRIPT_DIR/$CERT_FILE_NAME-ca.key \
  -out $SCRIPT_DIR/$CERT_FILE_NAME-ca.crt \
  -subj "/C=$COUNTRY_NAME/ST=$STATE_NAME/L=$LOCALITY_NAME/O=$ORGANIZATION_NAME/CN=$COMMON_NAME"
printf "\e[32m[INFO] %s\e[m\n" "Generating a self-signed certificate instead of a CSR (Certificate Signing Request): DONE"

printf "\e[32m[INFO] %s\e[m\n" "Generating an x509 v3 extension file for the local development environment."
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
printf "\e[32m[INFO] %s\e[m\n" "Generating an x509 v3 extension file for the local development environment: DONE"

printf "\e[32m[INFO] %s\e[m\n" "Generating a private key and a CSR (Certificate Signing Request) for the local development environment."
openssl req -newkey rsa:4096 -nodes -sha512 \
  -keyout $SCRIPT_DIR/$CERT_FILE_NAME.key \
  -out $SCRIPT_DIR/$CERT_FILE_NAME.csr \
  -subj "/C=$COUNTRY_NAME/ST=$STATE_NAME/L=$LOCALITY_NAME/O=$ORGANIZATION_NAME/CN=$COMMON_NAME"
printf "\e[32m[INFO] %s\e[m\n" "Generating a private key and a CSR (Certificate Signing Request) for the local development environment: DONE"

printf "\e[32m[INFO] %s\e[m\n" "Signing the certificate with the $CERT_FILE_NAME-ca."
openssl x509 -req -sha512 -days $CERT_EXPIRATION_DAYS \
  -in $SCRIPT_DIR/$CERT_FILE_NAME.csr \
  -out $SCRIPT_DIR/$CERT_FILE_NAME.crt \
  -CA $SCRIPT_DIR/$CERT_FILE_NAME-ca.crt \
  -CAkey $SCRIPT_DIR/$CERT_FILE_NAME-ca.key \
  -CAcreateserial \
  -extfile $SCRIPT_DIR/v3.ext
printf "\e[32m[INFO] %s\e[m\n" "Signing the certificate with the CA: DONE"

printf "\e[32m[INFO] %s\e[m\n" "Cleaning up temporary files."
rm -rf $SCRIPT_DIR/v3.ext $SCRIPT_DIR/$CERT_FILE_NAME-ca.srl $SCRIPT_DIR/$CERT_FILE_NAME.csr
printf "\e[32m[INFO] %s\e[m\n" "Cleaning up temporary files: DONE"
