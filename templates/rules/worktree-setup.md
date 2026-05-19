# Git Worktree Setup

Worktrees are stored in the directory configured under `worktree.dir` in `.claude/sillok/workflow.config.json` (default `.worktrees`).

## After creating a worktree

When `/sillok-start` creates a new feature worktree, it copies the files listed in `worktree.copyFiles` (in the same config file) from the main worktree into the new worktree. These are typically gitignored configuration files — secrets, build configs, generated credentials — that the project needs but git does not track.

| File pattern | Typical purpose |
| ------------ | --------------- |
| `.env`, `.env.*` | Local environment variables |
| `eas.json` | Expo Application Services config |
| `google-services.json` | Android Firebase config |
| `GoogleService-Info.plist` | iOS Firebase config |
| `<project>.config.local.js` | Per-developer overrides |

Edit `worktree.copyFiles` to add or remove patterns specific to your project. The list is read at runtime by `setup-feature-worktree.sh`.

## Example

```bash
# After: git worktree add .worktrees/my-feature my-feature
# (sillok runs this automatically via /sillok-start)
cd .worktrees/my-feature
<install command from workflow.config.json>
```

The install command comes from the `install` field in `workflow.config.json`. Empty `install` means "no install step" — fine for pure-config repos.
