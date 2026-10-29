---
name: grab-issue
description: Pick and reserve a ready GitHub issue, wait for dependencies if needed, then implement it.
---

# Grab an issue

Handle one issue when the user invokes `/grab-issue` or asks to grab an issue to implement. This request authorizes reservation, dependency monitoring and implementation.

Read the current project's `AGENTS.md` and its issue tracker conventions when present. Resolve the current repository using `gh repo view --json nameWithOwner --jq .nameWithOwner`. Use that explicit repository in every request, including from worktrees and subagents. Resolve the `ready-for-agent` and `reserved-by-agent` label roles from `docs/agents/labels.json` when present, otherwise use those names. Locate the project's `implement` skill or the installed shared skill before reserving work.

## Select and reserve

1. Fetch every page of open issues with the ready label. Exclude pull requests and issues carrying the reserved label. For example:

   ```sh
   set -o pipefail
   gh api --paginate --slurp "repos/$repo/issues?state=open&per_page=100" |
     jq --arg ready "$ready_label" --arg reserved "$reserved_label" \
       '[.[][] | select(has("pull_request") | not) |
         select(any(.labels[]; .name == $ready)) |
         select(all(.labels[]; .name != $reserved))] | sort_by(.number)'
   ```

2. Read each candidate's native Relationships dependency status using REST `issue_dependencies_summary.blocked_by` or GraphQL `issueDependenciesSummary.blockedBy`. Zero means unblocked. Fetch the individual issue if its list response omits the summary. A missing, malformed or unreadable count is unknown; resolve it before selecting. `totalBlockedBy` includes closed blockers and cannot determine readiness. Body checklists and labels do not establish this status. See [GitHub's dependency summary reference](https://docs.github.com/en/graphql/reference/issues#issuedependenciessummary).
3. Prefer an unblocked candidate, choosing the lowest issue number for stable ordering. Only when every candidate is blocked, choose the lowest issue number among them. If none remain, report that no unreserved ready issue is available and stop.
4. Immediately refetch the chosen issue's state, labels and dependency summary. Repeat selection if it closed, lost readiness, gained a reservation or changed blocking status.
5. Create the reserved label if absent. For an unblocked issue, add the reserved label and remove the ready label in the same call: `gh issue edit "$number" --repo "$repo" --add-label "$reserved_label" --remove-label "$ready_label"`. For a blocked issue, add only the reserved label: `gh issue edit "$number" --repo "$repo" --add-label "$reserved_label"`. Preserve unrelated labels. Record whether this run removed readiness. Refetch to verify the expected labels and current blocker count. Report the selected issue's number, title and URL. Label updates are not an atomic lock. If another agent's claim is detected, resolve ownership before implementing.

A failed API read or reservation stops implementation. Treat GraphQL errors as failures even when the command exits successfully.

## Implement or wait

If blocked, follow [references/watch.md](references/watch.md), passing the actual reserved label name. Keep the same reservation while waiting. The watcher reports when the native open blocker count becomes zero. The parent independently refetches state, labels and dependencies before implementing. Require the issue to remain open, reserved by this run and unblocked. If it becomes blocked again, resume monitoring the same issue. If it closes or loses its reservation, stop and report the change.

When unblocked, ensure the reserved label is present and remove the ready label before invoking `/implement` with the full issue URL. This also applies after the watcher reports an issue unblocked. Verify the resulting labels; absence of the ready label is expected after reservation and does not prevent implementation. Use the Skill tool when available; otherwise read and follow the located `implement/SKILL.md`. Follow the project's setup and landing scripts. The parent implements; the watcher only reports status.

After completing implementation, follow the project's issue completion convention and remove this run's reservation. On cancellation, stop the watcher and release this run's reservation if implementation has not begun. Restore the ready label if this run removed it and the issue remains open without a new triage state. On an implementation or monitoring failure, report the issue URL, reservation status and reason so work can be resumed deliberately.
