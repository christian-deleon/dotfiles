# Windows Bootstrap (`windows/`)

Out-of-band entry point that runs on Windows itself, before WSL exists. **Not part of `install.sh` or `dot`.**

`windows/bootstrap.ps1` does:

1. Verifies winget is available.
2. `winget install Alacritty.Alacritty`.
3. `winget install DEVCOM.JetBrainsMonoNerdFont`.
4. **Downloads `windows/alacritty.toml` from GitHub** and writes it to `%APPDATA%\alacritty\alacritty.toml`. This is the Windows-tuned Alacritty config — the key thing it does is set `[terminal.shell]` to `wsl.exe -d Ubuntu-26.04` so Alacritty auto-launches into Ubuntu instead of PowerShell. Downloaded (not embedded inline) so the config file stays independently editable and the `irm | iex` invocation can fetch it without a local checkout.
5. **WSL setup (two-phase with readiness probe):**
   - Probes WSL with `wsl --status` and parses the output text — `wsl.exe` returns exit 0 even when its operations didn't take effect, so exit code alone is unreliable. The probe matches **only WSL2-specific blockers** (`WSL2 is unable to start` or any mention of `Virtual Machine Platform`) and treats those as not-ready. WSL1-only warnings (e.g. `Please enable the "Windows Subsystem for Linux" optional component to use WSL1`) are deliberately ignored, since this script always installs a WSL2 distro — those warnings appear in normal post-VMP-enable states where WSL2 is fully functional, and would otherwise produce a false-negative readiness result.
   - If WSL is ready, skip to step 6.
   - Otherwise run `wsl --install --no-distribution` to enable features, then re-probe. If it's *still* not ready, features were just enabled and a reboot is required — script stops here with a clear reboot message, *without* attempting the distro install (avoids the wasted Ubuntu rootfs download + failed VM creation that happens if you try to install the distro before VM Platform is active).
6. Probes for existing Ubuntu-26.04 registration via `wsl --list --quiet`; if already registered, skips the install (treats it as success). Otherwise runs `wsl --install --distribution Ubuntu-26.04 --no-launch` and **verifies the distro is actually registered afterward** by re-probing — `wsl --install --distribution` can return exit 0 while only enabling features (printing "Changes will not be effective until the system is rebooted") on a machine where the WSL feature was newly turned on by an earlier step, so exit-0 alone isn't enough. If exit 0 but the distro isn't registered, treat the run as reboot-required and fall through to the reboot message. The pre-probe also catches the case where a *previous* failed run registered the distro before crashing at VM creation — re-running would otherwise hit `ERROR_ALREADY_EXISTS` and misreport as a failure. `WSL_UTF8=1` is set when invoking `wsl --list` so the output is UTF-8 instead of the default UTF-16.

After the script, the user finishes first-time Ubuntu user setup manually, then clones the repo inside Ubuntu and runs `./install.sh` — the normal Linux flow.

**No admin gate.** The script doesn't enforce elevation. Individual steps that need elevation (typically `wsl --install` on a system where WSL features have never been enabled) will trigger their own UAC prompts. winget at user scope and font install don't need admin.

**Idempotent — safe to run twice.** Three terminal states the script can reach:

- **Reboot required** (features were just enabled, VM Platform pending) — prints reboot message and the `irm | iex` one-liner to re-run. The distro install was *not* attempted, so re-running after reboot does it cleanly.
- **Distro install failed** (most commonly BIOS virtualization off, or rarer post-reboot edge cases) — prints likely causes and tells you to fix and re-run.
- **Success** — prints next steps for inside Ubuntu.

winget steps no-op when already installed; the WSL probe correctly skips redundant feature-enable calls on a working machine, so re-running is fast on a healthy box.

**Uses `return`, not `exit`, for early-exit paths.** The script is intended to be run via `irm | iex`, which evaluates it in the current PowerShell session. `exit` would close the user's PowerShell window; `return` exits only the iex'd code.

**Invocation.** Primary path is the GitHub raw `irm | iex` one-liner (see README); the script runs fine without a local checkout because it references no template files. A local checkout still works — `bootstrap.ps1` is self-contained.

**Hard split, by design:** `bootstrap.ps1` only does things that **cannot** be done from inside WSL (winget, WSL distro install, Windows-side configs). Anything that *can* be done from inside WSL stays in `install.sh` / `dot`. Don't let bootstrap.ps1 grow tendrils into the Linux side.

**Dual Alacritty configs.** `windows/alacritty.toml` and `alacritty/.config/alacritty/alacritty.toml` are two separate files and will drift. The Linux one has a `general.import` line for an Omarchy theme path that doesn't resolve on Windows; the Windows one has a `[terminal.shell]` block pointing at `wsl.exe -d Ubuntu-26.04`. Mirror font/padding/key changes manually. Because `bootstrap.ps1` fetches `windows/alacritty.toml` from GitHub at runtime (not from a local checkout), config changes must be pushed to `main` before they take effect on a re-run.

**Currently out of scope** (was considered, explicitly deferred — may be added later):

- **Windows Terminal install + settings.json** — settings.json is handled by `scripts/tools/install-windows-terminal.sh` from inside WSL after first WT launch (it needs the WSL profile GUID that WT auto-generates). Installing WT itself is also deferred.
- **1Password install + SSH agent → WSL forwarding** — agent forwarding needs an `npiperelay` shim + `socat` listener in WSL. Whole pipeline deferred.
- **`%USERPROFILE%\.wslconfig`** — memory/cpu caps for the WSL VM. Deferred; rely on WSL defaults.
- **Auto-cloning the repo inside WSL** — first-time user creation + private-submodule auth make this brittle. One paste inside Ubuntu is simpler.

**Ubuntu version is hard-coded to Ubuntu-26.04** in `bootstrap.ps1`. Single source of truth for now.
