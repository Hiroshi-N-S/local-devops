#
# Vault Kubernetes Auth Method Configuration
#

locals {
  # Read Kubernetes Auth Method configuration from a file.
  k8s_config_file = fileexists("${path.module}/.k8s-configs.yaml") ? file("${path.module}/.k8s-configs.yaml") : ""

  # Read Kubernetes CA certificate and token reviewer JWT from variables or the configuration file.  
  k8s_ca_cert = var.kubernetes_auth.config.ca_cert != "" ? var.kubernetes_auth.config.ca_cert : (
    local.k8s_config_file != "" ? trimspace(
      regex("(?m)^k8s-ca-cert:\\s*([^\\n]+)", local.k8s_config_file)[0]
    ) : ""
  )

  # Read Kubernetes token reviewer JWT from variables or the configuration file.
  # The token reviewer JWT is used by Vault to authenticate with the Kubernetes API server when validating service account tokens.
  k8s_token_reviewer_jwt = var.kubernetes_auth.config.token_reviewer_jwt != "" ? var.kubernetes_auth.config.token_reviewer_jwt : (
    local.k8s_config_file != "" ? trimspace(
      regex("(?m)^k8s-token-reviewer-jwt:\\s*([^\\n]+)", local.k8s_config_file)[0]
    ) : ""
  )
}

#
# Kubernetes Auth Method
#

resource "vault_auth_backend" "kubernetes_auth" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes_auth_config" {
  backend                       = vault_auth_backend.kubernetes_auth.path
  kubernetes_host               = var.kubernetes_auth.config.host
  kubernetes_ca_cert            = base64decode(local.k8s_ca_cert)
  token_reviewer_jwt_wo         = base64decode(local.k8s_token_reviewer_jwt)
  token_reviewer_jwt_wo_version = 1
  issuer                        = var.kubernetes_auth.config.issuer
  disable_iss_validation        = var.kubernetes_auth.config.disable_iss_validation
}

resource "vault_kubernetes_auth_backend_role" "kubernetes_auth_role" {
  backend                          = vault_auth_backend.kubernetes_auth.path
  role_name                        = var.kubernetes_auth.role.name
  bound_service_account_names      = var.kubernetes_auth.role.bound_service_account_names
  bound_service_account_namespaces = var.kubernetes_auth.role.bound_service_account_namespaces
  token_ttl                        = var.kubernetes_auth.role.token_ttl
  token_policies                   = [
    for policy_key in keys(var.kubernetes_auth.secret_engines_and_policies) :
      "${policy_key}-policy"
  ]
}
