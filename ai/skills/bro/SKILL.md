---
name: bro
description: Restate the last message in plain human language, with no jargon. Use when the user says /bro, 'say that simply', 'explain that in plain English', or 'what did you just say without the jargon'. Also use when they ask for a quick short high-level overview, a concise high-level overview, or concise reasoning — answer that way first.
compatibility: opencode
user-invocable: true
---

# Bro

Default replies are already supposed to sound like this. Use this skill to rewrite a reply that still came out dense, and to answer a short-overview ask the first time.

When they ask for a short overview, a high-level overview, or concise reasoning, answer that way first: a few sentences, no design dump. Do not wait for /bro.

Restate **your last message** only when they invoke /bro or ask what you just said. Drop jargon, acronyms-without-expansion, and hedging. Speak like one person talking to another — short sentences, everyday words, same facts.

## Rules

- **Rewrite the previous assistant turn**, not the whole conversation and not a new answer.
- **Same meaning.** Don't add advice, caveats, or next steps that weren't there.
- **Shorter if possible.** Cut filler; keep what mattered.
- **No "as an AI…" throat-clearing.** Just say it.
- **If the last message was already plain**, say so in one line and give a slightly tighter version.

## Example

Last message was dense:

> The reconciliation loop failed because the HelmRelease drifted — the controller couldn't apply the desired state due to a Conflict on the Deployment's generation field.

Bro version:

> Flux tried to update the app, but Kubernetes rejected it because something else had already changed the Deployment. The install is stuck until that conflict is cleared.
