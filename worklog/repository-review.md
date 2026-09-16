# Repository review

Date: 2026-09-16

## Done

- Corrected the sky source decision: the repository is `sindredg/sky`, and the pin lives in `.github/sky-upstream.ref`. ([#77](https://github.com/sindredg/k8-lab/pull/77))
- Added a trailing newline to 30 files, removed the unused `plan.md` ignore rule, fixed two typos, and completed the load test run table. ([#77](https://github.com/sindredg/k8-lab/pull/77))
- Recorded the `Watch sky` workflow in a decision and a worklog, with its two open gaps. ([#78](https://github.com/sindredg/k8-lab/pull/78))
- Cut code comments from 385 lines to 181, and removed the ones that restated the code. ([#79](https://github.com/sindredg/k8-lab/pull/79))
- Fixed two stale comments: the HPA target is 245m, not 70m, and there is no "Slice 2". ([#79](https://github.com/sindredg/k8-lab/pull/79))
- Added the `Docs and scripts` CI job, which checks links, anchors and screenshots and runs shellcheck. It is required on `main`. ([#80](https://github.com/sindredg/k8-lab/pull/80))
- Added Dependabot for GitHub Actions, and merged its first two bumps. ([#80](https://github.com/sindredg/k8-lab/pull/80), [#81](https://github.com/sindredg/k8-lab/pull/81), [#82](https://github.com/sindredg/k8-lab/pull/82))
- Moved the namespace-wide manifests to `kubernetes/platform/`. ([#83](https://github.com/sindredg/k8-lab/pull/83))
- `Deploy` now runs when `kubernetes/nginx/` changes. ([#84](https://github.com/sindredg/k8-lab/pull/84))
- Made kube-linter blocking, set `unhealthyPodEvictionPolicy: AlwaysAllow` on both budgets, and gave nginx a read-only root filesystem. ([#85](https://github.com/sindredg/k8-lab/pull/85))
- Verified the budgets and read-only nginx in the cluster. ([#86](https://github.com/sindredg/k8-lab/pull/86))

## Open

- 18 untracked screenshots from 2026-09-15 in `images/`, not yet reviewed.
- `Watch sky` still cannot open its pull request, and a pull request opened by the workflow token would skip CI.
- `Deploy sky` has not run on the new Docker actions.
- `HTTPRoute/nginx-https-redirect` keeps its old name in `kubernetes/platform/`.
