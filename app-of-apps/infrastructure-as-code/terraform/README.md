# Terraform

This directory contains Terraform configurations to provision infrastructure components
of the local development environment.

## Providers

| Provider                                                                          | Registry                   | Description                    |
| --------------------------------------------------------------------------------- | -------------------------- | ------------------------------ |
| [Vault](https://registry.terraform.io/providers/hashicorp/vault/latest/docs)      | hashicorp/vault >= 5.0.0   | Secret storage                 |
| [Keycloak](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs) | keycloak/keycloak >= 5.0.0 | Identity and access management |

## Prerequisites

- **Terraform** >= 1.13.0 (currently the latest security-supported version)
- A running K3s cluster with Vault and Keycloak already deployed.

## Directory Structure

```
terraform/
├── vault/      # Vault secret engines, policies, and Kubernetes auth configuration
└── keycloak/   # Keycloak realms, clients, users, groups, and roles
```

## Configuration

Each subdirectory manages a separate provider. See the README in each subdirectory for
variables and configuration details.

| Subdirectory | README                                   | Description                               |
| ------------ | ---------------------------------------- | ----------------------------------------- |
| vault/       | [vault/README.md](vault/README.md)       | Secret engines, policies, Kubernetes auth |
| keycloak/    | [keycloak/README.md](keycloak/README.md) | Realms, clients, users, groups, roles     |

## Usage

Run the following commands in each subdirectory (`vault/` or `keycloak/`):

```bash
# 1. Initialize the working directory and download providers
terraform init

# 2. Preview the changes to be applied
terraform plan -var-file=variables.tfvars

# 3. Apply the changes
terraform apply -var-file=variables.tfvars
```
