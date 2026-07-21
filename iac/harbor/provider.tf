#
# Harbor
#

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = ">= 3.0.0"
    }
  }
}

provider "harbor" {
  url          = var.provider_config.url
  username     = var.provider_config.username
  password     = var.provider_config.password
  bearer_token = var.provider_config.bearer_token
  insecure     = var.provider_config.tls_insecure
  api_version  = var.provider_config.api_version
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
