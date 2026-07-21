#
# Harbor OIDC Configuration
#

variable "harbor_oidc_config" {
  description = "Harbor OIDC configuration"
  type = object({
    primary_auth_mode      = bool
    provider_name          = string
    issuer_endpoint        = string
    client_id              = string
    groups_claim           = string
    admin_group            = string
    scopes                 = list(string)
    verify_cert            = optional(bool, true)
    auto_onboard           = optional(bool, false)
    user_claim             = optional(string, "name")
    vault_kv_v2_mount_path = string
  })
}

#
# Harbor Provider Configuration
#

variable "provider_config" {
  description = "Harbor provider configuration"
  type = object({
    url          = string
    username     = optional(string, null)
    password     = optional(string, null)
    bearer_token = optional(string, null)
    tls_insecure = optional(bool, false)
    api_version  = optional(number, 2)
  })
}

#
# Vault Provider Configuration
#

variable "vault_provider_config" {
  description = "Vault provider configuration"
  type = object({
    url             = string
    token           = optional(string, "")
    skip_tls_verify = optional(bool, false)
  })
}
