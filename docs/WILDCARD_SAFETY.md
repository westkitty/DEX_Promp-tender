# Wildcard mutation safety

## Default behavior

- **Save Local** saves only to `~/Library/Application Support/DexPromptender/Wildcards/`. It never calls DexDiffusion or mirrors into an external folder.
- **Sync...** presents a destination chooser. Folder and remote destinations are both off by default. Existing differing content requires a separate, explicit overwrite choice, and the destination is backed up before replacement.
- **Delete Bank...** presents a destination chooser. Only the local copy can be preselected; external-folder deletion and DexDiffusion remote deletion require separate opt-in. Remote deletion also requires a second acknowledgment.
- Bundled wildcard banks are read-only; duplicate them under a different name before editing.
- Local, folder, and remote backups are kept in `~/Library/Application Support/DexPromptender/WildcardBackups/`. They are not uploaded to GitHub.

## Failure and concurrency behavior

- A failing remote preflight blocks all writes and deletion.
- An unavailable synced folder blocks folder sync without altering the bank.
- A remote bank that changes after the preflight snapshot is not overwritten or deleted by a stale request. The existing API does not provide an atomic conditional write, so an external writer could still race after the final recheck.
- Individual storage operations may partially succeed before a later destination fails. The status banner reports an incomplete operation; local backups remain available for manual recovery.
- A mocked HTTP transport is used for automated tests; tests do not issue real remote PUT or DELETE requests.
- Reading/refreshing DexDiffusion's wildcard catalog performs only GET operations.

## Validation

Run `swift test` on a compatible macOS Swift toolchain, plus the app's existing bundle builder. The test suite covers no-auto-remote-write, explicit sync, protected built-ins, backup creation, remote HTTP failures, folder conflicts, and concurrent remote changes.

The app's compiled source and tests are not a substitute for a real click-through of the confirmation sheets on the user's MacBook. Native GUI testing remains a separate release acceptance check.
