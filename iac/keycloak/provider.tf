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
  client_id                = var.provider_config.client_id
  client_secret            = var.provider_config.client_secret
  url                      = var.provider_config.url
  tls_insecure_skip_verify = var.provider_config.tls_insecure
}

#
# Vault Provider Configuration
#

locals {
  # Read Vault token from a file.
  vault_config_file = fileexists("~/.vault-initial.config") ? file("~/.vault-initial.config") : ""

  # Read a variable from a variable or `.vault-initial.config` and set it as the token for authentication. This allows for flexible configuration of the Vault token, enabling users to either store it in a file or set it as an environment variable.
  vault_token = var.vault_provider_config.token != "" ? var.vault_provider_config.token : (
    local.vault_config_file != "" ? trimspace(
      regex("(?m)^Initial Root Token:\\s*([^\\n]+)", local.vault_config_file)[0]
    ) : ""
  )
}

#
# Vault
#

provider "vault" {
  address         = var.vault_provider_config.url
  skip_tls_verify = var.vault_provider_config.skip_tls_verify
  token           = local.vault_token
}
