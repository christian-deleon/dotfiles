---
name: my-command
description: One-sentence summary of what this user-only skill does. Invoked via /my-command.
compatibility: opencode
disable-model-invocation: true
argument-hint: "[args description]"
allowed-tools: Bash
---

[Optional preamble for the model — context for the upcoming task.]

[Pre-baked shell output goes here:]

```!
git log --oneline -10
```

```!
git diff --staged
```

[The actual ask, parameterized with $ARGUMENTS:]

Now [do the thing] for: $ARGUMENTS

[Any additional constraints or output-format requirements.]
