#
# OpenID Client Default Scopes
#

resource "keycloak_openid_client_default_scopes" "oidc_client_default_scopes" {
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

  realm_id               = keycloak_realm.realms[each.value.realm_key].id
  client_id              = keycloak_openid_client.oidc_clients[each.key].id
  default_scopes         = concat(
    each.value.client_data.default_scopes, [
      for scope_key, scope_value in each.value.client_data.client_scopes : scope_key
    ]
  )
}

#
# OpenID Client Optional Scopes
#

resource "keycloak_openid_client_optional_scopes" "optional_scopes" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for client_key, client_value in realm_value.clients : {
          key        = "${realm_key}-${client_key}"
          realm_key  = realm_key
          client_key = client_key
        }
      ]
    ]) : i.key => i
  }

  realm_id         = keycloak_realm.realms[each.value.realm_key].id
  client_id        = keycloak_openid_client.oidc_clients[each.value.key].id
  optional_scopes  = [
    keycloak_openid_client_scope.realm_roles_scopes[each.value.realm_key].name
  ]
}

#
# OpenID Client Scopes
#

resource "keycloak_openid_client_scope" "realm_roles_scopes" {
  for_each = var.realms

  realm_id               = keycloak_realm.realms[each.key].id
  name                   = "realm-roles"
  description            = "OpenID Connect scope for adding user roles to the access token"
  include_in_token_scope = true
}

resource "keycloak_openid_client_scope" "oidc_client_scopes" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for client_key, client_value in realm_value.clients : [
          for scope_key, scope_value in client_value.client_scopes : {
            key         = "${realm_key}-${client_key}-${scope_key}" 
            realm_key   = realm_key
            client_key  = client_key
            scope_key   = scope_key
            scope_value = scope_value
          }
        ]
      ]
    ]) : i.key => i
  }

  realm_id               = keycloak_realm.realms[each.value.realm_key].id
  name                   = each.value.scope_key
  description            = each.value.scope_value.description
  include_in_token_scope = each.value.scope_value.include_in_token_scope
}

#
# Realm Role Mappers
#

resource "keycloak_openid_user_realm_role_protocol_mapper" "realm_role_mapper" {
  for_each = var.realms

  realm_id            = keycloak_realm.realms[each.key].id
  client_scope_id     = keycloak_openid_client_scope.realm_roles_scopes["${each.key}"].id

  name                = "realm-roles-mapper"
  claim_name          = "groups"
  claim_value_type    = "string"
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
  multivalued         = true
}

resource "keycloak_openid_user_realm_role_protocol_mapper" "realm_role_mapper_for_realm_roles" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for client_key, client_value in realm_value.clients : [
          for scope_key, scope_value in client_value.client_scopes : [
            for mapper_key, mapper_value in scope_value.user_realm_role_mappers : {
              key          = "${realm_key}-${client_key}-${scope_key}-${mapper_key}"
              realm_key    = realm_key
              client_key   = client_key
              scope_key    = scope_key
              mapper_key   = mapper_key
              mapper_value = mapper_value
            }
          ]
        ]
      ]
    ]) : i.key => i
  }

  realm_id             = keycloak_realm.realms[each.value.realm_key].id
  client_scope_id      = keycloak_openid_client_scope.oidc_client_scopes["${each.value.realm_key}-${each.value.client_key}-${each.value.scope_key}"].id
  name                 = "${each.value.mapper_key}-mapper"
  claim_name           = each.value.mapper_value.token_claim_name
  claim_value_type     = each.value.mapper_value.claim_json_type
  add_to_id_token      = each.value.mapper_value.add_to_id_token
  add_to_access_token  = each.value.mapper_value.add_to_access_token
  add_to_userinfo      = each.value.mapper_value.add_to_userinfo
  multivalued          = each.value.mapper_value.multivalued
}
