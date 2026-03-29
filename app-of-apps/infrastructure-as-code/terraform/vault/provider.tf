#
# Vault Provider Configuration
#

locals {
  # Read Vault token from a file.
  vault_config_file = fileexists("${path.module}/.vault-initial.config") ? file("${path.module}/.vault-initial.config") : ""

  # Read a variable from a variable or `.vault-initial.config` and set it as the token for authentication. This allows for flexible configuration of the Vault token, enabling users to either store it in a file or set it as an environment variable.
  vault_token = var.provider_config.token != "" ? var.provider_config.token : (
     local.vault_config_file != "" ? trimspace(
      regex("(?m)^Initial Root Token:\\s*([^\\n]+)", local.vault_config_file)[0]
    ) : ""
  )
}

#
# Vault
#

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = ">= 5.0.0"
    }
  }
}

provider "vault" {
  address         = var.provider_config.url
  skip_tls_verify = var.provider_config.skip_tls_verify
  token           = local.vault_token
}
