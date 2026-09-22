# Secure Kubernetes Platform on GKE

A private GKE cluster, a couple of workloads, and an AI agent that handles the security findings nobody wants to read.

Terraform builds it. GitHub Actions ships to it, keylessly. Each phase has a worklog, and [decisions.md](decisions.md) covers the why.

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

Milestones 1 to 3 are complete, and Milestone 4 is under way: agents that operate the platform. Open gaps are listed next to what works.

| Area | State |
| --- | --- |
| Foundation | Private GKE on modular Terraform, custom VPC, Cloud NAT, DNS-only control plane |
| Workloads | Two behind one Gateway: `nginx` at two replicas, `sky` autoscaled from two to eight |
| Guardrails | Pod Security `restricted`, namespace budget, default-deny NetworkPolicies |
| Delivery | Keyless federation scoped to `main`, gated rollout, required checks, upstream CI checked before a pin moves |
| Ingress | Public Gateway on a custom domain, managed TLS, HTTP to HTTPS redirect |
| Resilience | Node floor of two, a disruption budget per workload, nightly maintenance window |
| Observability | Uptime check, one actionable alert, dashboard as code |
| Proven | Both failure drills run and recorded |
| Hardened | One network, vulnerability scanning on, logs queryable, TLS 1.2 floor, rate limit, response security headers |
| Under load | Rollouts drop no requests, sky autoscales to 125 rps with no failures, nodes scale across three zones |
| Modelled | Eight trust boundaries with [a threat model](reference/threat-model.md), measured rather than assumed, and scanned daily from outside |
| Streaming | Security Command Center findings reach a subscription in about two seconds, and park in a dead letter topic when nothing acknowledges them |
| Triaged | An agent in its own namespace settles findings against a corpus compiled into its image, holding four scoped grants and no cluster credential |
| Drilled | The worker is stopped at each of the three crash boundaries and recovers at each, notifying again rather than silently skipping |

Milestone 3 closed with eleven of the twelve findings in [the threat model](reference/threat-model.md) measured and closed across [Phase 13](worklog/phase-13-security-baseline.md) and [Phase 14](worklog/phase-14-close-the-baseline.md), the twelfth carrying a recorded acceptance.

[Phase 15](worklog/phase-15-scc-triage.md) is closed. The worker in [ai-k8s](https://github.com/sindredg/ai-k8s) settles what the reviewed mapping pairs, and asks Vertex AI about the rest through a one-permission role, within a token budget and a daily spend ceiling. Every failure path it adds was made to happen.

Whether the model is worth it is measured in [slices 13 and 14](worklog/phase-15-scc-triage.md#slice-13-decision-quality-rules-alone-against-rules-plus-the-model), on a reviewed set of 25 findings asked five times each. At first the model tied the rules alone, trading false contradictions for real ones. With a contradiction required to land on a control that applies to the finding's resource, it gets 16 of 18 dev cases and 7 of 7 sealed holdout cases right on every run, against 14 and 5 for the rules, with no false contradiction in 125 runs.

[Phase 15b](plan.md#phase-15b-patch-the-images-this-repository-builds) patched the images whose vulnerabilities triage counts: `frontend` from 17 CRITICAL and HIGH to 0, and `sky` from 22 to 6, none of which has a fixed package yet.

Next: [Phase 16](plan.md#phase-16-cluster-access-through-an-audited-gateway), cluster reads through an audited gateway, starting with a threat model pass.

## Measured

| | |
| --- | --- |
| Merge to Ready workload | 59s |
| Deploy duration, median of twelve runs | 70.5s |
| Alert detection floor | about 3 minutes |
| Running cost | kr461.81 a week, covered by credits |
| sky saturation, two replicas | 40 requests a second, p95 230ms |
| Requests failed during a rollout at 20 rps | 1.14%, error window up to 20.4s |
| Connection failures in a rollout, after `preStop` | 0 across three rollouts, from 72 |
| Closed-connection 503s in a ramp, after keep-alive | 0 of 7,150, from 6 |
| sky saturation, autoscaled to eight replicas | 125 requests a second, p95 394ms, no failures |
| HPA decision to a Pod running on a new node | 97s |
| Security Command Center finding change to a message on the subscription | about 2 seconds |
| Unacknowledged message to the dead letter topic | 5 delivery attempts |
| Outstanding message returned after the worker is killed | about 25 seconds, on stream close rather than on the 120s deadline |
| Crash to a recorded verdict on redelivery | four ledger states in 285ms |

Method and evidence: [Phase 8](worklog/phase-08-observability.md), [Phase 10](worklog/phase-10-failure-drills.md), [Phase 12a](worklog/phase-12a-load-baseline.md), [Phase 12b](worklog/phase-12b-rollout-baseline.md), [Phase 12c](worklog/phase-12c-rollouts-connections.md) and [Phase 12d](worklog/phase-12d-autoscaling.md).

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
| Deployment | Keyless GitHub Actions delivery for both workloads, federation scoped to `main`, namespaced pipeline RBAC, gated rollout | [Delivery](decisions.md#delivery) | [Phase 6](worklog/phase-06-keyless-delivery.md) |
| Upstream tracking | Scheduled workflow that proposes the sky commit bump as a pull request, with the merge as the review | [Upstream pin automation](decisions.md#upstream-pin-automation) | [Pin automation](worklog/notes/upstream-pin-automation.md) |
| Ingress | GKE Gateway on a reserved global address, container-native load balancing, Certificate Manager TLS, HTTP to HTTPS redirect, path routing to both workloads | [Ingress and TLS](decisions.md#ingress-and-tls) | [Phase 7](worklog/phase-07-gateway-tls.md) |
| Observability | Cluster telemetry, uptime check on `/healthz`, one alert policy, dashboard as code, deployment and cost numbers | [Observability](decisions.md#observability) | [Phase 8](worklog/phase-08-observability.md) |
| Resilience | Node floor of two, disruption budgets on both workloads, spread that survives a rollout, nightly maintenance window | [Cluster](decisions.md#cluster) | [Phase 9](worklog/phase-09-resilience.md) |
| Failure drills | Deliberate outage with a measured three minute detection floor, and a failed rollout contained by `maxUnavailable: 0` | [Observability](decisions.md#observability) | [Phase 10](worklog/phase-10-failure-drills.md) |
| Hardening | Only `gke-vpc` remains, workload vulnerability scanning on, Log Analytics and one log-based metric | [Workload security](decisions.md#workload-security) | [Phase 11](worklog/phase-11-hardening.md) |
| Load and autoscaling | k6 harness on a throwaway load generator, `preStop` and keep-alive for clean rollouts, HPA on sky with requests and quota sized from measured load, nodes across three zones | [Load and scaling](decisions.md#load-and-scaling) | [Phase 12a](worklog/phase-12a-load-baseline.md), [12b](worklog/phase-12b-rollout-baseline.md), [12c](worklog/phase-12c-rollouts-connections.md), [12d](worklog/phase-12d-autoscaling.md) |
| Security baseline | Twelve ranked threat model findings, eleven closed with evidence, federation scoped to a ref, CSP on both paths, CAA on a signed zone, a measured rate limit | [Workload security](decisions.md#workload-security) | [Phase 13](worklog/phase-13-security-baseline.md), [Phase 14](worklog/phase-14-close-the-baseline.md) |
| Finding triage | Security Command Center findings over Pub/Sub with a dead letter policy, a worker that settles them by reviewed mapping and then by model, an append-only verdict ledger, and a scored evaluation of both | [Agents](decisions.md#agents) | [Phase 15](worklog/phase-15-scc-triage.md) |

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
- [Phase 12a load baseline worklog](worklog/phase-12a-load-baseline.md)
- [Phase 12b rollout baseline worklog](worklog/phase-12b-rollout-baseline.md)
- [Phase 12c rollouts and connections worklog](worklog/phase-12c-rollouts-connections.md)
- [Phase 12d autoscaling worklog](worklog/phase-12d-autoscaling.md)
- [Phase 13 security baseline worklog](worklog/phase-13-security-baseline.md)
- [Phase 14 close the baseline worklog](worklog/phase-14-close-the-baseline.md)
- [Phase 15 Security Command Center triage worklog](worklog/phase-15-scc-triage.md)
- [Upstream pin automation worklog](worklog/notes/upstream-pin-automation.md)
- [Manifest linting worklog](worklog/notes/manifest-linting.md)
- [Repository review worklog](worklog/notes/repository-review.md)
- [Availability drill postmortem](worklog/notes/postmortem-availability-drill.md)
- [Load test harness](loadtest/README.md)
- [Troubleshooting log](troubleshooting.md)
- [Networking reference](reference/networking.md)
- [Kubernetes concepts reference](reference/kubernetes-concepts.md)
- [kubectl command reference](reference/kubectl-commands.md)
- [IAM and Workload Identity Federation reference](reference/iam-and-federation.md)
- [Triage worker reference](reference/triage-worker.md)
