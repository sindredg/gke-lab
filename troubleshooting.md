# Troubleshooting Log

Faults that took real work to find, and what the diagnosis actually depended on. Each entry records the symptom, the evidence, the wrong answers that were eliminated, and the fix.

## Method

Three rules produced every diagnosis below.

**Record a working baseline before changing anything.** A failure only means something when the same command succeeded a moment earlier. Without that, a timeout could be the new policy, a wrong Service name, or a broken test image, and there is no way to tell which.

**Read the exact error.** `curl: (6) Could not resolve host` and `curl: (28) Connection timed out` are one keystroke apart on screen and point at different layers. Treating both as "it is broken" discards the most useful thing on the terminal.

**Split the request into its hops and test each one.** Name resolution and connection are independent. So are the Service address and the Pod address. Narrowing to a single hop turns a symptom into a cause.

## DNS stopped resolving after the default deny

Phase 4, Slice 3.

### Symptom

Applying `default-deny` to the `demo` namespace removed cluster DNS for every Pod in it. The `allow-dns` policy written alongside it did not restore DNS, and neither did a second version of that policy.

```bash
curl http://nginx
curl http://cloud.google.com
nslookup nginx
```

![Every name lookup timing out](images/netpol-dns-failure.png)

### What the error established

```text
curl: (6) Could not resolve host: nginx (Timeout while contacting DNS servers)
```

`Timeout`, not `no such host`. The query was sent and nothing came back, which is what a dropped packet looks like. A denial in this dataplane discards traffic silently rather than rejecting it, so there is no error to read at the point of the block. Both the cluster name and the external name failed identically, which placed the fault on the first hop they share rather than on either destination.

### Eliminated

| Candidate | Evidence against it |
| --- | --- |
| The `nginx-client` label was wrong | `kubectl get pod client --show-labels` showed `nginx-client=true` applied |
| The Pod needed restarting to pick up the policy | Policy is evaluated continuously against current labels; a restart returns the same Pod with the same labels |
| The policy file was mistranscribed | `kubectl get netpol allow-dns -o yaml` showed the intended rule stored on the API server |
| The kube-system namespace lacked its name label | `kubernetes.io/metadata.name=kube-system` was present |
| NodeLocal DNSCache uses a link-local resolver | `resolv.conf` named `34.118.224.10`, an ordinary Service address |

### The first fix, which did not work

`resolv.conf` pointed at the kube-dns Service address, so the next attempt allowed that address directly with an `ipBlock` rule.

```bash
kubectl get svc kube-dns -n kube-system
```

![The kube-dns Service address](images/netpol-kube-dns-service.png)

![DNS still failing after the ipBlock rule](images/netpol-dns-still-failing.png)

It changed nothing. A NetworkPolicy cannot name a Service address: the dataplane rewrites a Service IP to a backend Pod before policy is evaluated, so a rule matching that address never sees any traffic. NetworkPolicy selects Pods, never Services.

### The fact that broke it open

Listing the DNS components showed a third Pod that no rule mentioned.

```bash
kubectl get pods -n kube-system --show-labels | grep dns
```

![NodeLocal DNSCache running alongside kube-dns](images/netpol-dns-providers.png)

Querying each resolver separately isolated the fault to one of them. `dig @server` bypasses `resolv.conf` and asks a named server directly, which is what makes this test possible.

```bash
dig +short @34.118.224.10 nginx.demo.svc.cluster.local
dig +short @10.20.1.12 nginx.demo.svc.cluster.local
```

![The Service address failing while the kube-dns Pod answers](images/netpol-dns-bisect.png)

The kube-dns Pod answered. The Service address did not. So the `allow-dns` rule was correct for the Pod it named, and something else was receiving the query.

The working assumption at this point was that NodeLocal DNSCache runs in the host network namespace, where no Pod selector could reach it. One command disproved that.

```bash
kubectl get nodes -o wide
```

![The node internal address](images/netpol-node-ip.png)

The node's address is `10.10.0.7`. NodeLocal DNSCache holds `10.20.1.2`, inside the Pod range, so it is an ordinary Pod with an ordinary Pod address. Confirming it was blocked took one more query.

```bash
dig +short @10.20.1.2 nginx.demo.svc.cluster.local
```

![The NodeLocal DNSCache Pod refusing the query](images/netpol-nodelocal-blocked.png)

### Root cause

NodeLocal DNSCache answers on the kube-dns Service address but runs as its own Pod, labelled `k8s-app: node-local-dns`. The rule allowed `k8s-app: kube-dns` only, so it permitted a Pod that never received the query and denied the one that did. The rule was well formed and pointed at the wrong Pod.

### Resolution

Allow both resolvers. `matchExpressions` expresses the alternative that `matchLabels` cannot.

```yaml
podSelector:
  matchExpressions:
    - key: k8s-app
      operator: In
      values:
        - kube-dns
        - node-local-dns
```

![Application traffic allowed and internet egress denied](images/netpol-result.png)

Name resolution returned, the labelled client reached NGINX, and egress to the internet stayed denied. The failure mode also changed from `(6) Could not resolve host` to `(28) Connection timed out`, which confirms the block moved one layer further along.

### Cost of the wrong assumption

Believing the cache was host-networked led to a recommendation to disable NodeLocal DNSCache in Terraform, which recreates every node. The node address had been one command away throughout. The rule that would have caught it sooner: check the cheap fact before building on the plausible mechanism.

### What to check first next time

1. Read the error. Resolution failure and connection failure are different faults.
2. `kubectl get netpol -n NAMESPACE -o yaml`, because what the API server stored is the only version that matters.
3. `cat /etc/resolv.conf` inside the Pod, to learn which resolver is actually configured.
4. `kubectl get pods -n kube-system --show-labels | grep dns`, because more than one component may answer.
5. `dig @server` against each candidate resolver in turn.

Dataplane V2 policy logging would have answered this directly by naming the denied connection. It is not enabled on this cluster and is recorded as a gap in the Phase 4 worklog.

## Shorter notes

**A Pod restart does not reload network policy.** Policy is recomputed continuously from current labels, so a restarted Pod returns with the same labels and the same verdict. Changing a label, a policy, or a Service selector takes effect on the running Pod within about a second. Only a change to the Pod template produces a new Pod.

**`kubectl port-forward` cannot validate network policy.** It tunnels through the API server to the kubelet and enters the Pod on loopback, so it never crosses the dataplane. A fully isolated Pod still answers on a forwarded port.

**`POD-SELECTOR` showing `<none>`.** In `kubectl get netpol` output this means the policy has no selector terms, which selects every Pod in the namespace. It reads like the opposite of what it means.
