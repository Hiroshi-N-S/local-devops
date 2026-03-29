#
# Policies for Kubernetes secrets
#

resource "vault_policy" "k8s_token_policy" {
  for_each = var.kubernetes_auth.secret_engines_and_policies

  name   = "${each.key}-policy"
  policy = <<-EOT
    path "${each.key}/${each.value.path}" {
      capabilities = ${jsonencode(each.value.capabilities)}
    }
  EOT
}
