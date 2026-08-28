# Secure GKE Workload Platform

```mermaid
flowchart TB
    User(["User"])
    Developer["Developer"]

    subgraph Delivery["Infrastructure and delivery"]
        Terraform["Terraform"]
        GitHub["GitHub Actions<br/>CI now, CD planned"]
    end

    subgraph GCP["Google Cloud"]
        DNS["Cloud DNS"]
        Gateway["HTTPS load balancer<br/>GKE Gateway API"]
        Registry["Artifact Registry"]
        PubSub["Pub/Sub"]
        Vertex["Vertex AI Gemini<br/>Flash-Lite"]
        Results["Short-lived review results<br/>Firestore or Cloud Storage"]
        Observability["Cloud Logging<br/>Cloud Monitoring"]
        Identity["Workload Identity Federation"]
        APIs["Google Cloud APIs"]

        subgraph VPC["Custom VPC"]
            ControlPlane["GKE Standard control plane<br/>DNS-only endpoint"]
            NAT["Cloud NAT"]

            subgraph Cluster["Private GKE node pool, 1 to 3 nodes"]
                Routes["Gateway and HTTPRoutes"]
                Frontend["NGINX reference workload<br/>Current"]
                API["Manifest review API<br/>Later milestone"]
                Worker["Review worker<br/>Later milestone"]
                Checks["Deterministic checks<br/>Later milestone"]
                Guardrails["Pod Security<br/>NetworkPolicy<br/>Quotas and limits"]

                Routes --> Frontend
                Frontend --> API
                Worker --> Checks
                Guardrails -. protects .-> Frontend
                Guardrails -. protects .-> API
                Guardrails -. protects .-> Worker
            end
        end
    end

    User --> DNS
    DNS --> Gateway
    Gateway --> Routes
    API --> PubSub
    PubSub --> Worker
    API -. keyless identity .-> Identity
    Worker -. keyless identity .-> Identity
    Identity --> PubSub
    Identity --> Vertex
    Identity --> Results

    Developer --> Terraform
    Developer --> GitHub
    Terraform --> APIs
    GitHub -. builds .-> Registry
    GitHub -. deploys .-> ControlPlane
    Registry -. images .-> Frontend
    Registry -. images .-> API
    Registry -. images .-> Worker

    ControlPlane --> Cluster
    Cluster --> NAT
    Frontend -. telemetry .-> Observability
    API -. telemetry .-> Observability
    Worker -. telemetry .-> Observability

    classDef external fill:#4B201D,stroke:#F28B82,color:#F8FAFC,stroke-width:2px
    classDef current fill:#123C2D,stroke:#81C995,color:#F8FAFC,stroke-width:2px
    classDef planned fill:#183B5B,stroke:#8AB4F8,color:#F8FAFC,stroke-width:2px
    classDef managed fill:#402060,stroke:#C58AF9,color:#F8FAFC,stroke-width:2px
    classDef delivery fill:#493510,stroke:#FDD663,color:#F8FAFC,stroke-width:2px

    class User external
    class Developer,Terraform,GitHub delivery
    class ControlPlane,NAT,Frontend current
    class Routes,API,Worker,Checks,Guardrails planned
    class DNS,Gateway,Registry,PubSub,Vertex,Results,Observability,Identity,APIs managed

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
- Next: guard the existing workload with Pod Security Admission, NetworkPolicy, and resource limits.
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
| Policy | Not built yet | [Deferred](decisions.md#deferred-decision-records) | Phase 4 |
| Observability | Not built yet | [Deferred](decisions.md#deferred-decision-records) | Phase 8 |

## Documentation

- [Implementation plan](plan.md)
- [Architecture decisions](decisions.md)
- [Phase 1 infrastructure worklog](worklog/phase-01-infrastructure.md)
- [Phase 2 workload worklog](worklog/phase-02-nginx-workload.md)
- [Phase 3 CI worklog](worklog/phase-03-ci.md)
- [kubectl command reference](reference/kubectl-commands.md)
