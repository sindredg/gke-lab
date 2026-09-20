# Worklog

What was run, what came back, and what it proves. `plan.md` holds the intent,
`decisions.md` the reasoning, these hold the evidence.

## Phases

| Phase | Proves |
| --- | --- |
| [01 Infrastructure](phase-01-infrastructure.md) | A private cluster, custom VPC and DNS-only control plane come up from Terraform |
| [02 nginx workload](phase-02-nginx-workload.md) | A workload serves, self-heals, scales and rolls back |
| [03 CI](phase-03-ci.md) | Invalid Terraform or manifests fail in a pull request, with no cloud credential |
| [04 Workload guardrails](phase-04-workload-guardrails.md) | A privileged Pod and an oversized request are rejected at admission, and an unlabelled client is denied |
| [05 Custom image](phase-05-custom-image.md) | The workload runs a project-owned non-root image pulled by digest |
| [06 Keyless delivery](phase-06-keyless-delivery.md) | A push to `main` deploys with no stored key |
| [07 Gateway and TLS](phase-07-gateway-tls.md) | The domain serves HTTPS on a managed certificate while Services stay internal |
| [08 Observability](phase-08-observability.md) | Onboarding time, deploy duration and cost are measured rather than estimated |
| [09 Resilience](phase-09-resilience.md) | A workload survives losing the node under it |
| [10 Failure drills](phase-10-failure-drills.md) | A deliberate break is detected, alerted on, and recovered |
| [11 Hardening](phase-11-hardening.md) | The open default network is gone and a `ForceNew` drift is caught before it destroys the pool |
| [12a Load baseline](phase-12a-load-baseline.md) | Where two replicas saturate |
| [12b Rollout baseline](phase-12b-rollout-baseline.md) | A rollout drops requests until `preStop` is added |
| [12c Rollouts and connections](phase-12c-rollouts-connections.md) | Keep-alive tuning removes the last closed-connection failures |
| [12d Autoscaling](phase-12d-autoscaling.md) | Eight replicas across three zones hold 125 rps with no failures |
| [13 Security baseline](phase-13-security-baseline.md) | The platform measured against its own threat model, not against a reading of it |
| [14 Close the baseline](phase-14-close-the-baseline.md) | The hardening that baseline ranked, with its remaining gaps stated |
| [15 SCC triage](phase-15-scc-triage.md) | Findings reach a notification path, and two plans that looked right and were not |

## Other records

| Record | What it is |
| --- | --- |
| [Availability drill postmortem](notes/postmortem-availability-drill.md) | Incident write-up from the Phase 10 drill |
| [Repository review](notes/repository-review.md) | A pass over the repository itself rather than the platform |
| [Manifest linting](notes/manifest-linting.md) | How the manifest checks were chosen and tuned |
| [Shared smoke test](notes/shared-smoke-test.md) | Why both delivery workflows call one composite action |
| [Upstream pin automation](notes/upstream-pin-automation.md) | How the `sky` pin is proposed and what reviews it |

## Reading one

Every worklog carries the command and its output. A number without a command
behind it is a gap, and the worklogs say so where one exists.
