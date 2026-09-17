# Shared smoke test

Date: 2026-09-17

## Done

- Reviewed the repository for refactoring. Roughly 3,300 lines of infrastructure code, no dead CSS, comment density already low after [#79](https://github.com/sindredg/k8-lab/pull/79). The two delivery workflows held the only material duplication: 102 of `deploy.yml`'s 112 non-blank lines also appeared in `deploy-sky.yml`.
- Extracted the in-cluster smoke test into `.github/actions/smoke-test`, called by both. ([#90](https://github.com/sindredg/k8-lab/pull/90))
- Recorded [shared smoke test](../decisions.md#shared-smoke-test), linked to the unchanged [delivery workflow separation](../decisions.md#delivery-workflow-separation).

## Why, since it adds 14 lines

- The step was 37 lines repeated byte for byte, differing in the Pod name, the client label and the URL.
- Sixteen of them are the `securityContext` the restricted Pod Security standard requires. A change there had to be made twice, correctly, or sky's smoke Pod would be rejected at admission while nginx's passed.
- The workflows lose 60 lines, the action costs 74. One definition instead of two kept in step by hand.

## Verified

- Ran the action's script with `kubectl` stubbed. The generated `--overrides` payload parsed equal to the inline JSON it replaces, for both workloads.
- YAML parses, the action path resolves from both callers, `bash -n` clean, `check-docs.sh` passes.
- Merging triggered both deploys, since each workflow lists its own file in `paths`. `Deploy sky` and `Deploy` both succeeded with the smoke step run, not skipped.

## Cost

- The nginx smoke Pod is now `smoke-nginx-<run id>`. It is created and deleted inside the step.
- A second file to open when reading either pipeline.

## Open

- 10 unused module outputs in `terraform/modules/`, exported and referenced by nothing.
- Dependabot watches `github-actions` only. The `app/Dockerfile` base image and the Terraform provider lock have nothing proposing updates.
- A `workflow_call` reusable workflow would cut about three times as much, at the cost of carrying `build_only` and the upstream fetch as inputs. Not taken.
