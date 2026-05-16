#
# Realm
#

resource "keycloak_realm" "realms" {
  for_each = var.realms

  realm        = each.key
  enabled      = true
  display_name = each.value.display_name
}
