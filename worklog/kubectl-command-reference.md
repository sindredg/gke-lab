# kubectl Command Reference

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
| `<manifest>` | YAML file or directory |
| `<local-port>` | Port on your computer |
| `<service-port>` | Port exposed by the Service |
| `<count>` | Desired replica count |

## Connect to GKE

```bash
gke-gcloud-auth-plugin --version
gcloud container clusters get-credentials <cluster> --location=<location> --dns-endpoint
kubectl config current-context
kubectl cluster-info
```

## Apply configuration

```bash
kubectl apply -f <manifest>
```

`apply` creates missing resources and updates existing resources to match the YAML.

## Inspect resources

```bash
kubectl get namespaces
kubectl get deployments -n <namespace>
kubectl get replicasets -n <namespace>
kubectl get pods -n <namespace> -o wide
kubectl get services -n <namespace>
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service>
```

## Validate and troubleshoot

```bash
kubectl rollout status deployment/<deployment> -n <namespace> --timeout=2m
kubectl describe deployment/<deployment> -n <namespace>
kubectl describe pod/<pod> -n <namespace>
kubectl logs deployment/<deployment> -n <namespace>
kubectl logs pod/<pod> -c <container> -n <namespace>
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
```

Add `-f` to `kubectl logs` to follow new log output.

## Test a private Service

```bash
kubectl port-forward service/<service> <local-port>:<service-port> -n <namespace>
curl http://localhost:<local-port>
```

The port mapping is `<local-port>:<service-port>`.

## Scale and inspect rollouts

```bash
kubectl scale deployment/<deployment> --replicas=<count> -n <namespace>
kubectl rollout history deployment/<deployment> -n <namespace>
kubectl rollout undo deployment/<deployment> -n <namespace>
```

Use `scale` for temporary testing. Change the YAML for a permanent replica count.

## Built-in documentation

```bash
kubectl explain deployment.spec
kubectl explain deployment.spec.template.spec.containers
kubectl explain service.spec
kubectl api-resources
```

## Remove manifest resources

```bash
kubectl delete -f <manifest>
```

Review the manifest before deleting because this removes the resources it defines.

