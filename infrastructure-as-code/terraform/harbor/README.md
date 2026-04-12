# Harbor

Manages Harbor OIDC authentication via Keycloak.

- **Provider**: [goharbor/harbor](https://registry.terraform.io/providers/goharbor/harbor/latest/docs) >= 3.0.0
- **Terraform**: >= 1.13.0

## Configuration

Copy the sample file and fill in the values for your environment:

```bash
cp variables.tfvars.sample variables.tfvars
# Edit variables.tfvars with your actual values
```

### Variables

| Variable                               | Description                                              |
| -------------------------------------- | -------------------------------------------------------- |
| `provider_config.url`                  | Harbor server URL (e.g. `https://registry.devenv.local`) |
| `provider_config.username`             | Harbor admin username (optional)                         |
| `provider_config.password`             | Harbor admin password (optional)                         |
| `provider_config.bearer_token`         | Harbor bearer token (alternative to username/password)   |
| `provider_config.tls_insecure`         | Skip TLS verification (default: `false`)                 |
| `provider_config.api_version`          | Harbor API version (default: `2`)                        |
| `harbor_oidc_config.primary_auth_mode` | Enable OIDC as the primary authentication mode           |
| `harbor_oidc_config.provider_name`     | OIDC provider display name                               |
| `harbor_oidc_config.issuer_endpoint`   | Keycloak OIDC issuer URL                                 |
| `harbor_oidc_config.client_id`         | Keycloak client ID for Harbor                            |
| `harbor_oidc_config.client_secret`     | Keycloak client secret for Harbor                        |
| `harbor_oidc_config.scopes`            | OIDC scopes (list)                                       |
| `harbor_oidc_config.groups_claim`      | JWT claim for group mapping                              |
| `harbor_oidc_config.admin_group`       | Group name granted admin privileges                      |
| `harbor_oidc_config.verify_cert`       | Verify Keycloak TLS certificate (default: `true`)        |
| `harbor_oidc_config.auto_onboard`      | Auto-onboard OIDC users (default: `false`)               |
| `harbor_oidc_config.user_claim`        | JWT claim for user name mapping (default: `name`)        |

## Usage

```bash
# 1. Initialize the working directory and download providers
terraform init

# 2. Preview the changes to be applied
terraform plan -var-file=variables.tfvars

# 3. Apply the changes
terraform apply -var-file=variables.tfvars
```
