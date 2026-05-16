#
# Roles
#

resource "keycloak_role" "realm-roles" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for client_key, client_value in realm_value.clients : [
          for role_key, role_value in client_value.roles : {
            key         = "${realm_key}-${client_key}-${role_key}"
            realm_key   = realm_key
            client_key  = client_key
            role_key    = role_key
            role_data   = role_value
          }
        ]
      ]
    ]) : i.key => i
  }

  realm_id    = keycloak_realm.realms[each.value.realm_key].id
  name        = each.value.role_key
  description = each.value.role_data.description
  attributes  = each.value.role_data.attributes
}
