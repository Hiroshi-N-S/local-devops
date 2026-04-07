#
# Secrets Engines mount for Kubernetes secrets
#

resource "vault_mount" "kv2_secrets_engines" {
  for_each = var.kubernetes_auth.secret_engines_and_policies

  path        = each.key
  type        = "kv"
  options = {
    version   = "2"
  }
  description = each.value.description
}

#
# Secrets for Kubernetes secrets kv2 Secrets Engine
#

resource "vault_kv_secret_v2" "kv2_secrets_engines_data" {
  for_each = {
    for i in flatten([
      for se_key, se_value in var.kubernetes_auth.secret_engines_and_policies : [
        for data_key, data_value in se_value.data : {
          key       = "${se_key}-${data_key}"
          se_key    = se_key
          data_key  = data_key
          data_json = jsonencode({
            for k, v in data_value :
              k => startswith(v, "file:") ? file(join("/", [
                path.module,
                replace(v, "file:", "")
              ])) : v
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
