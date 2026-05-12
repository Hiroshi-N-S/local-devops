#
# Kubernetes Auth Method
#

variable "kubernetes_auth" {
  description                          = "Kubernetes Auth Method configuration"
  type                                 = object({
    config                             = object({
      host                             = optional(string, "https://kubernetes.default.svc.cluster.local")
      ca_cert                          = optional(string, "")
      token_reviewer_jwt               = optional(string, "")
      issuer                           = optional(string, "api")
      disable_iss_validation           = optional(bool, true)
    })
    role                               = object({
      name                             = string
      bound_service_account_names      = list(string)
      bound_service_account_namespaces = list(string)
      token_ttl                        = optional(number, 3600)
    })
    secret_engines_and_policies        = map(object({
      description                      = string
      path                             = optional(string, "data/*")
      capabilities                     = optional(list(string), ["read", "list"])
      data                             = map(map(string))
    }))
  })
}

#
# Vault Provider Configuration
#

variable "provider_config" {
  description       = "Vault provider configuration"
  type              = object({
    url             = string
    token           = optional(string, "")
    skip_tls_verify = optional(bool, false)
  })
}
