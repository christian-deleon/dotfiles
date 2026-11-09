# Wait in short check-ins, then lengthen from evidence

When you wait on something — a monitor, a poll loop, a `wait`/`sleep`, a
background job, a deploy, a CI run — start with a short wait and check in
early. Never park on one long timeout "to be safe".

- **First wait is short.** Base it on the expected duration, but check in
  well before it should be done. A job that should take about 5 minutes
  gets a first check around 1–2 minutes, not 83. With no estimate, start
  at 1–2 minutes.
- **A timeout is a check-in, not a failure.** When it fires, look at the
  real state (logs, progress, status, exit code) and decide what to do
  next. Don't assume it failed or hung. Report to the user only if they
  need to know or the situation calls for it.
- **Lengthen only from evidence.** If the state shows the job is making
  progress but will clearly take longer than you guessed, set the next
  wait to match what you now know (rate of progress, time remaining).
  Each wait should be informed by the last check, not a bigger guess.
- **Stuck means stop.** If there is no progress or it is far past the
  estimate, report instead of waiting longer.
