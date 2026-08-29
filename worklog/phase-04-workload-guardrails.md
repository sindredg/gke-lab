# Worklog: Phase 4 Workload Guardrails

Date: 2026-08-29  
Status: In progress

## Goal

Guard the `demo` namespace so that dangerous, oversized, or unauthorized workloads are rejected rather than merely discouraged.

## Where the controls apply

```text
kubectl apply
    │
    ▼
GKE API server
    │
    ├── Authentication      who is calling
    ├── Authorization       is the caller allowed to do this
    ├── Admission control   is this specific object allowed as written
    │        │
    │        └── Pod Security Admission reads the namespace labels
    ▼
Cluster database
    │
    ▼
Scheduler assigns a node, kubelet starts the container
```

A rejection at admission means the object is never stored. No image is pulled, no node is selected, and no container starts.

## Slice 1: Pod Security and workload identity

Status: Complete

### Implemented

- Labelled the `demo` namespace to enforce the Pod Security `baseline` standard.
- Set `warn` and `audit` to the stricter `restricted` standard.
- Pinned all three to `v1.35` so a cluster upgrade cannot change enforcement.
- Added a dedicated `nginx` ServiceAccount with `automountServiceAccountToken` disabled.
- Moved the Deployment off the namespace `default` ServiceAccount.

### Validation

Status: Passed

```bash
kubectl apply -f kubernetes/nginx/namespace.yml
kubectl get namespace demo --show-labels
```

![Pod Security labels applied to the demo namespace](../images/psa-namespace-labels.png)

Applying the labels produced no warning about existing Pods, which confirms the running workload already satisfies `baseline`. Both Pods kept running with zero restarts.

```bash
kubectl apply -f kubernetes/nginx/deployment.yml
```

![Restricted standard reported as a warning](../images/psa-restricted-warning.png)

The `warn` label reported three `restricted` violations and applied the Deployment anyway: `allowPrivilegeEscalation != false`, unrestricted capabilities, and `runAsNonRoot != true`. These are the same gaps kube-linter reports in CI.

```bash
kubectl rollout status deployment/nginx -n demo
kubectl get pods -n demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.serviceAccountName}{"\n"}{end}'
kubectl exec -n demo deploy/nginx -- ls /var/run/secrets/kubernetes.io/
```

![Pods running under the nginx ServiceAccount with no mounted token](../images/nginx-serviceaccount.png)

Result: changing `serviceAccountName` altered the Pod template, so a new ReplicaSet replaced both Pods. Both now run as `nginx`, and the API token directory does not exist inside the container.

### Failure test

```bash
kubectl apply -n demo -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: psa-test
spec:
  containers:
    - name: test
      image: nginx:1.30.4-alpine3.24
      securityContext:
        privileged: true
YAML
```

![Privileged Pod rejected by the baseline standard](../images/psa-privileged-rejected.png)

Result: the API server refused the Pod with `violates PodSecurity "baseline:v1.35": privileged`. Nothing was created, and the two NGINX Pods were unaffected.

The wording separates the two modes. `enforce` reports `violates` and rejects. `warn` reports `would violate` and allows.

## Known gaps

- The workload still runs as root, so it cannot satisfy the `restricted` standard. Phase 5 replaces it with a non-root image, after which `enforce` can be raised.
- `audit` findings are written to the Google Cloud audit log and have not been reviewed yet.

## Next

- Slice 2: `ResourceQuota` and `LimitRange` on the namespace.
- Slice 3: default-deny NetworkPolicy with explicit DNS and application allow rules.
