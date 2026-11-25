#!/usr/bin/env python3
"""Claude Code Stop hook: an agent starts a sign-in itself instead of handing the user a command to run.

A sign-in on another computer (a device-code login, `tailscale up`, `gh auth login`, `codex login`, a
project's sign-in script) can almost always run over ssh in the background, with its output in a file:
the agent reads the address and code from the file and gives the user only those, then does the follow-up
itself. Asking the user to log in to a computer to run the command is the failure this hook catches.

When the final message has a line that tells the reader to run a sign-in command, the hook blocks the stop
once with a reason, and the agent rewrites its answer or starts the sign-in. A line in the past tense
("I ran", "started") and a line about a sign-in the agent runs from here are left alone. With
stop_hook_active set, the agent has already been told once, so the hook lets it stop. If the hook itself
fails, Claude Code stops anyway.
"""
import json
import re
import sys

# The sign-in commands: device-code and browser logins of common CLIs, and any sign-in or login script.
# Case-sensitive, so prose such as "the Codex login" is not a command.
SIGN_IN = re.compile(
    r"(?<![\w-])(?:"
    r"tailscale\s+(?:up|login)\b|gh\s+auth\s+(?:login|refresh)\b|codex\s+login\b|claude\s+(?:auth\s+)?login\b"
    r"|op\s+signin\b|op\s+account\s+add\b|(?:docker|podman|az|wrangler|vercel|netlify|fly|flyctl|npm)\s+login\b"
    r"|gcloud\s+auth\s+(?:login|application-default\s+login)\b|(?:huggingface-cli|hf\s+auth)\s+login\b"
    r"|[\w./~-]*(?:sign[-_]?in|log[-_]?in)\.(?:sh|py|ps1)\b|--device-auth\b|device-auth\b)")
# A sign-in that the agent itself starts from here; naming it hands the user nothing to run.
REMOTE = re.compile(r"(?i)remote[-_]sign[-_]?in")
# The reader is told to run it: an imperative, or "you" with a verb of doing.
IMPERATIVE = re.compile(
    r"(?i)(?:^\s*|[.:;!?)\]*>-]\s+|^\s*(?:\d+[.)]|[-*])\s+|\b(?:please|then|now|just|first|next)\s+|,\s+)"
    r"(?:run|execute|type|enter|paste|start|launch|do|ssh)\b"
    r"|\byou(?:'ll| will| would)?\s+(?:need\s+to|have\s+to|must|should|can|could)\s+(?:run|execute|type|ssh|log\s+in|sign\s+in)\b"
    r"|\b(?:log|sign)\s+in\s+(?:to|as|on)\s+\S+\s+and\s+run\b"
    r"|\b(?:until|once|when|after)\s+you\s+run\b|\b(?:either|or)\s+run\b"
    r"|\bneeds?\s+you\s+to\s+(?:run|log\s+in|sign\s+in)\b"
    r"|\b(?:for|from)\s+you:\s"
    r"|^\s*(?:on|from)\s+\S+,\s*(?:run|type|execute)\b")
# The agent's own past or ongoing work, not a request.
PAST = re.compile(r"(?i)\b(?:I|we)\s+(?:ran|started|re-?ran|have\s+run|am\s+running|'m\s+running|will\s+run|'ll\s+run)\b|\b(?:ran|was\s+run)\b")


def handoff(message):
    """The first line of the message that tells the reader to run a sign-in command, or None."""
    for line in message.splitlines():
        if not SIGN_IN.search(line) or REMOTE.search(line) or PAST.search(line):
            continue
        if IMPERATIVE.search(line):
            return line.strip()
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if event.get("stop_hook_active"):
        return
    line = handoff(event.get("last_assistant_message") or "")
    if not line:
        return
    reason = (
        "Your final message asks the user to run a sign-in: " + line[:200] + "\n"
        "Start it yourself instead: over ssh, in the background, with its output redirected to a file (a pipe can "
        "hold the code line back for minutes). Read the address and code from the file and give the user only "
        "those, or the one browser step, then do the follow-up yourself (converge, check). Use the project's own "
        "remote sign-in command when it has one. Ask the user to touch a computer only for a password only they "
        "have, a physical action or a decision; if that is the case here, say so plainly and stop again."
    )
    print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    main()
