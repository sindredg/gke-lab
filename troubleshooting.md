# Troubleshooting log

Faults that took real work to find. Each entry states the issue, the cause, and the fix, then records the investigation that connected them.

## Where a request breaks

```text
Pod sends a request
    │
    ▼
1  Name resolution        egress to the DNS Pods        allow-dns
    │                     curl (6) Could not resolve host
    ▼
2  Sender egress          the client's own rules        default-deny
    │                                                   nginx-client-allow-egress
    │                     curl (28) Failed to connect
    ▼
3  Service translation    ClusterIP rewritten to a backend Pod
    │                     no error of its own, but policy is evaluated after this
    ▼
4  Receiver ingress       the target Pod's rules        nginx-allow-http
    │                     curl (28) Failed to connect
    ▼
5  Application            the server answers            any HTTP status
```

Read the failure against this map before changing anything.

Step 1 fails differently from every other step, so `(6)` against `(28)` immediately halves the search. Steps 2 and 4 produce identical errors, because the dataplane checks the sender and the receiver separately and drops the packet either way. To separate them, send the same request from a Pod that is allowed to send: if it succeeds, the receiver admits the traffic and the original client's egress is what denies it.

Step 3 explains why a policy cannot name a Service address. By the time a rule is evaluated, the ClusterIP is already rewritten to a backend Pod.

Step 5 returns an HTTP status. Any status at all, including `301` or `404`, means all five steps succeeded and the network is not at fault.

## How to diagnose a fault in this project

Three rules produced every diagnosis below.

**Record a working baseline before changing anything.** A failure means something only when the same command succeeded a moment earlier. Without that, a timeout could be the new policy, a wrong Service name, or a broken test image, and nothing distinguishes them.

**Read the exact error.** `curl: (6) Could not resolve host` and `curl: (28) Failed to connect` sit one keystroke apart on screen and point at different layers. Treating both as "it is broken" discards the most useful text on the terminal.

**Split the request into hops and test each one.** Name resolution and connection are independent, and so are the Service address and the Pod address. Narrowing to a single hop turns a symptom into a cause.

## DNS stops resolving after the default deny

Phase 4, Slice 3.

**Issue:** Applying `default-deny` to the `demo` namespace removes cluster DNS for every Pod in it. The `allow-dns` policy written alongside it does not restore DNS, and neither does a second version of that policy.

**Cause:** NodeLocal DNSCache answers on the kube-dns Service address but runs as its own Pod, labelled `k8s-app: node-local-dns`. The rule allows `k8s-app: kube-dns` only, so it permits a Pod that never receives the query and denies the one that does.

**Fix:** Allow both resolvers in a single rule with `matchExpressions`.

```yaml
podSelector:
  matchExpressions:
    - key: k8s-app
      operator: In
      values:
        - kube-dns
        - node-local-dns
```

### Symptom

```bash
curl http://nginx
curl http://cloud.google.com
nslookup nginx
```

![Every name lookup timing out](images/netpol-dns-failure.png)

### Investigation

#### What the error establishes

```text
curl: (6) Could not resolve host: nginx (Timeout while contacting DNS servers)
```

The query times out rather than returning `no such host`. The request left the Pod and nothing came back, which is what a dropped packet looks like. This dataplane discards denied traffic silently instead of rejecting it, so no error appears at the point of the block.

Both the cluster name and the external name fail identically. That places the fault on the hop they share rather than on either destination.

#### Candidates eliminated

| Candidate | Evidence against it |
| --- | --- |
| The `nginx-client` label is wrong | `kubectl get pod client --show-labels` shows `nginx-client=true` applied |
| The Pod needs a restart to pick up the policy | Policy is evaluated continuously against current labels, so a restart returns the same Pod with the same verdict |
| The policy file is mistranscribed | `kubectl get netpol allow-dns -o yaml` shows the intended rule stored on the API server |
| The kube-system namespace lacks its name label | `kubernetes.io/metadata.name=kube-system` is present |
| NodeLocal DNSCache uses a link-local resolver | `resolv.conf` names `34.118.224.10`, an ordinary Service address |

#### The first fix, which does not work

`resolv.conf` points at the kube-dns Service address, so the next attempt allows that address directly with an `ipBlock` rule.

```bash
kubectl get svc kube-dns -n kube-system
```

![The kube-dns Service address](images/netpol-kube-dns-service.png)

![DNS still failing after the ipBlock rule](images/netpol-dns-still-failing.png)

Nothing changes. A NetworkPolicy cannot name a Service address. The dataplane rewrites a Service IP to a backend Pod before it evaluates policy, so a rule matching that address never sees traffic. NetworkPolicy selects Pods, never Services.

#### Finding the resolver that answers

Listing the DNS components reveals a third Pod that no rule mentions.

```bash
kubectl get pods -n kube-system --show-labels | grep dns
```

![NodeLocal DNSCache running alongside kube-dns](images/netpol-dns-providers.png)

Querying each resolver separately isolates the fault. `dig @server` bypasses `resolv.conf` and asks a named server directly, which is what makes this test possible.

```bash
dig +short @34.118.224.10 nginx.demo.svc.cluster.local
dig +short @10.20.1.12 nginx.demo.svc.cluster.local
```

![The Service address failing while the kube-dns Pod answers](images/netpol-dns-bisect.png)

The kube-dns Pod answers and the Service address does not. The `allow-dns` rule is therefore correct for the Pod it names, and something else receives the query.

#### Disproving the host network theory

The working assumption at this point is that NodeLocal DNSCache runs in the host network namespace, where no Pod selector can reach it. One command disproves it.

```bash
kubectl get nodes -o wide
```

![The node internal address](images/netpol-node-ip.png)

The node holds `10.10.0.7`. NodeLocal DNSCache holds `10.20.1.2`, inside the Pod range, so it is an ordinary Pod with an ordinary Pod address. One more query confirms that the rule blocks it.

```bash
dig +short @10.20.1.2 nginx.demo.svc.cluster.local
```

![The NodeLocal DNSCache Pod refusing the query](images/netpol-nodelocal-blocked.png)

#### Confirming the application path is not involved

Addressing the Service directly, while name resolution is still broken, contains the fault to DNS.

```bash
curl -I http://34.118.237.10
```

![NGINX answering by address while DNS is down](images/netpol-service-ip-reachable.png)

The Service returns `200 OK`. The ingress and client egress rules are correct throughout, and every failed `curl` up to this point died at the name lookup without reaching them.

### Verification

![Application traffic allowed and internet egress denied](images/netpol-result.png)

Name resolution returns, the labelled client reaches NGINX, and egress to the internet stays denied. The failure mode also changes from `(6) Could not resolve host` to `(28) Connection timed out`, which confirms that the block moves one layer further along.

### Cost of the wrong assumption

Believing that the cache was host-networked led to a recommendation to disable NodeLocal DNSCache in Terraform, which recreates every node. The node address was one command away throughout. Check the cheap fact before building on the plausible mechanism.

### What to check first next time

1. Read the error. Resolution failure and connection failure are different faults.
2. Run `kubectl get netpol -n NAMESPACE -o yaml`. What the API server stored is the only version that matters.
3. Run `cat /etc/resolv.conf` inside the Pod to find the configured resolver.
4. Run `kubectl get pods -n kube-system --show-labels | grep dns`. More than one component may answer.
5. Run `dig @server` against each candidate resolver in turn.

[Dataplane V2 policy logging](https://cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2#using-network-policy) answers this directly by naming the denied connection. This cluster does not have it enabled, and the Phase 4 worklog records that as a gap.

## A Terraform plan proposes the same change after every apply

Phase 5, Slice 1.

**Issue:** Every `terraform plan` proposes to unset `enable_private_endpoint` on the cluster, and applying it changes nothing. The next plan proposes it again.

![The same modification proposed after a successful apply](images/endpoint-permadiff.png)

The apply reported success and the plan above was taken afterwards. `0 to add, 1 to change` on a run where nothing had been edited.

**Cause:** The configuration never declares the field, and GKE derives it from `control_plane_endpoints_config.ip_endpoints_config.enabled = false`. Terraform reads `true` from the API, finds nothing in the configuration, and resolves the difference in favour of the configuration. The API then ignores the write because the value is derived, so the next refresh reads `true` again.

**Fix:** Declare the value the infrastructure already has, so the configuration and the API agree.

```hcl
private_cluster_config {
  enable_private_nodes    = true
  enable_private_endpoint = true
}
```

![A clean plan after declaring the value](images/endpoint-plan-clean.png)

### Checking exposure rather than reading it

The cluster description reports a public address, which reads alarming.

```bash
gcloud container clusters describe k8-lab --zone europe-north1-a \
  --format="yaml(privateClusterConfig,controlPlaneEndpointsConfig,endpoint)"
```

![Endpoint configuration reported by GKE](images/endpoint-cluster-config.png)

`publicEndpoint` is reported whether or not the endpoint serves traffic. Reachability is governed by `ipEndpointsConfig.enabled`, which is `false`, and the `endpoint` field holds the DNS name rather than an address. Connecting settles it.

```bash
curl -k --max-time 5 https://35.228.170.226/version
```

![The public address accepting no connection](images/endpoint-not-reachable.png)

Result: `curl: (28)`, a timeout rather than a refusal, so nothing is listening. The posture recorded in the Phase 1 decision holds, and the only real fault was the recurring diff.

### Why it matters beyond the noise

The diff appeared in the first plan run after Phase 1, alongside an unrelated change. A plan that always carries one expected modification trains the reader to skim, which is how an unintended change to a security control eventually gets applied without anyone reading it. This one governs control plane exposure.

`publicEndpoint` in the cluster description is reported whether or not the endpoint serves traffic. Reachability is governed by `ipEndpointsConfig.enabled`, so the address alone is not evidence of exposure. Confirm by connecting to it rather than by reading it.

### The general rule

A plan diff on something no one edited means the configuration is silent about a value the API has an opinion on. State the value. The same shape appears wherever an API normalises input, including durations returned in seconds when the configuration was written in days.

## A Pod restart does not reload network policy

**Issue:** A policy or label change appears not to take effect, and restarting the Pod does not help.

**Cause:** Policy is not baked into a Pod at creation. The dataplane recomputes it continuously from current labels, so a restarted Pod returns with the same labels and the same verdict.

**Fix:** Change the label, the policy, or the Service selector. The running Pod picks it up within about a second. Only a change to the Pod template produces a new Pod.

## Port forwarding cannot validate network policy

**Issue:** A Pod that policy should isolate still answers on a forwarded port.

**Cause:** `kubectl port-forward` tunnels through the API server to the kubelet and enters the Pod on loopback. It never crosses the dataplane, so no policy applies.

**Fix:** Test from another Pod in the cluster with `kubectl exec`, or address the Service or Pod IP directly.

## A denied connection hangs instead of failing

**Issue:** `curl` against a blocked destination sits for more than two minutes before reporting an error.

**Cause:** A denial drops the packet silently rather than refusing the connection, so the client waits out its own connect timeout with nothing to respond to.

**Fix:** Set a timeout with `curl -m 5`. The distinction still holds in the result: `(28)` is a timeout and `(7)` is a refusal.

## POD-SELECTOR shows none for a policy that matches everything

**Issue:** `kubectl get netpol` lists `<none>` under `POD-SELECTOR`, which reads as though the policy matches no Pods.

**Cause:** The column reports that the policy has no selector terms. An empty `podSelector` selects every Pod in the namespace.

**Fix:** Read `<none>` as "all Pods here". Confirm with `kubectl describe netpol NAME`, which spells the selection out.
