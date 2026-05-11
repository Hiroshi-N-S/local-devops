#
# Groups
#

resource "keycloak_group" "parent_groups" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for group_key, group_value in realm_value.groups : {
          key         = "${realm_key}-${group_key}"
          realm_key   = realm_key
          group_key   = group_key
          group_value = group_value
        }
      ]
    ]) : i.key => i
  }

  realm_id    = keycloak_realm.realms[each.value.realm_key].id
  name        = each.value.group_key
  description = each.value.group_value.description
}

resource "keycloak_group" "child_groups" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for group_key, group_value in realm_value.groups : [
          for child_group_key, child_group_value in group_value.child_groups : {
            key         = "${realm_key}-${group_key}-${child_group_key}"
            realm_key   = realm_key
            parent_key  = group_key
            group_key   = child_group_key
            group_value = child_group_value
          }
        ]
      ]
    ]) : i.key => i
  }

  realm_id   = keycloak_realm.realms[each.value.realm_key].id
  parent_id  = keycloak_group.parent_groups["${each.value.realm_key}-${each.value.parent_key}"].id
  name       = each.value.group_key
}

resource "keycloak_group_roles" "child_group_roles" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for group_key, group_value in realm_value.groups : [
          for child_group_key, child_group_value in group_value.child_groups : {
            key         = "${realm_key}-${group_key}-${child_group_key}"
            realm_key   = realm_key
            parent_key  = group_key
            group_key   = child_group_key
            group_value = child_group_value
          }
        ]
      ]
    ]) : i.key => i
  }

  realm_id = keycloak_realm.realms[each.value.realm_key].id
  group_id = keycloak_group.child_groups[each.value.key].id
  role_ids = [
    for realm-role in keycloak_role.realm-roles :
      realm-role.id if contains(each.value.group_value.role_names, realm-role.name)
  ]
}