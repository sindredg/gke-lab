# Secure GKE Workload Platform

```mermaid
flowchart TB
    User(["User"])
    Developer(["Developer"])

    subgraph Delivery["Infrastructure and delivery"]
        Terraform["Terraform"]
        GitHub["GitHub Actions"]
    end

    subgraph GCP["Google Cloud"]
        Ingress["Cloud DNS<br/>HTTPS load<br/>balancer"]
        Registry["Artifact Registry"]
        Identity["Workload<br/>Identity<br/>Federation"]
        Services["Pub/Sub<br/>Vertex AI<br/>Result store"]
        Observability["Cloud Logging<br/>Cloud Monitoring"]

        subgraph VPC["Custom VPC"]
            ControlPlane["GKE control plane<br/>DNS-only endpoint"]

            subgraph Cluster["GKE node pool"]
                Routes["Gateway and<br/>HTTPRoutes"]
                Workloads["NGINX frontend<br/>Review API<br/>and worker"]
                Guardrails["Pod Security<br/>NetworkPolicy<br/>Quotas"]
            end

            NAT["Cloud NAT"]
        end
    end

    User --> Ingress
    Ingress --> Routes
    Routes --> Workloads
    Guardrails -. protects .-> Workloads
    Developer --> Terraform
    Developer --> GitHub
    Terraform --> ControlPlane
    GitHub -. builds .-> Registry
    GitHub -. deploys .-> ControlPlane
    Registry -. images .-> Workloads
    ControlPlane --> Cluster
    Workloads --> NAT
    Workloads -. telemetry .-> Observability
    Workloads -. keyless identity .-> Identity
    Identity --> Services

    classDef external fill:#4B201D,stroke:#F28B82,color:#F8FAFC,stroke-width:2px
    classDef delivery fill:#493510,stroke:#FDD663,color:#F8FAFC,stroke-width:2px
    classDef workload fill:#123C2D,stroke:#81C995,color:#F8FAFC,stroke-width:2px
    classDef managed fill:#402060,stroke:#C58AF9,color:#F8FAFC,stroke-width:2px

    class User,Developer external
    class Terraform,GitHub delivery
    class ControlPlane,NAT,Routes,Workloads,Guardrails workload
    class Ingress,Registry,Identity,Services,Observability managed

    style Delivery fill:#211A0D,stroke:#FDD663,color:#F8FAFC,stroke-width:2px
    style GCP fill:#101828,stroke:#8AB4F8,color:#F8FAFC,stroke-width:2px
    style VPC fill:#102A23,stroke:#81C995,color:#F8FAFC,stroke-width:2px
    style Cluster fill:#183B31,stroke:#A8DAB5,color:#F8FAFC,stroke-width:2px
```

## Status

- Focus: secure workload delivery on GKE, with the AI reviewer as a later reference workload.
- Complete: private GKE foundation built with modular Terraform.
- Complete: NGINX Deployment, ClusterIP Service, probes, resources, scaling, self-healing, restart, and rollback validation.
- Complete: credential-free pull request validation, required on `main`.
- In progress: guarding the existing workload with Pod Security Admission, NetworkPolicy, and resource limits.
- Milestone 1: guard the existing NGINX workload, publish a custom image, add keyless delivery, expose it through Gateway API, and prove it with monitoring and failure tests.
- Milestone 2: add an AI-assisted manifest reviewer with deterministic validation before and after every model suggestion.

## Platform capabilities

| Domain | What exists | Decisions | Evidence |
| --- | --- | --- | --- |
| Networking | Custom VPC, private nodes, Cloud NAT, DNS-only control plane, Dataplane V2 | [Networking](decisions.md#networking) | [Phase 1](worklog/phase-01-infrastructure.md) |
| Cluster | Zonal GKE Standard, autoscaling node pool, Shielded Nodes, Regular release channel | [Cluster](decisions.md#cluster) | [Phase 1](worklog/phase-01-infrastructure.md) |
| Identity | Workload Identity Federation, dedicated node service account | [Identity and access](decisions.md#identity-and-access) | [Phase 1](worklog/phase-01-infrastructure.md) |
| Workload | `demo` namespace, NGINX Deployment, health probes, resource limits, ClusterIP Service | [Infrastructure and configuration](decisions.md#infrastructure-and-configuration) | [Phase 2](worklog/phase-02-nginx-workload.md) |
| Delivery | Credential-free pull request validation, required checks on `main` | [Delivery](decisions.md#delivery) | [Phase 3](worklog/phase-03-ci.md) |
| Policy | Pod Security baseline enforced, restricted audited, dedicated ServiceAccount | [Workload security](decisions.md#workload-security) | [Phase 4](worklog/phase-04-workload-guardrails.md) |
| Observability | Not built yet | [Deferred](decisions.md#deferred-decision-records) | Phase 8 |

## Documentation

- [Implementation plan](plan.md)
- [Architecture decisions](decisions.md)
- [Phase 1 infrastructure worklog](worklog/phase-01-infrastructure.md)
- [Phase 2 workload worklog](worklog/phase-02-nginx-workload.md)
- [Phase 3 CI worklog](worklog/phase-03-ci.md)
- [Phase 4 guardrails worklog](worklog/phase-04-workload-guardrails.md)
- [Kubernetes concepts reference](reference/kubernetes-concepts.md)
- [kubectl command reference](reference/kubectl-commands.md)
