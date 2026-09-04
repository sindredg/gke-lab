# Worklog: Phase 7 Gateway and Managed TLS

Date: 2026-09-03  
Status: In progress. HTTP delivery through the Gateway is complete; the managed certificate is still issuing.

## Goal

Publish the workload on the public internet through a Google load balancer with a managed certificate, while its Service stays unreachable from outside the cluster.

## The idea the phase turns on

The load balancer does not send traffic through the Service. GKE creates a network endpoint group listing Pod IP and port pairs, and the load balancer reaches those Pods directly. The Service is used only to work out which Pods belong in the group.

That is what lets both halves of the exit criteria hold at once: publicly reachable, and the Service still `ClusterIP`.

## Slice 1: Enable the Gateway API

Status: Complete

### Implemented

- Added `gateway_api_config` with `CHANNEL_STANDARD` to the cluster, installing the Gateway API CRDs and starting the controller.
- Added a `gateway` Terraform module reserving a global external address, so the address outlives any Gateway object a DNS record points at.

### The controller is not on by default

```bash
kubectl get gatewayclass
```

![The cluster does not recognise the resource type](../images/gateway-api-not-enabled.png)

```bash
terraform -chdir=terraform apply
```

![One address added, the cluster changed in place](../images/gateway-apply-complete.png)

### Validation

Status: Passed

GatewayClasses appear in waves. The first listing after the cluster update held only the layer 4 classes, all from `persistent-ip-controller`.

![Only the passthrough and persistent classes present](../images/gateway-classes-partial.png)

Nineteen minutes later the layer 7 classes had registered under `networking.gke.io/gateway`.

![The L7 classes accepted, including gke-l7-global-external-managed](../images/gateway-classes.png)

Result: `gke-l7-global-external-managed` is `Accepted`. Reading the name as a specification gives the whole configuration — layer 7, global, external, and managed by Google rather than by this project.

The absence of any row carrying the `networking.gke.io/gateway` controller is the signal that the L7 set has not landed yet. Waiting is the correct response; nothing needs reapplying.

## Slice 2: Publish over HTTP

Status: Complete

### Implemented

- Added a `Gateway` naming the reserved address by its Google Cloud name, so Terraform owns the address and the manifest only points at it.
- Added an `HTTPRoute` sending traffic to the `nginx` Service.
- Added a `HealthCheckPolicy` aiming the load balancer's health check at `/healthz` rather than `/`, so the check does not depend on page content.
- Added a `NetworkPolicy` admitting Google's health check and proxy ranges to port 8080.

```bash
kubectl apply -f kubernetes/nginx/
```

![The Gateway, HealthCheckPolicy, and HTTPRoute created](../images/gateway-manifests-applied.png)

### What the controller built

```bash
kubectl describe gateway external -n demo
```

![The address, the class, and the HTTP listener](../images/gateway-spec-address.png)

![Scheduled and Accepted both True](../images/gateway-conditions-accepted.png)

![The listener resolved its references and one route attached](../images/gateway-listener-resolved.png)

`Accepted` means the controller understood the manifest, and it flips within seconds. `Programmed` is the one worth waiting for, because it means the Google Cloud resources exist and are configured.

![The controller reporting SYNC and UPDATE](../images/gateway-controller-events.png)

```bash
gcloud compute backend-services list --global --format="table(name,healthChecks)"
```

![Three backend services, one per route target](../images/gateway-backend-services.png)

GKE generates these names, so they are discovered rather than known in advance. Two of the three are the default 404 and 500 services the Gateway creates for unmatched traffic.

### The default deny drops the health checks

Status: Failed, then fixed

```bash
gcloud compute backend-services get-health gkegw1-zs1b-demo-nginx-80-10i9ub7w3088 --global
```

![Both endpoints unhealthy on port 8080](../images/gateway-backends-unhealthy.png)

Both Pods appear in the endpoint group with the right IPs and the right port, and both are `UNHEALTHY`. The Gateway provisioned cleanly and the address answered nothing.

```bash
kubectl get netpol -n demo
```

![Four policies, none admitting the load balancer](../images/gateway-netpol-before.png)

The cause is Phase 4 working as designed. Health checks arrive from Google's infrastructure rather than from a Pod, so no `podSelector` rule can ever match them and the default deny drops every one. Nothing in the Gateway's own status says so.

`ipBlock` matches by source address, which is the only way to name a sender that is not a Pod. Phase 4 used `podSelector` for in-cluster clients; neither form can express the other.

```bash
kubectl apply -f kubernetes/nginx/networkpolicy-gateway.yml
```

![The gateway policy created alongside the existing four](../images/gateway-netpol-applied.png)

![Both endpoints healthy](../images/gateway-backends-healthy.png)

Result: both endpoints `HEALTHY` on the same IPs and port. The only thing that changed is that Google's proxies are now admitted to one port on one set of Pods.

### Validation

Status: Passed

```bash
IP=$(terraform -chdir=terraform output -raw gateway_address)
curl -sI "http://$IP"
curl -sI "http://$IP/healthz"
```

![Both requests answered through the load balancer](../images/gateway-http-via-google.png)

Result: `200 OK` for the page and for the probe path. The `via: 1.1 google` header is the evidence that the response came through the load balancer rather than from somewhere else.

That header sits ninth in the response, after `last-modified`, `etag`, and `accept-ranges`. A `head -5` truncates it, which reads as a missing header rather than a truncated listing.

## Slice 3: Domain and managed TLS

Status: In progress

### Implemented

- Registered `sindrg.com` and delegated it to Cloudflare.
- Added a Certificate Manager DNS authorization, a managed certificate, a certificate map, and a map entry.
- Added the `networking.gke.io/certmap` annotation and an HTTPS listener to the Gateway.
- Added a redirect route answering plain HTTP with a permanent redirect.

![The domain registered](../images/gateway-domain-registered.png)

### Why DNS authorization

A certificate authority will not issue for a name until control of it is proven. DNS authorization proves control with one `CNAME` record that Google checks; load balancer authorization proves it by checking the live load balancer at that name.

DNS authorization decouples issuance from the cutover, so a valid certificate can exist before the domain points at anything. The cost is one extra record, permanently, because renewal re-checks it.

```bash
terraform -chdir=terraform apply
```

![Five Certificate Manager resources added](../images/gateway-certmanager-apply.png)

### DNS

```bash
dig +short sindrg.com NS
```

![Cloudflare answering as authoritative](../images/gateway-nameservers.png)

```bash
dig +short @1.1.1.1 sindrg.com A
dig +short @8.8.8.8 sindrg.com A
dig +short sindrg.com A
```

![The apex resolving to the reserved address from three resolvers](../images/gateway-dns-a-record.png)

Querying a public resolver as well as the local one separates a record that does not exist from a negative answer cached locally. The apex took several minutes to appear locally after it resolved elsewhere.

```bash
curl -I http://sindrg.com
```

![The domain served through the load balancer](../images/gateway-domain-http.png)

### The certificate was issued for the wrong domain

Status: Failed, then fixed

```bash
curl -I https://sindrg.com
```

![The connection refused at the transport layer](../images/gateway-https-refused.png)

`SSL_ERROR_SYSCALL` is a connection-level failure, not a certificate error. A rejected or mismatched certificate produces a verify error instead. Nothing was listening on 443, because GKE does not stand up an HTTPS frontend without a usable certificate.

The certificate itself reported `PROVISIONING` indefinitely. The reason was only visible in `managed.authorizationAttemptInfo`, not in the top-level state:

```text
domain: sidnrg.com
failureReason: CONFIG
issues:
- CNAME_MISMATCH
```

The Terraform `domain` variable held `sidnrg.com`. The certificate, the DNS authorization, and the map entry had all been created for a domain nobody owns, and the `CNAME` in Cloudflare was correct for that wrong name, because it had been copied faithfully from Terraform's output.

`domain` is immutable on both resources, so correcting it replaced them.

```bash
terraform -chdir=terraform apply
```

![Three resources replaced](../images/gateway-domain-fix-apply.png)

Replacement issues a new authorization with a new target, so the record in Cloudflare became stale the moment the apply finished.

```bash
gcloud certificate-manager dns-authorizations describe k8-lab-gateway-dns-auth \
  --format="value(dnsResourceRecord.name,dnsResourceRecord.data)"
dig +short _acme-challenge.sindrg.com CNAME
```

![The expected target and the served target differing](../images/gateway-cname-mismatch.png)

Comparing the two values directly is what identifies a stale record. The served value still began `c016c223`, from the destroyed authorization; the expected value began `fbee38d7`.

The [troubleshooting log](../troubleshooting.md#a-managed-certificate-stays-in-provisioning) records the diagnosis.

### The HTTPS listener

```bash
kubectl apply -f kubernetes/nginx/
```

![The redirect route created and the main route rebound](../images/gateway-https-listener-applied.png)

The main route is bound to `sectionName: https`, so it could not attach until the HTTPS listener existed. The redirect route attaches to the HTTP listener and answers with a `301`, so no request reaches a Pod in clear text.

### Validation

Status: Complete

```bash
gcloud certificate-manager certificates describe k8-lab-gateway-cert --format=yaml
```

![The certificate authorizing against the correct domain](../images/gateway-cert-authorizing.png)

Correcting the domain moved the certificate to `domains: sindrg.com`, `state: PROVISIONING`, with the `CNAME` resolving to the expected target.

A later attempt, roughly three hours after that correction, failed again, and kept failing. The cause was Cloudflare: it serves hidden `TXT` records at `_acme-challenge.sindrg.com` for its own Universal SSL, and a name carrying both a `CNAME` and a `TXT` answers `TXT` queries from the `TXT` set alone. Validation asks for `TXT`, so it never followed the `CNAME` to Google. The records do not appear in the Cloudflare dashboard.

Switching the authorization to `PER_PROJECT_RECORD` moves validation to `_acme-challenge_<hash>.sindrg.com`, a label nothing else claims. `type` is immutable, so this replaced the authorization, the certificate and the map entry, and the DNS record was rewritten with a new name and a new target. The [troubleshooting log](../troubleshooting.md#a-second-failure-with-the-domain-and-the-record-both-correct) carries the queries that isolate it.

The certificate reached `ACTIVE` shortly after.

![The certificate active and authorized](../images/gateway-cert-active.png)

The evidence the phase was waiting on:

```bash
curl -I https://sindrg.com
curl -I https://sindrg.com/healthz
curl -I http://sindrg.com/
echo | openssl s_client -connect sindrg.com:443 -servername sindrg.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

![HTTP/2 200 over TLS](../images/gateway-https-200.png)

![The health endpoint over TLS](../images/gateway-https-healthz.png)

![HTTP redirected to HTTPS](../images/gateway-http-redirect.png)

`via: 1.1 google` confirms the response came through the load balancer rather than anything else answering for the name, and port 80 returns `301` to `https://sindrg.com:443/` from the redirect route.

The certificate on the wire:

```text
subject=CN = sindrg.com
issuer=C = US, O = Google Trust Services, CN = WR3
notBefore=Sep  4 12:17:24 2026 GMT
notAfter=Dec  3 13:13:19 2026 GMT
```

![The browser reporting a valid certificate](../images/gateway-browser-secure.png)

No apply was needed once the certificate became usable. GKE configured the HTTPS frontend on its own.

## Slice 4: Prove the Service stayed private

Status: Complete

Publicly reachable is demonstrated. The other half of the exit criteria is the claim a reader will doubt.

```bash
kubectl get svc nginx -n demo -o jsonpath='{.spec.type}{"  externalIPs="}{.spec.externalIPs}{"\n"}'
kubectl get svcneg -n demo -o wide
```

```text
ClusterIP  externalIPs=
NAME                                   AGE
k8s1-0bf1ac7c-demo-nginx-80-49b21201   19h
```

The Service holds no external address. Traffic reaches the Pods through the `ServiceNetworkEndpointGroup` the Gateway controller manages, so the load balancer addresses Pod endpoints directly and the Service is never published. Going public changed the path into the cluster, not the exposure of the workload.

## Known gaps

- The Gateway admits Google's health check ranges by source address. Every Google Cloud customer's proxies originate there, so this is the coarsest control that works rather than identity.
- Nothing rate-limits or filters requests. Cloud Armor is the answer and is a phase of its own.
- The certificate covers the apex only. `www.sindrg.com` is absent from the certificate, the map entry `hostname` and the route `hostnames`, so adding it is a four-part change rather than a DNS record.
- The zone still carries Cloudflare's hidden `_acme-challenge` `TXT` records. They are harmless now that validation uses a per-project label, but they will break any future authorization that uses the default `FIXED_RECORD` type.
- `HealthCheckPolicy` is not schema-validated in CI. It is a GKE-proprietary CRD with no public schema, so `-ignore-missing-schemas` skips it.
