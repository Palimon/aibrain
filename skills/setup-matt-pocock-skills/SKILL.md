---
name: setup-matt-pocock-skills
description: "Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills."
disable-model-invocation: true
---

# Setup Matt Pocock's Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker**: where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels**, when enabled: the strings used for the five canonical triage roles
- **Domain docs**: where `GLOSSARY.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

Reuse choices already supplied by the user or the project's documentation. Ask only about unresolved choices.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config`: is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root: does either exist? Is there already an `## Agent skills` section in either?
- `GLOSSARY.md` and `GLOSSARY-MAP.md` at the repo root
- `docs/decisions/` and any `src/*/docs/decisions/` directories
- `docs/agents/`: does this skill's prior output already exist?
- `.scratch/`: a sign that a local-markdown issue tracker convention is already in use
- Which installed skills need labels? `triage` uses two categories and five states; `to-spec` needs `ready-for-agent` even without `triage`. Check sibling skill folders and available skills. Skip label setup only when the repo explicitly disables labels or no installed skill needs them.
- Monorepo signals: a `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, or a populated `packages/*` with its own `src/`. These are present only in a genuinely large multi-package repo; their absence means single-context, which is almost every repo.

### 2. Present findings and ask

Summarise what's present and what's missing. Then take the sections in order. One section, one answer, then the next.

Lead each section with the recommended answer so the user can accept it in a word. Give a one-line explainer only when the choice genuinely branches; skip the section entirely when exploration already settled it (Section B when labels are disabled or no installed skill needs them, Section C when there's no monorepo).

**Section A: Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-tickets`, `triage`, and `to-spec` read from and write to it. They need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise (or if the user prefers), offer:

- **GitHub**: issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab**: issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown**: issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.): ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

Record the choice in `docs/agents/issue-tracker.md`. The GitHub and GitLab templates carry a "PRs as a request surface" flag, defaulted **off**. Leave it off and don't raise it: a user who wants external PRs in the triage queue can flip the flag in the file later.

**Section B: Label vocabulary.** Configure only the roles needed by the installed skills. With `triage`, configure category roles `bug` and `enhancement` and state roles `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. With `to-spec` alone, configure `ready-for-agent`. An explicit project opt-out of labels skips this section.

When this section applies, ask exactly one question:

> Do you want to keep the default label names? (recommended: **yes**)

Each default label string equals its role name. Start from [labels.json](labels.json), retaining only the roles needed. On **yes**, keep those names. Only if the user says no, usually because their tracker already uses other names (e.g. `bug:triage` for `needs-triage`), collect the overrides so skills apply existing labels instead of creating duplicates. Preserve prior color and description choices when updating an existing configuration.

**Section C: Domain docs.** Default to **single-context** (one `GLOSSARY.md` + `docs/decisions/` at the repo root). This fits almost every repo; write it without asking.

Offer **multi-context** (a root `GLOSSARY-MAP.md` pointing to per-context `GLOSSARY.md` files) only when exploration found monorepo signals. Then confirm which layout they want.

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see step 4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/domain.md`, and, when Section B ran, `docs/agents/triage-labels.md` and `docs/agents/labels.json`

Let them edit before writing.

### 4. Write

**Pick the file to edit:**

- Edit the repo's canonical `AGENTS.md`. Create it if neither instruction file exists.
- If only `CLAUDE.md` exists, follow the repo's migration conventions before changing which file is canonical.
- When both exist, put the configuration in `AGENTS.md` and keep `CLAUDE.md` as a pointer to it. Avoid duplicate configuration.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Include the `### Triage labels` sub-block and write `docs/agents/triage-labels.md` and `docs/agents/labels.json` only when Section B ran. Otherwise omit them. Preserve any existing instruction that disables labels.

`labels.json` is the authoritative array of `{role, name, color, description}` definitions. The Markdown document explains the roles and points to that array for actual label names, avoiding a second mapping to maintain.

When Section B ran on GitHub, run `aibrain-labels <repo-root>` if available. It creates missing labels and repairs configured colors and descriptions; aibrain bootstrap repeats this for configured checkouts. If the helper is absent, use `gh label create --force` for the manifest's labels. On GitLab, reconcile the configured definitions through `glab`. Local files use the mapping for status and category metadata. Preserve unrelated labels and existing issues.

Then write the docs files using the seed templates in this skill folder as a starting point:

- [issue-tracker-github.md](./issue-tracker-github.md): GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md): GitLab issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md): local-markdown issue tracker
- [triage-labels.md](./triage-labels.md): label mapping (only when Section B ran)
- [labels.json](./labels.json): label definitions and bootstrap provisioning manifest (only when Section B ran)
- [domain.md](./domain.md): domain doc consumer rules + layout

For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

### 5. Done

Tell the user the setup is complete and which engineering skills will now read from these files. Mention they can edit `docs/agents/*.md` directly later; re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.
