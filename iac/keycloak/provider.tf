#
# Keycloak
#

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.0.0"
    }
  }
}

provider "keycloak" {
  client_id                 = var.provider_config.client_id
  client_secret             = var.provider_config.client_secret
  url                       = var.provider_config.url
  tls_insecure_skip_verify  = var.provider_config.tls_insecure
}
