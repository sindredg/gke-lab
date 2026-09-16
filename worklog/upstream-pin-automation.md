# Upstream pin automation

Date: 2026-09-07 to 2026-09-16

`deploy-sky.yml` builds the sky image from a commit in [sindredg/sky](https://github.com/sindredg/sky), not from a branch. That is what makes a re-run of an old workflow run rebuild the same source. It also means the pin goes stale until someone moves it. `Watch sky` moves it, as a pull request, so the merge stays the review.

## What runs

A scheduled job at 05:00 UTC, early enough that a morning merge deploys inside the maintenance window, plus `workflow_dispatch`.

| Step | Does |
| --- | --- |
| Read the application's head and the pin | Reads `UPSTREAM_REPOSITORY` out of `deploy-sky.yml`, the pinned commit out of `.github/sky-upstream.ref`, and the upstream head through the public API. Sets `changed=false` and stops here when they match. |
| Check the commit can still be fetched | Shallow-fetches the head into a scratch clone and checks `Dockerfile` is there. A pin that cannot be fetched would fail the deploy instead of this run. |
| Open or update the bump | Writes the pin onto `bump-sky`, force-pushes with a lease, and opens the pull request if one is not already open. |

Only the first step runs when upstream has not moved. That matters for reading the run history below: a green run is not evidence that the push and the pull request work.

## Why the pin is a data file

It started inside `deploy-sky.yml` as an environment variable. GitHub rejects a push from the workflow token that touches anything under `.github/workflows`, and no permission grants it: the `workflow` scope belongs to personal access tokens. Moving the commit into `.github/sky-upstream.ref` is what lets this job propose a bump while holding no credential of its own, which is the property the pipeline is built around. Fixed in [#45](https://github.com/sindredg/k8-lab/pull/45).

## What failed

Every failure landed in the same step, `Open or update the bump`.

| Date | Run | Era |
| --- | --- | --- |
| 2026-09-07 | [34170570261](https://github.com/sindredg/k8-lab/actions/runs/34170570261) | Before the pin moved out of the workflow file, fixed by [#45](https://github.com/sindredg/k8-lab/pull/45) |
| 2026-09-08 | [34189196244](https://github.com/sindredg/k8-lab/actions/runs/34189196244) | Same |
| 2026-09-14 | [34808240569](https://github.com/sindredg/k8-lab/actions/runs/34808240569) | `--force-with-lease` had nothing to compare against, fixed by [#63](https://github.com/sindredg/k8-lab/pull/63) |
| 2026-09-15 | [34931228089](https://github.com/sindredg/k8-lab/actions/runs/34931228089) | Same |

GitHub retains the step outcome but not the logs of these runs, so the two eras are attributed from the fixes that followed them rather than quoted from output.

The lease failure is the one worth keeping. `actions/checkout` fetches `main` alone, so once `bump-sky` existed on the remote there was no local copy of it, `--force-with-lease` could not establish what it was overwriting, and it rejected every push. The fix fetches the branch first and tolerates that fetch failing, which is the expected case before the branch exists.

It sat latent for five days. The runs on 2026-09-09 through 2026-09-13 all report success, and none of them proves anything: upstream had not moved, so every one of them stopped at the first step. The bug surfaced on 2026-09-14, the first run after upstream moved and therefore the first run to reach the push at all.

## What recovery looks like

Run 2026-09-15 [34957367222](https://github.com/sindredg/k8-lab/actions/runs/34957367222) pushed the branch, then GitHub refused the pull request:

```
Could not open the pull request. Open it from
https://github.com/sindredg/k8-lab/compare/main...bump-sky, or allow
GitHub Actions to create pull requests in the repository settings.
```

The refusal is reported as a warning rather than a failure, because the branch is pushed either way and the work is not lost. An operator opened [#75](https://github.com/sindredg/k8-lab/pull/75) from that link. It carried `62f2c3a`, both required checks passed, and merging it built and rolled out.

The 2026-09-16 scheduled run found the pin already at the head and stopped at the first step, which is the steady state.

## Residual

**The automated path has never completed end to end.** GitHub is still refusing the pull request, because *Allow GitHub Actions to create and approve pull requests* is off in the repository settings. Every bump so far has been opened by hand from the link in the warning. The automation currently saves the reading, the fetch check and the commit, not the last click.

**A bump opened by the workflow would not be validated before merge.** A pull request opened with the workflow token raises no workflow events, so `ci.yml` does not run on it. The checks required on `main` would then be satisfied by the push after the merge rather than before it, which is the opposite of what [merge protection](../decisions.md#merge-protection) claims everywhere else. #75 did run both checks, but only because a person opened it. Turning the repository setting on without solving this would trade a manual click for a hole in the gate, so the two are one decision rather than two.

See [Upstream pin automation](../decisions.md#upstream-pin-automation) for the decision and its alternatives.
