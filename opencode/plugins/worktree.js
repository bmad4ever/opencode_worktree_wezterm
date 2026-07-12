export const WorktreePlugin = async ({ client }) => {
  try {
    await client.app.log({
      body: {
        service: "worktree-commands",
        level: "info",
        message: "Loaded /startworktree and /mergeworktree commands",
      },
    })
  } catch {
    // Logging is best-effort only.
  }

  return {}
}
