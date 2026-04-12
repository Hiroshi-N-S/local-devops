#
# Auth configurations
#

resource "harbor_config_auth" "oidc" {
  auth_mode           = "oidc_auth"
  primary_auth_mode   = var.harbor_oidc_config.primary_auth_mode
  oidc_name           = var.harbor_oidc_config.provider_name
  oidc_endpoint       = var.harbor_oidc_config.issuer_endpoint
  oidc_client_id      = var.harbor_oidc_config.client_id
  oidc_client_secret  = var.harbor_oidc_config.client_secret
  oidc_groups_claim   = var.harbor_oidc_config.groups_claim
  oidc_admin_group    = var.harbor_oidc_config.admin_group
  oidc_scope          = join(",", var.harbor_oidc_config.scopes)
  oidc_verify_cert    = var.harbor_oidc_config.verify_cert
  oidc_auto_onboard   = var.harbor_oidc_config.auto_onboard
  oidc_user_claim     = var.harbor_oidc_config.user_claim
}
