# Delegate searches and bulk reads to the scout subagent

Broad searches and large reads are billed at the session model's rate — on a
premium model that is the most expensive way to run `grep`. Delegate that work
to the `scout` subagent (pinned to a cheaper model) and keep the conclusion,
not the file dumps.

Delegate when:
- Answering requires searching across many files or directories ("where is X
  handled", find-all-usages, naming-convention sweeps).
- A file, log, or command output to read is more than a few hundred lines.
- Several independent lookups could run at once — spawn one scout per lookup,
  in parallel.

Stay inline when the exact file and location are already known and the read is
small; spawning an agent there costs more than it saves.

Once delegated, wait for the scout's answer — never re-run the same search
inline.

The scout finds and locates; it does not decide. Treat its `file:line` +
excerpt as evidence to reason over yourself, not as a conclusion to adopt
untouched — read the excerpt, not just the claim built on top of it. If a
finding is surprising, negative ("X doesn't exist/isn't handled anywhere"),
or will drive an irreversible action, open the cited location yourself before
acting on it. A cheap model's summary can miss or misstate what it found;
verifying the load-bearing ones is cheap insurance, not wasted delegation.
