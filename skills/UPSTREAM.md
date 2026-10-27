# Selected upstream skills

Source: [mattpocock/skills](https://github.com/mattpocock/skills), commit [`5beb35b040e3de97e54fa9e386d7e42d15c295c2`](https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2), retrieved 2026-10-26. These are editable copies under the MIT license in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Selection and dependencies

Each upstream path below is relative to its `skills/` folder. Locally, each skill lives directly under this folder. Copy the complete skill folder, including reference files and `agents/openai.yaml`.

| Requested skill | Upstream path | Required skills |
|---|---|---|
| `grill-with-docs` | `engineering/grill-with-docs` | `grilling`, `domain-modeling` |
| `improve-codebase-architecture` | `engineering/improve-codebase-architecture` | `codebase-design`, `grilling`, `domain-modeling` |
| `to-spec` | `engineering/to-spec` | Per-project configuration from `setup-matt-pocock-skills` |
| `implement` | `engineering/implement` | `tdd`, `code-review` |
| `retro` | `engineering/retro` | `writing-for-agents` |
| `grill-me` | `productivity/grill-me` | `grilling` |
| `handoff` | `productivity/handoff` | None |
| `triage` | `engineering/triage` | `grilling`, `domain-modeling`; tracker and label configuration |

The supporting skills are installed too:

| Supporting skill | Upstream path | Further requirements |
|---|---|---|
| `grilling` | `productivity/grilling` | Subagent support for environment exploration |
| `domain-modeling` | `engineering/domain-modeling` | Its glossary and decision-record format files |
| `codebase-design` | `engineering/codebase-design` | `DEEPENING.md`, `DESIGN-IT-TWICE.md`; subagent support for alternative designs |
| `tdd` | `engineering/tdd` | `codebase-design`, `tests.md`, `mocking.md` |
| `code-review` | `engineering/code-review` | Per-project tracker configuration; subagent support for independent reviews |
| `writing-for-agents` | `productivity/writing-for-agents` | `SKILL-MECHANICS.md` |
| `setup-matt-pocock-skills` | `engineering/setup-matt-pocock-skills` | Its tracker, domain and label templates |

`improve-codebase-architecture` also includes `HTML-REPORT.md`. Every installed skill includes its upstream `agents/openai.yaml`; user-invoked skills keep `allow_implicit_invocation: false`.

`triage` was added to the selection when enabling the issue workflow. It includes `AGENT-BRIEF.md` and `OUT-OF-SCOPE.md`; its skill dependencies were already installed. There are 15 selected and supporting skill folders in total.

Mentions of other commands in templates or examples are not dependencies. This selection does not require `to-tickets`, `implement-spec`, `ask-matt`, or the rest of the upstream plugin.

## Local adaptations

- Preserve the existing `grill-me` and `grill-with-docs` wrappers, which explain skill loading in Claude Code and Codex. Add the same fallback to the imported skills that instruct the agent to call the Skill tool: when that tool is absent, read and follow the named `SKILL.md`.
- Preserve the existing domain-modeling wording, `docs/decisions/` directory and `DECISION-RECORD-FORMAT.md` filename. Align the architecture-review and setup instructions and templates with that directory. Existing projects' documented layouts still take precedence.
- The setup command writes its configuration to the canonical `AGENTS.md`, consistent with this setup's instructions. The upstream version prefers `CLAUDE.md` when both exist.
- Setup provisions the roles needed by the installed skills: two categories and five states for `triage`, or `ready-for-agent` for `to-spec` alone. This fixes upstream's omission of categories and its label-setup dependency on `triage`. Explicit project opt-outs remain supported; otherwise `to-spec` requires its mapping and applies the configured label.
- Setup writes a `labels.json` manifest alongside its role documentation. The local `aibrain-labels` helper and bootstrap synchronize that manifest with GitHub. This helper and manifest template are aibrain additions. The local-file tracker template makes triage status conditional on enabling triage.

The rest of the upstream workflows are retained, including their confirmation points and use of subagents. Installing a skill does not run it.

## Before using the engineering workflow

Run `setup-matt-pocock-skills` in each project where you want tracker integration. Installing these skills globally does not choose a tracker for every project. The setup command prepares a pointer in the project's `AGENTS.md` and configuration under `docs/agents/`:

- `issue-tracker.md` describes the tracker and how to read and publish issues.
- `domain.md` describes glossary and decision-record locations and how to read them.
- `triage-labels.md` explains the configured roles. `labels.json` holds their authoritative names, colors and descriptions. Setup creates these for installed skills that need labels, including `to-spec` without `triage`.

Choose these per-project settings when starting that workflow. Keep personal project configuration in private repos. Glossaries and decision records are created only when there is something to record.

This repo is configured for GitHub Issues, the seven default category and state roles, one root glossary, and `docs/decisions/`. See its root `AGENTS.md` and `docs/agents/`.

GitHub workflows use the `gh` CLI already provided by bootstrap; choosing GitLab requires `glab`. Local Markdown needs no tracker CLI. The architecture report uses Tailwind and Mermaid from CDNs, so viewing it as designed needs network access. No Node packages are required to install or load this selection.

On every run, bootstrap synchronizes GitHub labels for checkouts directly under `~/Projects/` that contain `docs/agents/labels.json`. This needs GitHub Issues write access. `aibrain-labels <project>` runs the same reconciliation on demand, and `--check` reports drift without writing. Missing manifests and non-GitHub origins are skipped. Unrelated labels and existing issues are preserved.

## Updates and files outside the skills

Bootstrap links these committed folders into each agent's skill directory; it does not fetch updates from upstream. A personal-layer skill with the same name overrides the engine copy.

To update:

1. Fetch a new upstream revision into a temporary checkout. Compare the selected skills, then trace their skill calls and local reference links again.
2. Copy the selected folders and their complete dependencies. Reapply the local adaptations above. Review upstream changes before committing them.
3. Update this source revision and `THIRD_PARTY_NOTICES.md`. Commit on local `main`, run `tests/bootstrap-test.sh all`, push, then run `bootstrap.sh` on the real machine.

The upstream root `AGENTS.md`, `.agents/`, plugin manifests, `scripts/link-skills.sh`, package files and release tooling belong to developing or distributing that repository. They are not required for these copied skills. Bootstrap already handles linking. The upstream `docs/engineering/` and `docs/productivity/` pages are optional human-facing guides; consult them online rather than copy another set of documentation to maintain.
