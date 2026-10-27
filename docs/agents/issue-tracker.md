# Issue tracker

Specs and implementation tickets live in this checkout's GitHub Issues. Use `gh` from the repo root; it infers the target from the origin remote.

- Create an issue with `gh issue create --title "..." --body-file <file>`.
- Read an issue with `gh issue view <number> --json number,title,body,labels,comments`.
- List issues with `gh issue list --state open --json number,title,body,labels`; filter by `--label` when needed.
- Apply or remove configured labels with `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- Write multiline comments to a temporary file and use `gh issue comment <number> --body-file <file>`.
- Close a resolved issue with `gh issue close <number>`.

When a skill says to publish to the tracker, create an issue. When it says to fetch a ticket, read the referenced issue. Publishing a completed spec applies the configured `ready-for-agent` label.

Label roles and their interpretation are in [triage-labels.md](triage-labels.md). [labels.json](labels.json) is the authoritative mapping and provisioning manifest. Run `aibrain-labels .` after changing it; bootstrap also synchronizes configured checkouts.

**PRs as a request surface: no.** Triage discovery covers issues. An explicitly named pull request can still be triaged. A bare reference may identify either kind of item; check with `gh pr view <number>` and fall back to `gh issue view <number>`.

Personal planning and fleet notes remain in the private personal layer. Public issues must satisfy this repo's privacy rules.
