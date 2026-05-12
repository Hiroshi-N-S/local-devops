# Vault

Manages Vault secret engines, policies, and Kubernetes auth configuration.

- **Provider**: [hashicorp/vault](https://registry.terraform.io/providers/hashicorp/vault/latest/docs) >= 5.0.0
- **Terraform**: >= 1.13.0

## Configuration

Copy the sample file and fill in the values for your environment:

```bash
cp variables.tfvars.sample variables.tfvars
# Edit variables.tfvars with your actual values
```

### Variables

| Variable                          | Description                                                      |
| --------------------------------- | ---------------------------------------------------------------- |
| `provider_config.url`             | Vault server URL (e.g. `https://vault.devenv.local`)             |
| `provider_config.token`           | Vault root or management token                                   |
| `provider_config.skip_tls_verify` | Skip TLS verification (default: `false`)                         |
| `kubernetes_auth`                 | Kubernetes auth method configuration (host, CA cert, JWT, roles) |

## Usage

```bash
# 1. Initialize the working directory and download providers
terraform init

# 2. Preview the changes to be applied
terraform plan -var-file=variables.tfvars

# 3. Apply the changes
terraform apply -var-file=variables.tfvars
```
