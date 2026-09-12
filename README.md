# Secure GKE Workload Platform

A secure, publicly reachable Kubernetes platform on Google Cloud, built and documented one phase at a time, for those who want to see how a private cluster, keyless delivery, workload guardrails and managed TLS fit together in practice.

## Live

[sindrg.com](https://sindrg.com)

## Architecture

```mermaid
flowchart TB
    User(["User"])
    Developer(["Developer"])
    DNS["Cloudflare DNS<br/>sindrg.com"]

    subgraph Delivery["Infrastructure and delivery"]
        Terraform["Terraform"]
        GitHub["GitHub Actions"]
    end

    subgraph GCP["Google Cloud"]
        Ingress["Global external<br/>Application Load Balancer<br/>reserved address"]
        Certs["Certificate Manager<br/>managed TLS"]
        Registry["Artifact Registry"]
        Identity["Workload<br/>Identity<br/>Federation"]
        Uptime["Uptime check<br/>three prober regions"]
        Observability["Cloud Logging<br/>Cloud Monitoring<br/>dashboard and alert policy"]
        Notify["Email notification<br/>channel"]

        subgraph VPC["Custom VPC"]
            ControlPlane["GKE control plane<br/>DNS-only endpoint"]

            subgraph Cluster["GKE node pool, floor of two nodes"]
                Routes["Gateway and<br/>HTTPRoutes"]
                Nginx["nginx<br/>two replicas<br/>serves /"]
                Sky["sky<br/>two replicas<br/>serves /sky, /api, /static"]
                Guardrails["Pod Security, NetworkPolicy,<br/>quotas, disruption budgets"]
            end

            NAT["Cloud NAT"]
        end
    end

    User --> DNS
    DNS --> Ingress
    Certs -. terminates TLS .-> Ingress
    Certs -. validated by a DNS record .-> DNS
    Ingress -- "Pod IPs via NEG" --> Nginx
    Ingress -- "Pod IPs via NEG" --> Sky
    Routes -. configures .-> Ingress
    Guardrails -. protects .-> Nginx
    Guardrails -. protects .-> Sky
    Developer --> Terraform
    Developer --> GitHub
    Terraform --> ControlPlane
    GitHub -. federates .-> Identity
    GitHub -. builds and pushes .-> Registry
    GitHub -. deploys .-> ControlPlane
    Registry -. images pulled by nodes .-> Cluster
    ControlPlane --> Cluster
    Cluster -- "node egress" --> NAT
    Cluster -. telemetry .-> Observability
    Uptime -- "probes /healthz every 60s" --> Ingress
    Uptime -. the result is the metric .-> Observability
    Observability -. opens an incident .-> Notify

    classDef external fill:#4B201D,stroke:#F28B82,color:#F8FAFC,stroke-width:2px
    classDef delivery fill:#493510,stroke:#FDD663,color:#F8FAFC,stroke-width:2px
    classDef workload fill:#123C2D,stroke:#81C995,color:#F8FAFC,stroke-width:2px
    classDef managed fill:#402060,stroke:#C58AF9,color:#F8FAFC,stroke-width:2px

    class User,Developer external
    class Terraform,GitHub delivery
    class ControlPlane,NAT,Routes,Nginx,Sky,Guardrails workload
    class Ingress,Registry,Identity,Uptime,Observability,Notify managed

    style Delivery fill:#211A0D,stroke:#FDD663,color:#F8FAFC,stroke-width:2px
    style GCP fill:#101828,stroke:#8AB4F8,color:#F8FAFC,stroke-width:2px
    style VPC fill:#102A23,stroke:#81C995,color:#F8FAFC,stroke-width:2px
    style Cluster fill:#183B31,stroke:#A8DAB5,color:#F8FAFC,stroke-width:2px
```

## Status

Milestone 1 is complete. Every platform claim has recorded commands, results and evidence.

| Area | State |
| --- | --- |
| Foundation | Private GKE on modular Terraform, custom VPC, Cloud NAT, DNS-only control plane |
| Workloads | Two, `nginx` and `sky`, two replicas each, behind one Gateway |
| Guardrails | Pod Security `restricted`, namespace budget, default-deny NetworkPolicies |
| Delivery | Keyless, repository-scoped federation, gated rollout, required checks on `main` |
| Ingress | Public Gateway on a custom domain, managed TLS, HTTP to HTTPS redirect |
| Resilience | Node floor of two, a disruption budget per workload, nightly maintenance window |
| Observability | Uptime check, one actionable alert, dashboard as code |
| Proven | Both failure drills run and recorded |
| Hardened | One network, vulnerability scanning on, logs queryable |

Next: Milestone 2, the deterministic manifest reviewer, which is the first workload this platform exists to carry.

## Measured

| | |
| --- | --- |
| Merge to Ready workload | 59s |
| Deploy duration, median of twelve runs | 70.5s |
| Alert detection floor | about 3 minutes |
| Running cost | kr461.81 a week, covered by credits |

Method and evidence: [Phase 8](worklog/phase-08-observability.md) and [Phase 10](worklog/phase-10-failure-drills.md).

## Platform capabilities

| Domain | What exists | Decisions | Evidence |
| --- | --- | --- | --- |
| Networking | Custom VPC, private nodes, Cloud NAT, DNS-only control plane, Dataplane V2 | [Networking](decisions.md#networking) | [Phase 1](worklog/phase-01-infrastructure.md) |
| Cluster | Zonal GKE Standard, autoscaling node pool, Shielded Nodes, Regular release channel | [Cluster](decisions.md#cluster) | [Phase 1](worklog/phase-01-infrastructure.md) |
| Identity | Workload Identity Federation, dedicated node service account | [Identity and access](decisions.md#identity-and-access) | [Phase 1](worklog/phase-01-infrastructure.md) |
| Workload | `demo` namespace, two Deployments (`nginx` and `sky`), health probes, resource limits, ClusterIP Services | [Infrastructure and configuration](decisions.md#infrastructure-and-configuration) | [Phase 2](worklog/phase-02-nginx-workload.md) |
| Delivery | Credential-free pull request validation, required checks on `main` | [Delivery](decisions.md#delivery) | [Phase 3](worklog/phase-03-ci.md) |
| Policy | Pod Security `restricted` enforced, dedicated ServiceAccount, namespace budget, default-deny NetworkPolicies | [Workload security](decisions.md#workload-security) | [Phase 4](worklog/phase-04-workload-guardrails.md), [Phase 5](worklog/phase-05-custom-image.md) |
| Images | Private Artifact Registry repository, immutable tags, retention policy, node read access | [Images and supply chain](decisions.md#images-and-supply-chain) | [Phase 5](worklog/phase-05-custom-image.md) |
| Deployment | Keyless GitHub Actions delivery for both workloads, repository-scoped federation, namespaced pipeline RBAC, gated rollout | [Delivery](decisions.md#delivery) | [Phase 6](worklog/phase-06-keyless-delivery.md) |
| Ingress | GKE Gateway on a reserved global address, container-native load balancing, Certificate Manager TLS, HTTP to HTTPS redirect, path routing to both workloads | [Ingress and TLS](decisions.md#ingress-and-tls) | [Phase 7](worklog/phase-07-gateway-tls.md) |
| Observability | Cluster telemetry, uptime check on `/healthz`, one alert policy, dashboard as code, deployment and cost numbers | [Observability](decisions.md#observability) | [Phase 8](worklog/phase-08-observability.md) |
| Resilience | Node floor of two, disruption budgets on both workloads, spread that survives a rollout, nightly maintenance window | [Cluster](decisions.md#cluster) | [Phase 9](worklog/phase-09-resilience.md) |
| Failure drills | Deliberate outage with a measured three minute detection floor, and a failed rollout contained by `maxUnavailable: 0` | [Observability](decisions.md#observability) | [Phase 10](worklog/phase-10-failure-drills.md) |
| Hardening | Only `gke-vpc` remains, workload vulnerability scanning on, Log Analytics and one log-based metric | [Workload security](decisions.md#workload-security) | [Phase 11](worklog/phase-11-hardening.md) |

## Documentation

- [Implementation plan](plan.md)
- [Architecture decisions](decisions.md)
- [Phase 1 infrastructure worklog](worklog/phase-01-infrastructure.md)
- [Phase 2 workload worklog](worklog/phase-02-nginx-workload.md)
- [Phase 3 CI worklog](worklog/phase-03-ci.md)
- [Phase 4 guardrails worklog](worklog/phase-04-workload-guardrails.md)
- [Phase 5 custom image worklog](worklog/phase-05-custom-image.md)
- [Phase 6 keyless delivery worklog](worklog/phase-06-keyless-delivery.md)
- [Phase 7 gateway and TLS worklog](worklog/phase-07-gateway-tls.md)
- [Phase 8 observability worklog](worklog/phase-08-observability.md)
- [Phase 9 surviving a node worklog](worklog/phase-09-resilience.md)
- [Phase 10 failure drills worklog](worklog/phase-10-failure-drills.md)
- [Phase 11 hardening worklog](worklog/phase-11-hardening.md)
- [Availability drill postmortem](worklog/postmortem-availability-drill.md)
- [Troubleshooting log](troubleshooting.md)
- [Networking reference](reference/networking.md)
- [Kubernetes concepts reference](reference/kubernetes-concepts.md)
- [kubectl command reference](reference/kubectl-commands.md)
- [IAM and Workload Identity Federation reference](reference/iam-and-federation.md)
