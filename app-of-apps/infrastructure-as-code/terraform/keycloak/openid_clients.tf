#
# OpenID Connect Clients
#

resource "keycloak_openid_client" "oidc_clients" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for client_key, client_value in realm_value.clients : {
          key         = "${realm_key}-${client_key}"
          realm_key   = realm_key
          client_key  = client_key
          client_data = client_value
        }
      ]
    ]) : i.key => i
  }

  realm_id                        = keycloak_realm.realms[each.value.realm_key].id
  client_id                       = each.value.client_key
  enabled                         = each.value.client_data.enabled
  name                            = each.value.client_data.name
  description                     = each.value.client_data.description
  access_type                     = each.value.client_data.access_type
  standard_flow_enabled           = each.value.client_data.standard_flow_enabled
  implicit_flow_enabled           = each.value.client_data.implicit_flow_enabled
  direct_access_grants_enabled    = each.value.client_data.direct_access_grants_enabled
  service_accounts_enabled        = each.value.client_data.service_accounts_enabled
  root_url                        = each.value.client_data.root_url
  base_url                        = each.value.client_data.base_url
  valid_redirect_uris             = each.value.client_data.valid_redirect_uris
  valid_post_logout_redirect_uris = each.value.client_data.valid_post_logout_redirect_uris
  web_origins                     = each.value.client_data.web_origins
  admin_url                       = each.value.client_data.admin_url
}
