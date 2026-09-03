# IAM and Workload Identity Federation Reference

How this platform's identities are established, scoped, and verified. Written against what Phase 6 builds, but the concepts apply to any pipeline that authenticates to Google Cloud without a key.

Replace every value inside `<...>` before running a command.

| Placeholder | Meaning |
| --- | --- |
| `<project-id>` | Project identifier, such as `my-project-123` |
| `<project-number>` | Numeric project identifier |
| `<pool>` | Workload Identity Pool ID |
| `<provider>` | Workload Identity Pool provider ID |
| `<sa-email>` | Service account email |
| `<repository>` | GitHub repository as `owner/name` |
| `<repository-id>` | Artifact Registry repository name |
| `<location>` | GCP region |

## The problem federation solves

A workstation authenticates with `gcloud auth login`, because a person is present to complete it. A CI runner has nobody to log in, so it needs an identity of its own.

The direct answer is to create a service account, download its JSON key, and store the key where the runner can read it. That key is a **bearer credential**: possession is authorization. It does not expire, it does not record where it was used, and anyone who reads it is the pipeline until someone notices and rotates it.

Workload Identity Federation replaces the stored key with an exchange. The CI platform already signs a short-lived token describing each run. You configure Google Cloud to trust that signature and to accept only tokens describing the workload you intend. Nothing is stored.

## The exchange, step by step

```text
1  Workflow requests a token from GitHub          needs id-token: write
       │                                          OIDC token, signed by GitHub,
       │                                          valid minutes, describes this run
       ▼
2  STS validates the token                        signature against GitHub's public keys
       │                                          claims against the attribute condition
       ▼
3  STS returns a federated token                  identifies the caller as a pool principal
       │
       ▼
4  IAM Credentials issues an access token         requires roles/iam.workloadIdentityUser
       │                                          on the target service account
       ▼
5  The pipeline acts as the service account       holds only that account's roles
```

Two APIs carry this, and neither is enabled by default:

- `sts.googleapis.com` — step 2 and 3.
- `iamcredentials.googleapis.com` — step 4.

Steps 2 and 4 fail differently, and telling them apart is most of the diagnosis. See [Reading a failure](#reading-a-failure).

## What the token contains

GitHub's OIDC token is a JWT whose claims describe the run. The ones this platform uses:

| Claim | Example | Use |
| --- | --- | --- |
| `iss` | `https://token.actions.githubusercontent.com` | Identifies the issuer; fixes which public keys validate the signature |
| `sub` | `repo:owner/name:ref:refs/heads/main` | The subject, a composite string; mapped to `google.subject` |
| `repository` | `owner/name` | The repository that ran the workflow |
| `ref` | `refs/heads/main` | The git ref the run started from |
| `aud` | The provider resource name | Binds the token to one provider so it cannot be replayed elsewhere |

The token is signed, not encrypted. Its claims are readable by anyone holding it, and the signature is what makes them trustworthy. Treat it as an assertion about the run, not as a secret about the project.

## Attribute mapping

Mapping copies claims from the token into attributes Google Cloud can reason about. Only mapped attributes can be referenced by a condition or by an IAM member string.

```hcl
attribute_mapping = {
  "google.subject"       = "assertion.sub"
  "attribute.repository" = "assertion.repository"
  "attribute.ref"        = "assertion.ref"
}
```

`google.subject` is required and must be unique per identity. Everything else becomes `attribute.<name>`, and you map only what you intend to authorize or audit on. Mapping a claim you never use adds a field to every log entry and nothing else.

## Attribute condition

The condition is the trust boundary. Without it, the provider validates that a token was signed by GitHub and stops there.

```hcl
attribute_condition = "assertion.repository == '<repository>'"
```

Every public repository on GitHub receives tokens from the same issuer. A provider with a mapping and no condition therefore accepts a validly signed token from a repository an attacker creates. The condition narrows "signed by GitHub" to "signed by GitHub, for this repository".

Treat a provider without an attribute condition as an open door, regardless of how narrow its IAM bindings are. The bindings decide what a caller may do; the condition decides who may become the caller at all.

Conditions use [Common Expression Language](https://cloud.google.com/iam/docs/workload-identity-federation#conditions) and can combine claims:

```text
assertion.repository == 'owner/name' && assertion.ref == 'refs/heads/main'
```

Scoping to a ref is stricter and breaks on every branch rename. This platform scopes to the repository only, and records that trade-off in [decisions.md](../decisions.md#federation-trust-boundary).

## principal, principalSet, and principalSetHierarchy

An IAM member string names who may impersonate a service account.

| Form | Names | Use when |
| --- | --- | --- |
| `principal://.../subject/<sub>` | One exact subject | You are pinning a single workflow on a single ref |
| `principalSet://.../attribute.<name>/<value>` | Every identity sharing an attribute | You are authorizing a repository, team, or environment |
| `principalSet://.../*` | Every identity in the pool | Almost never; this is the pool with no boundary |

```hcl
member = "principalSet://iam.googleapis.com/${pool.name}/attribute.repository/<repository>"
```

`principalSet` on `attribute.repository` authorizes every workflow in the repository. The branch, the workflow file, and the job name all change over a project's life. The repository does not, which makes it the stable thing to bind.

## Two layers of authorization

Reaching a GKE cluster and acting on it are separate decisions, made by separate systems. Both must say yes.

| Layer | System | Grants | Failure looks like |
| --- | --- | --- | --- |
| Reach the cluster | Google IAM | `roles/container.clusterViewer` | `get-gke-credentials` fails, or `PERMISSION_DENIED` on the cluster resource |
| Act in the cluster | Kubernetes RBAC | A namespaced `Role` and `RoleBinding` | `Error from server (Forbidden)` naming a verb and resource |

On GKE, a Google identity is a valid RBAC subject named by its email:

```yaml
subjects:
  - kind: User
    name: <sa-email>
    apiGroup: rbac.authorization.k8s.io
```

This split is what keeps the project-level grant to discovery only. `roles/container.developer` is one line of Terraform and grants read and write on every object in every cluster in the project; `clusterViewer` plus a four-rule namespaced Role grants what a rollout needs and nothing else.

The pipeline cannot apply its own RBAC, because doing so would require the permissions it is asking for. A human applies it once, before the first run. That bootstrapping step is a property worth keeping, not an inconvenience to automate away.

## Scoping roles to a resource

Prefer a resource-level binding to a project-level one wherever the API supports it.

```hcl
# Push rights on one repository, not on every repository in the project.
resource "google_artifact_registry_repository_iam_member" "deploy_writer" {
  project    = var.project_id
  location   = var.region
  repository = var.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deploy.email}"
}
```

A member string always carries its principal type. `serviceAccount:`, `user:`, `group:`, and `domain:` are the common ones, and omitting the prefix is a common cause of an apply that succeeds while granting nothing you expected.

## Verification

### Confirm no key exists

```bash
gcloud iam service-accounts keys list --iam-account=<sa-email> --managed-by=user
```

Expect `Listed 0 items.`

`--managed-by=user` is the part that matters. Every service account holds Google-managed signing keys it cannot function without, and those cannot be downloaded. A user-managed key is the credential worth avoiding.

### Read the provider and its condition

```bash
gcloud iam workload-identity-pools providers describe <provider> \
  --location=global --workload-identity-pool=<pool> --project=<project-id>
```

Check `attributeCondition` is present and names the repository you intend.

### Read who may impersonate the account

```bash
gcloud iam service-accounts get-iam-policy <sa-email>
```

Check that `roles/iam.workloadIdentityUser` is bound to a `principalSet` naming an attribute, not to the pool root.

### Read what the account may do

```bash
gcloud projects get-iam-policy <project-id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:<sa-email>" \
  --format="table(bindings.role)"

gcloud artifacts repositories get-iam-policy <repository-id> --location=<location>
```

### Confirm the required APIs

```bash
gcloud services list --enabled | grep -E 'sts|iamcredentials'
gcloud projects describe <project-id> --format='value(projectNumber)'
```

The provider resource path uses the project **number**, not the ID. A path built with the ID is a common cause of an authenticate step that fails on a correctly configured provider.

## Reading a failure

Identify which step failed before forming a theory. The steps have no causes in common.

| Message | Step | Meaning |
| --- | --- | --- |
| `read ECONNRESET`, `ETIMEDOUT` | 2 | Transport. The request never arrived. Re-run before investigating configuration. |
| `Unable to acquire impersonated credentials` | 2 or 4 | The token was rejected, or the impersonation binding is missing |
| `The given credential is rejected` | 2 | The attribute condition did not match. Check the repository name, including case |
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | 4 | `roles/iam.workloadIdentityUser` is missing or bound to the wrong member |
| `SERVICE_DISABLED` | 2 or 4 | `sts` or `iamcredentials` is not enabled |
| `Error from server (Forbidden)` | 5 | Federation succeeded. This is Kubernetes RBAC |

The distinction that saves the most time is the first row against the rest. A transport failure means nothing was evaluated, so the configuration you are about to inspect is not implicated. A rejection means the exchange happened and something about the token or the bindings is wrong.

## Further reading

- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Federation for deployment pipelines](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [Service account best practices in deployment pipelines](https://cloud.google.com/iam/docs/best-practices-for-using-service-accounts-in-deployment-pipelines)
- [GitHub OIDC token claims](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [GKE RBAC and Google identities](https://cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control)
