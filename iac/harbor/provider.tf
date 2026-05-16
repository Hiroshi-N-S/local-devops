#
# Harbor
#

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    harbor = {
      source = "goharbor/harbor"
      version = ">= 3.0.0"
    }
  }
}

provider "harbor" {
  url           = var.provider_config.url
  username      = var.provider_config.username
  password      = var.provider_config.password
  bearer_token  = var.provider_config.bearer_token
  insecure      = var.provider_config.tls_insecure
  api_version   = var.provider_config.api_version
}
