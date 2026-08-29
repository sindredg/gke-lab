# Kubernetes Concepts Reference

This page explains how Kubernetes works, using the objects this project actually runs. It covers cluster architecture, the path a request takes through the API server, how controllers keep the cluster in its declared state, and the parts of GKE that differ from upstream Kubernetes.

Use it to understand why something behaves the way it does. For the commands themselves, see the [kubectl command reference](kubectl-commands.md).

## Cluster architecture

A cluster has two halves. The control plane decides what should be running. The nodes run it.

```text
Control plane, managed by Google
    │
    ├── kube-apiserver          the only component you talk to
    ├── etcd                    the cluster database
    ├── kube-scheduler          assigns Pods to nodes
    ├── kube-controller-manager runs the built-in controllers
    └── cloud-controller-manager integrates with Google Cloud
    │
    ▼
Nodes, Compute Engine VMs in your VPC
    │
    ├── kubelet                 starts and supervises containers
    ├── container runtime       containerd
    └── networking agent        Cilium, through GKE Dataplane V2
```

In GKE Standard, Google runs and upgrades the control plane. You do not see those components as Pods and you cannot log in to them. You own the nodes, which is why node pools, machine types, and disk sizes are yours to configure.

The API server is the only way in. `kubectl`, controllers, and the kubelet all talk to it, and nothing talks directly to etcd.

## How a request reaches the cluster

Every object you create passes through the same pipeline before it is stored.

```text
kubectl apply
    │
    ▼
API server
    │
    ├── Authentication       identifies the caller
    ├── Authorization        checks the caller is allowed to perform the action
    ├── Mutating admission   modifies the object, for example applying defaults
    ├── Schema validation    checks the object is structurally valid
    ├── Validating admission rejects objects that violate policy
    ▼
etcd
```

Two kinds of rejection look similar and mean different things:

| Message names | Stage | Meaning |
| --- | --- | --- |
| A user, group, or role | Authorization | You are not allowed to perform this action |
| A policy, such as `PodSecurity` | Admission | You are allowed to act, but this object is not acceptable |

An object rejected at admission is never stored. No image is pulled, no node is chosen, and no container starts.

Order matters when you combine controls. A LimitRange applies defaults during mutating admission, and a ResourceQuota checks totals during validating admission. Defaults are therefore in place before the quota counts them.

## Controllers and reconciliation

Kubernetes is declarative. You describe the state you want, and a controller works continuously to make the cluster match it.

Each controller runs the same loop:

1. Read the desired state from the API server.
2. Observe the actual state of the cluster.
3. Take one step to reduce the difference.
4. Repeat.

This loop is level triggered rather than edge triggered. A controller acts on the difference it observes, not on the event that caused it. Two practical consequences follow:

- Deleting a Pod that belongs to a Deployment does not reduce your replica count. The ReplicaSet controller observes a shortfall and creates a replacement. This is what self healing means.
- Reapplying an unchanged manifest is safe. The observed state already matches, so no controller has anything to do.

## Workload objects

Three objects work together to run an application.

```text
Deployment      the state you declare, and the rollout strategy
    │
    ▼
ReplicaSet      keeps N copies of one frozen Pod template
    │
    ▼
Pods            one or more containers that share a network namespace
```

A Deployment does not manage Pods directly. It manages ReplicaSets, and each ReplicaSet maintains identical copies of a single Pod template.

Change any field inside `spec.template` and the template differs, so the Deployment creates a new ReplicaSet and shifts replicas across gradually. Change a field outside the template, such as `replicas`, and no Pod is replaced.

The old ReplicaSet is kept at zero replicas, up to `revisionHistoryLimit`. Rolling back scales the previous ReplicaSet up again rather than rebuilding anything.

A Pod is the smallest unit you can schedule. Containers in the same Pod share an IP address and can reach each other on `localhost`. Pods are disposable: they are never repaired in place, only replaced.

## Labels and selectors

A label is a key and value attached to an object. Labels carry no meaning on their own. They matter because other objects select on them.

```text
Service         selector: app.kubernetes.io/name=nginx
    │
    ▼
matching Pods   labels:   app.kubernetes.io/name=nginx
```

This loose coupling is why a Service keeps working when Pods are replaced. The Service never refers to a Pod by name.

Two exceptions are worth knowing:

- `spec.selector` on a Deployment is immutable after creation, because changing it would orphan the running Pods.
- Pod Security reads specific labels on a Namespace as configuration rather than as tags. Most labels do nothing until something selects on them.

## Services and EndpointSlices

A Service gives a stable address to a changing set of Pods.

```text
Service           a stable virtual IP and DNS name
    │
    ▼
EndpointSlice     the current list of Pod IPs that match the selector
    │
    ▼
Pods
```

The EndpointSlice is maintained by a controller and updated whenever a matching Pod becomes ready or stops being ready. Reading it is the direct way to confirm that a Service found the Pods you expect.

| Type | Reachable from |
| --- | --- |
| `ClusterIP` | Inside the cluster only. The default. |
| `NodePort` | A fixed port on every node |
| `LoadBalancer` | An external load balancer provisioned by the cloud provider |
| `ExternalName` | Maps to an external DNS name, with no proxying |

In-cluster DNS resolves a Service at `<service>.<namespace>.svc.cluster.local`. Within the same namespace, the short name is enough.

Readiness matters here. A Pod that fails its readiness probe is removed from the EndpointSlice, so the Service stops sending it traffic without the Pod being restarted. A liveness probe failure restarts the container instead. Confusing the two produces either restarts that should have been removals, or traffic sent to a Pod that cannot serve it.

## Namespaces

A namespace scopes the names of most objects, so two workloads can each have a Service called `api`. Nodes, PersistentVolumes, and namespaces themselves are cluster scoped and cannot be namespaced.

A namespace is the unit that several controls attach to:

| Control | Scope |
| --- | --- |
| ResourceQuota and LimitRange | Namespace |
| Pod Security Standards | Namespace |
| RBAC Role and RoleBinding | Namespace |
| NetworkPolicy | Namespace, selecting Pods within it |

A namespace is not a network boundary. Without a NetworkPolicy, any Pod can reach any other Pod in the cluster, across namespaces.

The API server adds the `kubernetes.io/metadata.name` label to every namespace automatically. A NetworkPolicy can select namespaces only by label, so that automatic label is how you write a rule that refers to a specific namespace.

## The resource model

Every container can declare two numbers for each resource.

| Field | Enforced by | When | Purpose |
| --- | --- | --- | --- |
| `requests` | Scheduler | At placement | Reserves capacity and decides which node fits |
| `limits` | Node kernel | At runtime | Caps what the container can consume |

The scheduler sums the requests of all Pods assigned to a node and compares the total against allocatable capacity. It does not consider limits, and it does not measure current usage. A node can therefore refuse new Pods while running almost idle, because requests are a reservation system rather than a measurement.

Allocatable capacity is lower than the machine type suggests, because GKE reserves CPU and memory for the kubelet, the operating system, and system Pods.

### Units

- CPU is measured in cores. `1` is one vCPU, and the `m` suffix means millicores, so `1000m` equals one core and `50m` is five percent of a core.
- Memory is measured in bytes. `Mi` is a mebibyte, which is 1024 squared, and `M` is a megabyte, which is 1000 squared. The two are not interchangeable.

### Exceeding a limit

CPU and memory behave differently, because one can be reclaimed and the other cannot.

| | CPU | Memory |
| --- | --- | --- |
| Kernel treatment | Compressible | Incompressible |
| Over the limit | Throttled | Terminated |
| What you observe | Latency, slow responses | `OOMKilled`, restart count increases |
| Container survives | Yes | No |

A CPU limit that is too low produces a service that is mysteriously slow. A memory limit that is too low produces a crash loop.

### Quality of service

Kubernetes derives a class from the relationship between requests and limits, and uses it to decide what to evict when a node runs short of memory.

| Class | Condition | Evicted |
| --- | --- | --- |
| `Guaranteed` | Requests equal limits for every container | Last |
| `Burstable` | Requests are set and lower than limits | After BestEffort |
| `BestEffort` | Nothing declared | First |

## Admission control and Pod Security

Pod Security Admission is a validating admission plugin built into the API server. It evaluates Pods against the Pod Security Standards, which are three named profiles:

| Profile | Blocks |
| --- | --- |
| `privileged` | Nothing. The default when a namespace is unlabelled. |
| `baseline` | Known privilege escalation routes: privileged containers, host networking, host paths, dangerous capabilities |
| `restricted` | Baseline, plus running as root, privilege escalation, and undropped capabilities |

Three modes can run at once, each configured by a namespace label:

| Mode | Effect | Wording in output |
| --- | --- | --- |
| `enforce` | Rejects the Pod | `violates PodSecurity` |
| `warn` | Returns a message to the caller and creates the Pod | `would violate PodSecurity` |
| `audit` | Records an annotation in the audit log | Not shown at the terminal |

Pin the version on each mode. The profiles are tightened between Kubernetes releases, so an unpinned label lets a cluster upgrade change enforcement without any change in your repository.

Pod Security evaluates Pods at admission only. Labelling a namespace does not re-check or evict Pods that are already running. When the labels change, the API server does compare existing Pods against the new `enforce` level and warns you if any would now be refused.

## Identity and access

Kubernetes separates two kinds of identity:

| Kind | For | Stored in the cluster |
| --- | --- | --- |
| User | People and external systems | No. GKE delegates to Google IAM. |
| ServiceAccount | Workloads | Yes, as a namespaced object |

A Pod runs under a ServiceAccount, and uses the namespace `default` account unless it names another. The account a Pod runs under is fixed when the Pod is created and cannot be changed afterwards.

By default, Kubernetes mounts a short-lived token for that account into the container at `/var/run/secrets/kubernetes.io/serviceaccount`. Any process in the container can read it and call the API server. Set `automountServiceAccountToken: false` when a workload does not call the Kubernetes API, so the credential is never present.

What an account can do is decided by RBAC:

```text
Role            a set of permissions, within one namespace
ClusterRole     a set of permissions, cluster wide
    │
    ▼
RoleBinding or ClusterRoleBinding
    │
    ▼
ServiceAccount, user, or group
```

Permissions are additive only. RBAC has no deny rule, so an identity holds the union of everything bound to it.

## Network policy

A NetworkPolicy selects Pods and describes the traffic they are allowed to send and receive.

Three rules explain most of the confusing behaviour:

1. **Pods are unrestricted until a policy selects them.** With no policy, all traffic is allowed.
2. **Selecting a Pod switches it to deny by default,** for the directions the policy names. A policy with `policyTypes: [Ingress, Egress]` and no rules denies everything in both directions.
3. **Policies are additive and allow only.** There is no deny rule. When several policies select the same Pod, the Pod is allowed the union of what they permit.

A default-deny policy therefore takes effect the moment it is created, and you re-open specific paths by adding further policies rather than by editing it.

Egress policies commonly break DNS. Name resolution is network traffic to the cluster DNS service, so a default-deny egress policy blocks it, and the failure appears as an application that cannot resolve any hostname. Allow UDP and TCP port 53 to the DNS Pods in `kube-system` alongside any other egress rule.

## What GKE changes

| Area | Upstream Kubernetes | GKE Standard, as configured here |
| --- | --- | --- |
| Control plane | You run and upgrade it | Google runs it. You choose a release channel. |
| Nodes | You provide them | Node pools of Compute Engine VMs, with autoscaling, auto-repair, and auto-upgrade |
| Pod networking | Choose a CNI plugin | Dataplane V2, which is Cilium using eBPF, and which also enforces NetworkPolicy |
| kube-proxy | Runs on every node | Replaced by eBPF programs under Dataplane V2 |
| Pod IP addresses | Often an overlay network | VPC-native, so Pod IPs come from a secondary range on the subnet and are routable in the VPC |
| API server address | An IP endpoint you expose | A DNS-based endpoint, with IP endpoints disabled and access controlled by IAM |
| Workload cloud identity | Service account keys | Workload Identity Federation, which exchanges a Kubernetes ServiceAccount token for short-lived Google Cloud credentials |

Because Pod IPs are routable in the VPC under a VPC-native cluster, address ranges must be planned so they do not overlap with other networks you intend to reach.

## Further reading

- [Kubernetes concepts](https://kubernetes.io/docs/concepts/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Resource management for Pods and containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [GKE cluster architecture](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture)
- [GKE Dataplane V2](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2)
