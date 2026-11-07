# Personal Gitea (`gitea` MCP server, `tea` CLI)

Applies only where the `gitea` MCP server or `tea` is installed.

- **Personal projects only.** This Gitea is the user's self-hosted server for
  personal repos. Never use it for work, and never treat work repos as living
  there.
- **Netbird only.** The server is reachable only over the user's self-hosted
  Netbird network. If a call times out, refuses the connection, or the host
  does not resolve, the Netbird client is most likely disconnected. Stop and
  tell the user to reconnect Netbird. Do not retry in a loop, switch tools, or
  go looking for another route.
- **The token is the user's own account**, so Gitea's `main` branch protection
  does not stop agents. Work on a branch, push it, and open a pull request.
  Never push to or merge into `main`.
- **MCP first, `tea` second.** Use the MCP tools by default. Fall back to
  `tea` when the MCP server lacks the operation. Mutations (create, merge,
  delete, settings, releases) follow `live-mutations.md`.
