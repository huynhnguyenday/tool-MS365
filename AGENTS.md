# Teams Channel Manager — Project Instructions

## Purpose

This repository contains a Windows-local PowerShell application for managing Microsoft Teams and private-channel membership through Microsoft Graph.

- The UI is `private-channel-members.html`.
- The local HTTP server and Graph API layer are in `Start-PrivateChannelMembersUI.ps1`.
- `Open-PrivateChannelMembersUI.cmd` is the normal launcher.
- `Update-TeamsChannelManager.ps1` updates an installed copy from the public GitHub `main` branch.
- `Build-Package.ps1` creates the distributable ZIP.
- `Add-PrivateChannelMembers.ps1` is the legacy CSV/console workflow.

Preserve the local-first architecture unless the user explicitly requests a migration. The HTTP listener must remain bound to `127.0.0.1`, not a LAN or public interface.

## Repository and release source

- Repository: `https://github.com/huynhnguyenday/tool-MS365`
- Release branch: `main`
- Version source of truth: `VERSION`
- Update allowlist: `UPDATE-MANIFEST.txt`
- Generated package directory: `dist/`
- Update backups: `.update-backup/`

Do not change the repository URL, update source, default branch, or updater trust model without explicit user approval.

## Architecture rules

The application has two membership flows. Keep them separate in both UI and server validation.

### Team-only flow

Use this flow when a selected Team has no selected private channel.

- Add or update each selected user at Team level.
- Allow a per-user Team role of `Member` or `Owner`.
- Standard-channel access is inherited from Team membership.
- Do not send private-channel assignments in this flow.

### Private-channel flow

Use this flow when one or more private channels are selected for a Team.

- Validate that every selected user belongs to the parent Team.
- If users are missing, request explicit confirmation before adding them to the parent Team.
- Add missing parent-Team users as regular Members.
- Then apply the per-user `Member` or `Owner` role to each selected private channel.
- Do not mix Team-level role assignments into this flow.

Multiple Teams must be processed independently. Failure in one Team must not discard successful results from another Team.

## UI conventions

- Keep the primary desktop workflow within one viewport when practical.
- The main layout is Team/channel selection, user selection, and operation summary.
- In the summary, use the hierarchy `Team → Channel → User → Role`.
- Preserve selected private channels when the user switches between Teams.
- Use toast messages for transient feedback.
- Store session notification history under the notification bell.
- Keep the version/update button beside the connection and notification controls.
- Maintain responsive behavior for narrower screens.

## Privacy and public-repository rules

Before every public push, scan tracked and untracked project files for sensitive data.

Never commit or package:

- Microsoft Graph access or refresh tokens.
- GitHub tokens, PATs, API keys, passwords, or client secrets.
- Certificates or private keys.
- Real tenant IDs when they are not intentionally public configuration.
- Real employee/customer email addresses, UPNs, names, or membership exports.
- Generated result CSV files.
- `.update-backup/` or other machine-local backups.
- Browser profiles, authentication caches, or local configuration containing credentials.

The committed `bulk-channel-members.csv` must contain sample `@contoso.com` addresses only.

Use a GitHub noreply address for public commit metadata. Before pushing, verify the latest commit author and committer do not expose a personal email address.

## Required verification after code changes

Perform checks appropriate to the changed files. Before a release or public push, perform all of the following:

1. Parse every tracked `.ps1` file with `System.Management.Automation.Language.Parser`.
2. Parse the JavaScript embedded in `private-channel-members.html`.
3. Run `Build-Package.ps1` and confirm the ZIP is created.
4. Confirm every path in `UPDATE-MANIFEST.txt` exists and is safe.
5. Scan the repository for secrets, private keys, tokens, personal emails, and real tenant data.
6. Run `git diff --check` and review the complete diff.
7. Confirm the working tree contains no generated result or backup data.
8. Test `Update-TeamsChannelManager.ps1 -CheckOnly` after the new version is available on GitHub.

Do not claim live Microsoft Graph operations were tested unless they were actually tested with an authorized tenant account.

## Version update and release procedure

Every release that should be detected by installed copies must increase `VERSION`. Use semantic versions such as `1.0.1`, `1.1.0`, or `2.0.0`.

### Choose the version number

- Patch (`1.0.0` → `1.0.1`): bug fixes, documentation corrections, or small UI changes.
- Minor (`1.0.0` → `1.1.0`): backward-compatible features or meaningful workflow changes.
- Major (`1.0.0` → `2.0.0`): breaking changes, incompatible configuration, or a major architecture migration.

### Prepare a release

1. Finish and verify the code changes.
2. Update `VERSION` to a number greater than the version currently on GitHub `main`.
3. Update `README.md` when behavior, setup, permissions, or release steps changed.
4. Add any new distributable program file to `UPDATE-MANIFEST.txt`.
5. Do not add user data files to the update manifest.
6. Run the full verification checklist above.
7. Build the package:

   ```powershell
   .\Build-Package.ps1
   ```

8. Inspect the ZIP contents and confirm no secrets or personal data are included.
9. Review `git status`, staged files, and commit metadata.
10. Commit with a clear message, for example:

    ```powershell
    git add .
    git commit -m "Release v1.1.0"
    ```

11. Push only after the user has authorized the external write:

    ```powershell
    git push origin main
    ```

12. Optionally create and push a matching annotated tag:

    ```powershell
    git tag -a v1.1.0 -m "Teams Channel Manager v1.1.0"
    git push origin v1.1.0
    ```

13. Verify the remote version:

    ```powershell
    .\Update-TeamsChannelManager.ps1 -CheckOnly
    ```

The updater reads `VERSION` from GitHub `main`. A commit or tag alone does not make an update discoverable if `VERSION` was not increased.

## Git safety and authorization

- Do not push, force-push, create/delete remote tags, publish releases, or change repository visibility without explicit user authorization.
- Prefer normal fast-forward pushes.
- Use force-push only when the user has explicitly authorized rewriting the affected public history and the exact target is known.
- Never discard unrelated user changes.
- Keep `dist/`, `.update-backup/`, temporary files, and generated result CSVs untracked.

## Documentation

Keep `README.md` user-facing and task-oriented. Keep implementation policy and Codex working rules in this `AGENTS.md` file. When behavior changes, update both only where their audiences require it; avoid duplicating low-level implementation details unnecessarily.
