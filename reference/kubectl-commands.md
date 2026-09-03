# kubectl Command Reference

Commands used to operate and inspect this platform, grouped by what you are trying to do.

Replace every value inside `<...>` before running a command.

| Placeholder | Meaning |
| --- | --- |
| `<cluster>` | GKE cluster name |
| `<location>` | GCP zone or region |
| `<namespace>` | Kubernetes namespace |
| `<deployment>` | Deployment name |
| `<pod>` | Pod name |
| `<container>` | Container name |
| `<service>` | Service name |
| `<image>` | Full image reference, including the digest |
| `<manifest>` | YAML file or directory |
| `<local-port>` | Port on your computer |
| `<service-port>` | Port exposed by the Service |
| `<count>` | Desired replica count |
| `<principal>` | Google identity, such as a service account email |

## 1. Connect

### Get cluster credentials

```bash
gke-gcloud-auth-plugin --version
gcloud container clusters get-credentials <cluster> --location=<location> --dns-endpoint
kubectl config current-context
kubectl cluster-info
```

This cluster disables its IP endpoints, so `--dns-endpoint` is required. The DNS endpoint is authorized by IAM rather than by source address, which is what lets a GitHub-hosted runner reach it with no bastion and no allowlist.

## 2. Apply and remove

### Apply a manifest

```bash
kubectl apply -f <manifest>
```

`apply` creates missing resources and updates existing resources to match the YAML.

### Remove what a manifest defines

```bash
kubectl delete -f <manifest>
```

Read the manifest first. This removes every resource it defines, including ones you may not have intended to name.

## 3. Inspect

### List resources

```bash
kubectl get namespaces
kubectl get deployments -n <namespace>
kubectl get replicasets -n <namespace>
kubectl get pods -n <namespace> -o wide
kubectl get services -n <namespace>
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service>
```

### Read one field

```bash
kubectl get deployment/<deployment> -n <namespace> \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Use this to confirm what the cluster actually runs. What a manifest in git says and what the Deployment holds can differ, because the delivery pipeline sets the image directly.

### Describe one object

```bash
kubectl describe deployment/<deployment> -n <namespace>
kubectl describe pod/<pod> -n <namespace>
```

Describe one Pod by name. `kubectl describe pod -l <selector>` concatenates every matching Pod, so piping it to `tail` shows the last Pod rather than the one that failed.

### Built-in schema documentation

```bash
kubectl explain deployment.spec
kubectl explain deployment.spec.template.spec.containers
kubectl explain service.spec
kubectl api-resources
```

## 4. Diagnose a failure

### Read events

```bash
kubectl get events -n <namespace> --sort-by=.lastTimestamp | tail -20
```

Events are the first place to look when a Pod is created but never starts. A container that fails to start records its reason here and nowhere else. Events expire after about an hour, so capture them while the failure is fresh.

### Read logs

```bash
kubectl logs deployment/<deployment> -n <namespace>
kubectl logs pod/<pod> -c <container> -n <namespace>
```

Add `-f` to follow new output.

### Separate the failure modes

| Symptom | Where the fault is |
| --- | --- |
| Object rejected immediately, error names a policy | Admission: Pod Security, quota, or a webhook |
| Pod `Pending`, no node assigned | Scheduling: resources, selectors, or taints |
| `ErrImagePull` or `ImagePullBackOff` | Image reference, registry permissions, or platform mismatch |
| Pod created, container never starts | The kubelet refused the container spec; read the events |
| `Running` but `0/1` | The readiness probe is failing |

## 5. Roll out and roll back

### Watch a rollout

```bash
kubectl rollout status deployment/<deployment> -n <namespace> --timeout=180s
```

`rollout status` only waits. It reports that a rollout has not finished, never why. When it stalls, stop it and inspect the new Pod instead.

Always set `--timeout`. Without one, an automated caller waits indefinitely on a rollout that will never complete.

### Change the running image

```bash
kubectl set image deployment/<deployment> <container>=<image> -n <namespace>
```

Name the image by digest. A tag is a label the registry could repoint; a digest names one fixed set of bytes.

### Roll back

```bash
kubectl rollout history deployment/<deployment> -n <namespace>
kubectl rollout undo deployment/<deployment> -n <namespace>
```

`undo` scales the failing ReplicaSet to zero and restores the previous one. With `maxUnavailable: 0` the previous Pods never stopped serving, so this ends a stalled rollout rather than recovering an outage.

### Scale

```bash
kubectl scale deployment/<deployment> --replicas=<count> -n <namespace>
```

Use `scale` for temporary testing. Change the YAML for a permanent replica count.

## 6. Verify permissions

### Ask what an identity may do

```bash
kubectl auth can-i <verb> <resource> -n <namespace> --as="<principal>"
```

`--as` asks the API server the same question the caller will ask, without running the caller. Use it to check a binding before a pipeline depends on it.

Test the refusals as well as the grants. A binding that answers `yes` to everything usually means a `ClusterRole` was bound where a `Role` was intended.

```bash
SA=<principal>
kubectl auth can-i patch deployments  -n <namespace> --as="$SA"    # expected: yes
kubectl auth can-i delete deployments -n <namespace> --as="$SA"    # expected: no
kubectl auth can-i get secrets        -n <namespace> --as="$SA"    # expected: no
kubectl auth can-i patch deployments  -n kube-system  --as="$SA"   # expected: no
```

### List what an identity may do

```bash
kubectl auth can-i --list -n <namespace> --as="<principal>"
```

## 7. Test from inside the cluster

### Reach a private Service from your workstation

```bash
kubectl port-forward service/<service> <local-port>:<service-port> -n <namespace>
curl http://localhost:<local-port>
```

The mapping is `<local-port>:<service-port>`. `port-forward` bypasses NetworkPolicy, so it proves the Service and the application work. It does not prove that another Pod is allowed to reach them.

### Run a throwaway Pod

```bash
kubectl run <pod> -n <namespace> \
  --image=<image> \
  --labels=nginx-client=true \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"probe","image":"<image>",
    "command":["curl","-sSf","--max-time","5","http://<service>/healthz"],
    "securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,
    "runAsUser":100,"capabilities":{"drop":["ALL"]},
    "seccompProfile":{"type":"RuntimeDefault"}}}]}}'
```

In this namespace such a Pod needs both:

- The `nginx-client: "true"` label, or the default-deny NetworkPolicy drops its traffic.
- A complete `securityContext`, or the `restricted` Pod Security standard rejects it. Set `runAsUser` to a number as well as `runAsNonRoot`, because the kubelet cannot verify an image whose user is a name.

### Wait for it to finish

```bash
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/<pod> -n <namespace> --timeout=90s \
  || { kubectl describe pod/<pod> -n <namespace>; exit 1; }
kubectl logs <pod> -n <namespace>
kubectl delete pod/<pod> -n <namespace> --ignore-not-found
```

Prefer this to `kubectl run --attach`. Attaching waits for the Pod to reach `Running` and reports a bare timeout when it does not, hiding the reason. It also races against a container that exits in under a second, and needs the `pods/attach` subresource that a least-privilege Role does not grant.
