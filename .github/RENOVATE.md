# Renovate Configuration

This repository uses [Renovate](https://docs.renovatebot.com/) for automated
dependency updates.

## What Gets Updated

Renovate monitors and updates:

- **Helm Charts:** ArgoCD Applications with chart versions
- **Docker Images:** Container images in Kubernetes manifests
- **GitHub Actions:** Workflow dependencies
- **Kubernetes Manifests:** API versions and resources

## Configuration

See `renovate.json` in the repository root for the complete configuration.

### Key Settings

- **Schedule:** Runs after 10pm weekdays and all weekend
- **Timezone:** America/Denver
- **Auto-merge:** GitHub Actions (patch/minor only)
- **PR Limits:** Max 5 concurrent, 2 per hour
- **Semantic Commits:** Enabled with `chore(deps):` prefix

### Package Rules

1. **Helm Charts:**
   - Minor/patch: Grouped together
   - Major: Separate PRs with `major-update` label
   - No auto-merge

1. **GitHub Actions:**
   - Minor/patch: Auto-merged
   - Major: Manual review required

1. **Docker Images:**
   - Grouped by update type
   - No auto-merge

1. **Security Patches:**
   - Auto-merged if not v0.x.x
   - Labeled as `security`

## Enabling Renovate

### GitHub App (Recommended)

1. Go to <https://github.com/apps/renovate>
1. Click **Install** or **Configure**
1. Select **Mosher-Labs** organization
1. Choose **Only select repositories**
1. Select `homelab-gitops`
1. Click **Install** or **Save**

Renovate will automatically:

- Create a dependency dashboard issue
- Scan for updates
- Create PRs based on the schedule

### Self-Hosted (Alternative)

If you prefer to run Renovate in your cluster, see the
[self-hosted documentation](https://docs.renovatebot.com/self-hosting/).

## Dependency Dashboard

Renovate creates a "Dependency Dashboard" issue that shows:

- All pending updates
- Rate-limited/errored updates
- Manually triggered updates

Find it in Issues with title: **🤖 Renovate Dependency Dashboard**

## Manual Trigger

To manually trigger Renovate:

1. Go to the Dependency Dashboard issue
1. Check the box for the dependency you want to update
1. Renovate will create a PR immediately

## PR Workflow

1. Renovate creates PR with semantic commit message
1. Pre-commit hooks run automatically
1. Review the changes (especially major updates)
1. Merge when ready - ArgoCD will auto-sync

## Ignoring Dependencies

To ignore a specific dependency, add to `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchPackageNames": ["package-name"],
      "enabled": false
    }
  ]
}
```

## Troubleshooting

### Renovate Not Running

- Check the GitHub App is installed and has access
- Verify the `renovate.json` is valid JSON
- Check the Dependency Dashboard for errors

### Too Many PRs

Adjust limits in `renovate.json`:

```json
{
  "prConcurrentLimit": 3,
  "prHourlyLimit": 1
}
```

### Failed Updates

Check the PR description for:

- Compatibility issues
- Breaking changes
- Migration guides

## References

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Configuration Options](https://docs.renovatebot.com/configuration-options/)
- [Preset Configs](https://docs.renovatebot.com/presets/)
