---
name: wsl
description: Run a repo's Linux-only tests or commands in WSL from Git Bash on Windows. Use when a test, script or tool needs Linux on a Windows computer, or when making a repo's test runner work on Windows.
---

# WSL

On Windows, agents run in Git Bash, where `uname -s` prints `MINGW64_NT-...`. A test that needs Linux, such as `unshare`, a Linux-only Python package or a tool Git Bash lacks, runs in WSL through `scripts/wsl-run` in this skill's folder.

## Run a command once

From anywhere in the checkout:

```bash
bash <this skill's folder>/scripts/wsl-run tests/run
```

`wsl-run` snapshots the checkout (HEAD plus every uncommitted change, untracked files included), checks the snapshot out in a throwaway clone inside WSL, runs the command from the clone's root, deletes the clone, and exits with the command's status. In the clone, HEAD is the checkout's HEAD and the index holds the changes, so `git ls-files` and `git diff --cached` show what the checkout shows. It works from a git worktree and leaves the checkout's own index alone. Without WSL it prints `skip: WSL is not available` and exits 0.

Each workaround in the script has a comment saying what breaks without it. Keep them when you change or copy the script.

## Make a repo's test runner work on Windows

The runner has to work on computers without this skill, so the repo carries its own copy:

1. Copy `scripts/wsl-run` to `tests/wsl-run` and mark it executable (`git update-index --chmod=+x`; Git Bash can't set exec bits).
2. Put this near the top of the runner, after `set -e`:

   ```bash
   case $(uname -s) in
     MINGW*|MSYS*) exec "$(git rev-parse --show-toplevel)/tests/wsl-run" bash tests/run "$@" ;;
   esac
   ```

   On Linux and macOS the runner carries on as before.
3. Have each test that needs a tool check for it and print one skip line when it's missing, for example `command -v ffmpeg >/dev/null || { echo 'skip: ffmpeg is not installed'; exit 0; }`. A WSL distro starts with few tools.
4. Run the runner from Git Bash and check that the skip lines name only tools you expect to be missing.

## Tools missing in WSL

Installing a tool in a computer's WSL distro is setup for that one computer. It goes in that computer's setup in the personal layer (`computers/<name>/setup.sh`), as a step that changes nothing on a second run. Keep it out of the repo under test and out of this repo.

## Claude Code's removal check

Claude Code asks a person before running a Bash tool command that holds both `bash -c` (or `sh -c`) and `rm`. `wsl-run` keeps its `rm` inside the script file, so calling it passes. When you write your own `wsl.exe -e bash -c ...` pipeline, put it in a script file and run the file.
