import { $ } from "bun"

const HOOKS_DIR = `${process.env.HOME}/.dotfiles/ai/hooks`

export const NotifySound = async () => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const payload = JSON.stringify({ cwd: process.cwd() })
        await $`echo ${payload} | ${HOOKS_DIR}/stop_notify.sh`.quiet()
      }
    },
  }
}
