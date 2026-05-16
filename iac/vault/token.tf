#
# Token definitions for Kubernetes secrets
#

# resource "vault_token" "client_token" {
#   for_each = var.kv2_secrets_engines

#   policies  = [
#     for p_key, p_value in each.value.policies : p_key
#   ]
#   ttl       = "24h"
#   renewable = true
# }

# output "client_tokens" {
#   value = [
#     for k, v in vault_token.client_token : v.id
#   ]
# }
