# local-devops

This repository contains configurations to set up a local development environment.

``` mermaid
---
config:
  layout: elk
  look: classic
  theme: default
---
graph TB
  subgraph LocalDevEnv["local-devenv"]
    subgraph "Developer Tools"
      Git[("Git Repository<br/>(GitHub)")]
      Terraform[("IaC Tool<br/>(Terraform)")]
    end

    subgraph "External Services"
      NFS[("NFS Server")]
    end

    subgraph K3s["Kubernetes Cluster (K3s)"]
      subgraph InfrastructureNamespace["Infrastructure Namespace"]
        CSI["NFS CSI driver<br/>(Kubernetes CSI)"]
        Vault[("Secret Storage<br/>(Vault)")]
        ESO[("Secret Management<br/>(External Secrets)")]
        ArgoCD[("GitOps Controller<br/>(Argo CD)")]
        Harbor[("Container Registry<br/>(Harbor)")]
      end

      subgraph ApplicationNamespace["Application Namespace"]
        K8sSecret["Secret/ConfigMap"]
        Apps["Applications"]
      end


    end
  end

  %% Connections
  Git <-- "1. Sync Declarative Definitions" --> ArgoCD
  Terraform -- "1. Apply Declarative Configurations" ----> Vault
  ArgoCD --"2. Self Management" --> ArgoCD
  ArgoCD -- "2. Deploy Resources" --> CSI
  ArgoCD -- "2. Deploy Resources" --> ESO
  ArgoCD -- "2. Deploy Resources" --> Harbor
  ArgoCD -- "2. Deploy Resources" --> Apps

  Harbor -- "3. Pull Image" --> Apps

  CSI -- "3. Mount NFS" --> NFS
  CSI -- "4. Mount PersistentVolumes" --> Apps

  ESO -- "3. Authentication & Fetch" --> Vault
  ESO -- "4. Deploy Secrets/ConfigMaps" --> K8sSecret

  K8sSecret -- "5. Mount Secrets/ConfigMaps" --> Apps

  %% Styles
  style LocalDevEnv fill:white,stroke:darkgray
  style K3s fill:gold,stroke:white
  style InfrastructureNamespace fill:white,stroke:white
  style ApplicationNamespace fill:white,stroke:white
  style Vault fill:goldenrod,stroke:white
  style ArgoCD fill:orange,stroke:white
  style ESO fill:cornflowerblue,stroke:white
  style Harbor fill:steelblue,stroke:white
```
