# Worklog: Phase 2 NGINX Workload

Date: 2026-08-28  
Status: Complete

## Goal

Deploy and validate a private NGINX workload on GKE.

## Where the workload runs

```text
Your WSL terminal
    │
    │ kubectl sends YAML through the DNS control-plane endpoint
    ▼
GKE control plane
    │
    │ creates and manages the requested resources
    ▼
Deployment → ReplicaSet → 2 NGINX Pods
                         │
                         ▼
                 GKE node in Google Cloud
```

## How local access works

```text
Browser
    │
    │ localhost:8080
    ▼
kubectl port-forward in WSL
    │
    │ encrypted connection through the Kubernetes API
    ▼
One selected NGINX Pod in GKE
```

## Implemented

- Installed the GKE authentication plugin for `kubectl`.
- Created the `demo` namespace.
- Deployed two NGINX replicas using `nginx:1.30.4-alpine3.24`.
- Added health probes, resource controls, and a private ClusterIP Service.

## Validation

`kubectl rollout status deployment/nginx -n demo`

![NGINX rollout completed](../images/nginx-rollout.png)

`kubectl get pods -n demo -o wide`

![Two healthy NGINX Pods](../images/nginx-pods.png)

`kubectl get endpointslices -n demo -l kubernetes.io/service-name=nginx`

![NGINX Service endpoints](../images/nginx-endpoints.png)

`kubectl port-forward service/nginx 8080:80 -n demo`

![NGINX reached through local port forwarding](../images/nginx-local-test.png)

Result: rollout succeeded, both Pods are healthy, the Service selected both Pods, and NGINX responded locally.

## Self-healing test

`kubectl delete pod <pod-name> -n demo`

`kubectl get pods -n demo --watch`

![Kubernetes replacing the deleted Pod](../images/nginx-self-healing-watch.png)

`kubectl get deployments,replicasets,pods -n demo -o wide`

![Deployment restored to two healthy Pods](../images/nginx-self-healing-result.png)

`kubectl get events -n demo --sort-by=.metadata.creationTimestamp`

![Self-healing lifecycle events](../images/nginx-self-healing-events.png)

Result: Kubernetes replaced the deleted Pod and restored the Deployment to `2/2` ready replicas.

Note: one readiness check failed while NGINX was starting. The Pod recovered and became ready normally.

## Scaling test

`kubectl scale deployment/nginx --replicas=3 -n demo`

`kubectl get pods -n demo -o wide`

![Three healthy NGINX Pods](../images/nginx-scale-three-pods.png)

`kubectl get endpointslices -n demo -l kubernetes.io/service-name=nginx`

![Service updated to three Pod endpoints](../images/nginx-scale-three-endpoints.png)

`kubectl apply -f kubernetes/nginx/deployment.yml`

`kubectl get deployments,pods -n demo -o wide`

![YAML restored the Deployment to two replicas](../images/nginx-scale-restored.png)

Result: live scaling added a third Pod and Service endpoint. Reapplying the manifest restored the declared two-replica state.

## Rolling restart and rollback

`kubectl rollout restart deployment/nginx -n demo`

`kubectl get pods -n demo --watch`

![NGINX Pods replaced gradually](../images/nginx-rolling-restart-watch.png)

`kubectl get replicasets,pods -n demo -o wide`

![New ReplicaSet active after restart](../images/nginx-rolling-restart-result.png)

`kubectl rollout undo deployment/nginx -n demo`

`kubectl get replicasets,pods -n demo -o wide`

![Previous ReplicaSet restored by rollback](../images/nginx-rollback-result.png)

Result: revision 2 replaced the Pods gradually, then rollback restored revision 1 with two healthy Pods.

`kubectl rollout history deployment/nginx -n demo`

History recorded two Deployment revisions.

## Next

- Decide how the application should be exposed externally.

