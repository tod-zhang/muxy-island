// Muxy Island — OpenCode plugin
//
// Emits a HookEvent-compatible JSON payload to the app's Unix socket whenever
// an OpenCode session goes idle (i.e. finishes a request). The Swift side
// then surfaces that session in the notch panel, tagged with provider
// "opencode" so UI features gate themselves by ProviderCapabilities.
//
// OpenCode's plugin API is more limited than Claude Code's hooks — there's
// no equivalent of PreToolUse/PermissionRequest — so we only report the
// final "done" transition. Sessions show up in the notch after their first
// idle event, not while in-flight.

const SOCKET_PATH = "/tmp/claude-island.sock"

export const MuxyIslandPlugin = async ({ client }) => ({
  event: async ({ event }) => {
    if (event.type !== "session.idle") return

    const sessionID = event?.properties?.sessionID
    if (!sessionID) return

    let lastMessage = null
    try {
      const result = await client.session.messages({
        path: { id: sessionID },
        query: { limit: 3 },
      })
      const messages = result.data || []
      const lastAssistant = [...messages]
        .reverse()
        .find((m) => m.info && m.info.role === "assistant")
      if (lastAssistant) {
        const textParts = (lastAssistant.parts || []).filter(
          (p) => p.type === "text",
        )
        const text = textParts.map((p) => p.text || "").join("")
        if (text) lastMessage = text.replace(/\s+/g, " ").slice(0, 500)
      }
    } catch {}

    // Muxy injects these so we can route clicks on the session row straight
    // back to the pane that's running OpenCode. Missing outside of Muxy.
    const muxyPaneId = process.env.MUXY_PANE_ID || null
    const muxyProjectId = process.env.MUXY_PROJECT_ID || null
    const muxyWorktreeId = process.env.MUXY_WORKTREE_ID || null

    const payload = {
      session_id: sessionID,
      cwd: process.cwd(),
      // We reuse Claude Code's event/status vocabulary so SessionStore can
      // treat OpenCode sessions without a special case. "Stop" +
      // "waiting_for_input" is the clean "I'm done, your move" transition.
      event: "Stop",
      status: "waiting_for_input",
      pid: process.pid,
      tty: null,
      provider: "opencode",
      message: lastMessage,
      muxy_pane_id: muxyPaneId,
      muxy_project_id: muxyProjectId,
      muxy_worktree_id: muxyWorktreeId,
    }

    try {
      const { createConnection } = await import("net")
      const conn = createConnection({ path: SOCKET_PATH })
      conn.on("error", () => {})
      conn.write(JSON.stringify(payload), () => conn.end())
      await new Promise((resolve) => {
        conn.on("close", resolve)
        setTimeout(resolve, 3000)
      })
    } catch {}
  },
})
