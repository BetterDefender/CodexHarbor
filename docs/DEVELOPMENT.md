# Development

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/CodexHarbor/App.swift` | SwiftUI views, frozen workspace layout, compact cards, group targets and sheets |
| `Sources/CodexHarbor/Store.swift` | Serialized account operations, groups, appearance/language state, safe preview fixtures |
| `Sources/CodexHarbor/Theme.swift` | Light/dark/system theme model, adaptive palette, typography scale and button style |
| `Sources/CodexHarbor/Localization.swift` | English/Chinese copy, locale and preference handling |
| `Sources/CodexHarbor/Backend.swift` | Subprocess execution, system proxy injection and JSON schema 1 decoding |
| `Sources/CodexHarbor/AuthStore.swift` | Auth-only snapshot sync that preserves registry usage and aliases |
| `Sources/CodexHarbor/ClientRestart.swift` | Normal quit, bounded wait and app relaunch |
| `Vendor/core/` | Pinned macOS arm64 account-core binary and its required MIT notice |
| `windows/` | Electron UI, x64/arm64 account cores and NSIS installer sources |
| `windows/scripts/build-windows.sh` | Portable x64/arm64 packaging and installer build |
| `windows/installer/` | Guided NSIS installer script and license text |
| `Tests/` | Model, localization, theme and simulated lifecycle tests |
| `scripts/smoke.py` | Isolated account-core account-operation tests |
| `scripts/build.sh` | Release compilation, icon generation, app bundle and ZIP |

## Localization and appearance

`Copy` stores English and Simplified Chinese together. `AppLanguage` resolves it when displayed, including notices and errors that are already visible. The preference key is `interfaceLanguage`; an absent or unsupported value falls back to English. Dates use the selected language and the Mac's local time zone. Brand names, account-provided text, plan identifiers and technical filenames are intentionally not translated.

`AppTheme` stores `system`, `light`, or `dark` under `interfaceTheme` and falls back to `system`. `Palette` uses dynamic `NSColor` providers, so the same view code adapts to the active appearance. The app applies `preferredColorScheme(store.theme.colorScheme)`; `nil` follows macOS. The sidebar and the Theme menu both change the same store value. Demo mode does not persist preferences.

Add both translations for new UI text. Do not expose raw account-core stderr as user-visible messages. The app's language setting controls its own UI; standard OS menus and some file-picker controls remain system-owned.

## Layout

The workspace header, summary, search row, group button and sidebar are fixed. `LazyVGrid` scrolls only the account cards, two per row, at a compact card scale. The sidebar group rows are both filters and `dropDestination` targets for dragged card payloads (`account_key` strings). The same assignment is available from a card's context menu and the Groups sheet. The Windows renderer mirrors this with a fixed header, a CSS two-column grid, and HTML drag-and-drop.

## Account and restart boundaries

All backend operations are serialized by the main-actor store's busy state. The account core runs off the main thread and receives arguments as an array, without shell interpolation. JSON list, switch and remove use schema 1; alias and import use exit status and a subsequent list reload. Credentials are never passed through UI text.

The account-core subprocess inherits the app environment plus the standard Homebrew paths. When no proxy variables are inherited (the usual Finder launch), `Backend.proxyEnvironment()` reads the macOS system proxy for `chatgpt.com` and passes `HTTP(S)_PROXY`/`ALL_PROXY`/`NO_PROXY` to the child, because the core performs its live refresh through `curl`. Existing proxy variables always take precedence.

On macOS, switching uses `--restart-daemon`. An exit failure may happen after `switched_to` was emitted, so this case receives a partial-success error and the account list is always reloaded. A desktop restart happens only after both the command and local identity validation succeed. No claim is made that the desktop's internal account identity has been independently queried.

The desktop restart targets `com.openai.codex`. It requests normal termination, waits up to 30 seconds and opens the existing bundle URL (or the registered installation). It never force-quits. The core's daemon operation itself may restart a shared daemon and interrupt tasks.

At launch and before switching, `AuthStore.syncCurrentSnapshot()` copies the current `auth.json` into the active account's snapshot without touching `registry.json`, so cached usage and aliases are preserved. It falls back to the core's `import` only for a new or mismatched account.

On Windows, the Electron main process pins one explicit `CODEX_HOME` for every core call. Before switching, it checks for `ChatGPT`, `Codex`, and `codex` processes and aborts with their names if any remain; it does not close them. The renderer asks the user to quit them, switches without `--restart-daemon`, then asks the user to reopen Codex. The same auth-only snapshot sync runs at launch, before switching, and on **Save current**. Native close prompt, tray menu, and import dialog follow the selected UI language via an IPC language update.

## Groups

Groups are app-local metadata keyed by `account_key`; they never change credentials or the account registry. `Store` keeps an array of `AccountGroup` values plus an `assignments` dictionary and persists both as JSON under `accountGroups` in `UserDefaults`. Assignments are pruned when the account list no longer contains the key. Deleting a group clears its assignments and resets the sidebar filter. Demo mode seeds two fictional groups for screenshots and does not write preferences. The Windows renderer stores the same groups/assignments, theme, and language in local storage.

## Preview and screenshots

`--demo` uses hard-coded fictional accounts and groups. The store guards refresh, import and all backend mutations, not only the buttons. Demo mode performs no backend invocation and does not save language, theme or group changes. Repository screenshots must be captured in demo mode; do not publish real account data.

## Release preparation

1. Run `./scripts/test.sh` and `./scripts/build.sh` on Apple Silicon.
2. Run `cd windows && npm install && ./scripts/build-windows.sh` to create both portable zips and both NSIS setup executables.
3. Check the English/Chinese UI, both appearances, group drag-and-drop, the Windows close prompt/tray language, and the bundle with `codesign --verify --deep --strict "dist/Codex Harbor.app"`.
4. When bumping the version, update `scripts/build.sh`, `AppInfo.version`, `windows/package.json`, `windows/installer/installer.nsi`, and both READMEs.
5. Keep the account-core MIT notices in `Vendor/core/LICENSE` and `windows/core/LICENSE`, and in the application bundles.
6. Publish only intended source files and release assets. `.build`, `dist`, `windows/node_modules`, downloaded tarballs and private auth files are excluded from version control.
7. Attach the macOS ZIP, both Windows portable ZIPs, both Windows setup executables, and the source archive to the GitHub release.
8. Developer ID signing/notarization and Windows code signing are separate distribution steps; the included scripts use ad-hoc/unsigned builds.

`./scripts/package-source.sh` creates a source archive from an explicit allowlist. It does not upload or push anything. The source archive includes both pinned account-core binaries for reproducible local builds.
