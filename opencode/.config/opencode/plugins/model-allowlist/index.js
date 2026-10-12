import { Plugin } from "@opencode/plugin"

// OpenCode 2 config has no per-provider model allow-list; a model transform
// is the only place to filter the catalog. Options map a provider ID to the
// model IDs to keep; every other model of that provider is hidden.
export default Plugin.define({
  id: "dotfiles.model-allowlist",
  async setup(ctx) {
    const allowlists = Object.entries(ctx.options)
      .filter(([, modelIDs]) => Array.isArray(modelIDs))
      .map(([providerID, modelIDs]) => [providerID, new Set(modelIDs)])
    if (allowlists.length === 0) return
    await ctx.model.transform((editor) => {
      for (const [providerID, allowed] of allowlists) {
        for (const model of editor.list(providerID)) {
          if (!allowed.has(model.id)) editor.remove(providerID, model.id)
        }
      }
    })
  },
})
