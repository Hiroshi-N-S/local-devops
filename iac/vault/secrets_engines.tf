#
# Secrets Engines mount for Kubernetes secrets
#

resource "vault_mount" "kv2_secrets_engines" {
  for_each = var.kubernetes_auth.secret_engines_and_policies

  path = each.key
  type = "kv"
  options = {
    version = "2"
  }
  description = each.value.description
}

#
# Random passwords for Kubernetes secrets kv2 Secrets Engine
#

resource "random_password" "kv2_secrets_engines_random_passwords" {
  for_each = {
    for i in flatten([
      for se_key, se_value in var.kubernetes_auth.secret_engines_and_policies : [
        for rp_key, rp_value in se_value.random_passwords : {
          key              = "${se_key}-${rp_key}"
          se_key           = se_key
          rp_key           = rp_key
          length           = rp_value.length
          special          = rp_value.special
          override_special = rp_value.override_special
        }
      ]
    ]) : i.key => i
  }

  length           = each.value.length
  special          = each.value.special
  override_special = each.value.override_special
}

#
# Secrets for Kubernetes secrets kv2 Secrets Engine
#

resource "vault_kv_secret_v2" "kv2_secrets_engines_data" {
  for_each = {
    for i in flatten([
      for se_key, se_value in var.kubernetes_auth.secret_engines_and_policies : [
        for data_key, data_value in merge(
          se_value.data, {
            for rp_key in keys(se_value.random_passwords) :
            rp_key => {
              secret = random_password.kv2_secrets_engines_random_passwords[
                "${se_key}-${rp_key}"
              ].result
            }
          }) : {
          key      = "${se_key}-${data_key}"
          se_key   = se_key
          data_key = data_key
          data_json = jsonencode({
            for k, v in data_value :
            k => (
              startswith(v, "file:") ? file(join("/", [
                path.module,
                replace(v, "file:", "")
              ])) :
              startswith(v, "random_password:") ? random_password.kv2_secrets_engines_random_passwords[
                "${se_key}-${replace(v, "random_password:", "")}"
              ].result :
              v
            )
          })
        }
      ]
    ]) : i.key => i
  }

  mount               = vault_mount.kv2_secrets_engines[each.value.se_key].path
  name                = each.value.data_key
  delete_all_versions = true
  data_json           = each.value.data_json
}
