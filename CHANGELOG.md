# Changelog

## 1.0.0

Initial public release.

- Codex Harbor, a desktop Codex account manager for macOS and Windows, with a compact two-column account workspace.
- Account groups: drag cards onto groups in the sidebar, use **Move to group** from a card menu, or assign accounts in the Groups sheet.
- Fixed header, summary, search row, group controls and sidebar; only the account cards scroll.
- Live, local and cached usage with short-window, weekly and free-plan quotas, reset times, data source and snapshot time.
- Save the current Codex login or import an `auth.json` file or a folder of JSON files.
- macOS: switch a saved account, synchronize the background service, verify the local selection, and restart Codex.
- Windows: portable x64 and arm64 builds plus guided per-user NSIS installers; quit the client before switching and reopen it afterwards.
- Windows close button asks whether to minimize to the system tray or quit; the tray menu can reopen or quit the app.
- macOS and Windows sync the current Codex login into the saved snapshot at launch, before switching away, and on **Save current**, preserving cached usage and aliases.
- Both platforms refresh live usage for all saved accounts once at every launch.
- Light, dark and system appearance, remembered between launches.
- English and Simplified Chinese interface with instant switching and a remembered preference; Windows follows the system language on first launch and localizes the native close prompt, tray menu and import dialog.
- Windows pins one explicit `CODEX_HOME` for all core calls, warns before switching to a revoked or expired snapshot, and reads the system proxy from Windows Internet Settings.
- macOS reads the system proxy for live refresh when launched from Finder.
- Account credentials remain in the local files managed by the bundled account core; the app does not add Keychain encryption.
- Bundled third-party account core under the MIT license; required notices retained in the repository and application bundles.
