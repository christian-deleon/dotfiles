#!/usr/bin/env bash
# Skip fingerprint auth when laptop lid is closed (e.g. docked mode)
# Installed to /usr/local/bin/ by install.sh and wired into PAM
# PAM calls this before pam_fprintd.so — exit 0 (lid open) allows
# fingerprint, exit 1 (lid closed) skips to password
grep -q open /proc/acpi/button/lid/LID/state
