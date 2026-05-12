# Keycloak

Manages Keycloak realms, clients, users, groups, and roles.

- **Provider**: [keycloak/keycloak](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs) >= 5.0.0
- **Terraform**: >= 1.13.0

## Configuration

Copy the sample file and fill in the values for your environment:

```bash
cp variables.tfvars.sample variables.tfvars
# Edit variables.tfvars with your actual values
```

### Variables

| Variable                        | Description                                            |
| ------------------------------- | ------------------------------------------------------ |
| `provider_config.url`           | Keycloak server URL (e.g. `https://auth.devenv.local`) |
| `provider_config.client_id`     | Keycloak admin client ID                               |
| `provider_config.client_secret` | Keycloak admin client secret                           |
| `provider_config.tls_insecure`  | Skip TLS verification (default: `false`)               |
| `realms`                        | Map of realms with users, groups, clients, and roles   |

## Usage

```bash
# 1. Initialize the working directory and download providers
terraform init

# 2. Preview the changes to be applied
terraform plan -var-file=variables.tfvars

# 3. Apply the changes
terraform apply -var-file=variables.tfvars
```
