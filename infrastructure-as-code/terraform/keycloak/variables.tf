#
# Realms with their users, groups and clients 
#

variable "realms" {
  description                         = "Realms with their clients"
  type                                = map(object({
    display_name                      = string
    users                             = optional(map(object({
      email                           = string
      first_name                      = string
      last_name                       = string
      enabled                         = optional(bool, true)
      group_names                     = optional(list(string), [])
    })), {})
    groups                            = optional(map(object({
      description                     = string
      child_groups                    = optional(map(object({
        description                   = string
        role_names                    = optional(list(string), [])
      })), {})
    })), {})
    clients                           = map(object({
      enabled                         = optional(bool, true)
      name                            = string
      description                     = string

      access_type                     = optional(string, "CONFIDENTIAL")
      standard_flow_enabled           = optional(bool, false)
      implicit_flow_enabled           = optional(bool, false)
      direct_access_grants_enabled    = optional(bool, false)
      service_accounts_enabled        = optional(bool, false)

      root_url                        = optional(string, null)
      base_url                        = optional(string, null)
      valid_redirect_uris             = optional(list(string), [])
      valid_post_logout_redirect_uris = optional(list(string), [])
      web_origins                     = optional(list(string), [])
      admin_url                       = optional(string, null)

      default_scopes                  = optional(list(string), [])
      client_scopes                   = optional(map(object({
        description                   = string
        include_in_token_scope        = optional(bool, false)
        user_realm_role_mappers       = optional(map(object({
          token_claim_name            = string
          claim_json_type             = optional(string, "String")
          add_to_id_token             = optional(bool, false)
          add_to_access_token         = optional(bool, false)
          add_to_userinfo             = optional(bool, false)
          multivalued                 = optional(bool, false)
        })), {})
      })), {})

      roles = optional(map(object({
        description                   = string
        attributes                    = optional(map(string), {})
      })), {})
    }))
  }))
}

#
# Keycloak Provider Configuration
#

variable "provider_config" {
  description     = "Keycloak provider configuration"
  type            = object({
    client_id     = string
    client_secret = string
    url           = string
    tls_insecure  = optional(bool, false)
  })
}
