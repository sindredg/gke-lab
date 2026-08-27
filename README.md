# GKE Platform

```mermaid
flowchart TB
    Developer["Developer"]
    Terraform["Terraform"]
    Internet(("Internet"))

    subgraph Project["Google Cloud project"]
        APIs["Google Cloud APIs"]
        DNS["IAM protected DNS endpoint"]
        ControlPlane["GKE Standard control plane<br/>Regular release channel<br/>europe-north1-a"]
        WorkloadIdentity["Workload Identity Federation"]
        NodeIdentity["Dedicated node service account"]

        subgraph VPC["Custom VPC: gke-vpc"]
            subgraph Subnet["Subnet: gke-subnet<br/>Nodes: 10.10.0.0/20"]
                NodePool["Private node pool<br/>1 to 3 e2-standard-2 nodes<br/>Shielded VMs"]
                Dataplane["GKE Dataplane V2"]
                Pods["Pods<br/>10.20.0.0/16"]
                Services["GKE managed Service range"]

                NodePool --> Dataplane
                Dataplane --> Pods
                Services --> Pods
            end

            PrivateAccess["Private Google Access"]
            Router["Cloud Router"]
            NAT["Cloud NAT"]

            NodePool --> PrivateAccess
            NodePool --> Router
            Pods --> Router
            Router --> NAT
        end
    end

    Developer --> DNS
    DNS --> ControlPlane
    Terraform --> APIs
    ControlPlane --> NodePool
    NodeIdentity --> NodePool
    Pods --> WorkloadIdentity
    WorkloadIdentity --> APIs
    PrivateAccess --> APIs
    NAT --> Internet

    classDef user fill:#e8f0fe,stroke:#1a73e8,color:#174ea6,stroke-width:2px
    classDef control fill:#f3e8fd,stroke:#9334e6,color:#681da8,stroke-width:2px
    classDef network fill:#e6f4ea,stroke:#34a853,color:#137333,stroke-width:2px
    classDef security fill:#fef7e0,stroke:#f9ab00,color:#b06000,stroke-width:2px
    classDef external fill:#fce8e6,stroke:#ea4335,color:#a50e0e,stroke-width:2px

    class Developer,Terraform user
    class DNS,ControlPlane control
    class NodePool,Dataplane,Pods,Services,Router,NAT network
    class WorkloadIdentity,NodeIdentity,PrivateAccess security
    class Internet external
```

- Terraform enables seven required Google Cloud APIs.
- A custom VPC provides explicit node and Pod address ranges.
- Private nodes use Cloud NAT for outbound internet access.
- The GKE control plane is reachable only through its IAM protected DNS endpoint.
- Dataplane V2, Workload Identity Federation, Shielded Nodes, auto-repair, and auto-upgrade are enabled.
- The general node pool scales from one to three `e2-standard-2` nodes.
- Next: deploy Kubernetes workloads, namespaces, policies, and resource controls.
- Next: decide Artifact Registry, Gateway or Ingress, DNS, and TLS.
- Next: define observability, backup, and recovery requirements.
- Later: add remote state and CI/CD when collaboration or automation requires them.
- Before production: decide whether to use a regional cluster.
- See [decisions.md](decisions.md) for decisions and alternatives.
