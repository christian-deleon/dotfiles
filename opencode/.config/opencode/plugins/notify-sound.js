export const NotifySound = async ({ $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        await $`paplay /usr/share/sounds/freedesktop/stereo/message-new-instant.oga`.quiet()
      }
    },
  }
}
