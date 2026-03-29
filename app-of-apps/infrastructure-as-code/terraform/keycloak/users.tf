#
# Users
#

resource "keycloak_user" "users" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for user_key, user_value in realm_value.users : {
          key         = user_key
          realm_name  = realm_key
          user_data   = user_value
        }
      ]
    ]) : i.key => i
  }

  realm_id    = keycloak_realm.realms[each.value.realm_name].id
  username    = each.key
  email       = each.value.user_data.email
  first_name  = each.value.user_data.first_name
  last_name   = each.value.user_data.last_name
  enabled     = each.value.user_data.enabled
  initial_password {
    value     = "${each.value.user_data.first_name}.${each.value.user_data.last_name}"
    temporary = true
  }
}

resource "keycloak_user_groups" "user_groups" {
  for_each = {
    for i in flatten([
      for realm_key, realm_value in var.realms : [
        for user_key, user_value in realm_value.users : {
          key         = user_key
          realm_name  = realm_key
          user_data   = user_value
          group_names = [
            for group_name in user_value.group_names : format("%s-%s", realm_key, replace(group_name, "/", "-"))
          ]
        }
      ]
    ]) : i.key => i
  }

  realm_id  = keycloak_realm.realms[each.value.realm_name].id
  user_id   = keycloak_user.users[each.key].id
  group_ids = [
    for group_name in each.value.group_names : keycloak_group.child_groups[group_name].id
  ]
}
