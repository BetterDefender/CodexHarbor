# Codex Harbor for Windows

This is the Windows desktop build of Codex Harbor. It uses the same account core and JSON interface as the macOS app, with a separate Electron interface.

## Install

Choose the package that matches your Windows machine:

- `CodexHarbor-1.0.0-win32-x64-setup.exe` for Windows 10/11 on x64.
- `CodexHarbor-1.0.0-win32-arm64-setup.exe` for Windows 11 on Arm.

Run the installer and follow the wizard. It installs per user under `%LOCALAPPDATA%\Programs\Codex Harbor`, creates Start Menu and desktop shortcuts, and registers an uninstaller. Close Codex Harbor before installing an update.

Portable builds are also available:

- `CodexHarbor-1.0.0-win32-x64.zip`
- `CodexHarbor-1.0.0-win32-arm64.zip`

Unzip and run `Codex Harbor.exe` without installing. The installers and portable builds are unsigned, so Windows SmartScreen may ask you to confirm them.

On first launch the interface follows the system language; use the sidebar to switch between English and 中文, and between System, Light, and Dark appearance. The app refreshes live usage for all saved accounts once at every launch.

## Behavior

- Closing the window with **X** asks whether to **minimize to the system tray** or **quit**. Minimize keeps the app running in the tray; the tray menu can reopen or quit it. Launching a second copy focuses the existing window. The close prompt, tray menu, and import dialog follow the selected interface language.
- The app refreshes live usage for every account once at launch, then refreshes again when you use **Refresh usage**.
- The current `%USERPROFILE%\.codex\auth.json` is synced into the active account's saved snapshot automatically at launch, before switching away, and when you use **Save current**. The sync copies only the auth file, so cached usage and aliases are preserved.
- **Quit Codex/ChatGPT and any Codex CLI sessions yourself before switching.** Harbor does not close them; it checks and aborts with a “still running” message if any remain. After switching, reopen Codex or use **Open Codex**.
- **Do not use Codex's Sign out to switch accounts.** Signing out can revoke the saved login. If a saved login is revoked or expired, sign in to that account in Codex; the snapshot is synced automatically on the next launch or switch, or use **Save current** immediately. Harbor warns when a snapshot's refresh fails with 401 or missing auth.
- The **ChatGPT desktop app keeps its own login** and is not the same client as Codex CLI / Codex App. Switching in Codex Harbor may not update a ChatGPT desktop session; use Codex CLI or Codex App for switched accounts.
- System proxy settings are read from the Windows Internet Settings registry and passed to the account core for live usage refresh. PAC-only configurations may need a manual proxy environment.
- Account groups, theme, and language are stored locally by the app. Account credentials remain in `%USERPROFILE%\.codex` (or `CODEX_HOME`). Uninstalling the app does not delete credentials or settings. The app pins one explicit `CODEX_HOME` for all core calls and passes it to `Open Codex`.

## Build

Requirements: Node.js 22+ and npm, plus `zip` for the portable archives and `makensis` for the installers (`brew install makensis` on macOS).

```sh
cd windows
npm install
./scripts/build-windows.sh
```

The build script packages both `win32-x64` and `win32-arm64` with Electron Packager and, when `makensis` is available, builds the guided NSIS installers too. To rebuild only the installers, run `./installer/build-installers.sh`.

```text
dist/windows/Codex Harbor-win32-x64/
dist/windows/Codex Harbor-win32-arm64/
dist/CodexHarbor-1.0.0-win32-x64.zip
dist/CodexHarbor-1.0.0-win32-arm64.zip
dist/CodexHarbor-1.0.0-win32-x64-setup.exe
dist/CodexHarbor-1.0.0-win32-arm64-setup.exe
```

The build script defaults `ELECTRON_MIRROR` to the npmmirror Electron mirror; override it if you prefer another mirror. The two account cores are bundled at `core/harbor-core-x64.exe` and `core/harbor-core-arm64.exe`; the app selects the matching one for the running architecture. Their MIT notice is in `core/LICENSE` and `THIRD_PARTY_NOTICES.md`. The app does not include the official Codex desktop app or CLI.

## Scope

The builds are unsigned and do not include automatic updates, a Microsoft Store package, or a native WinUI version. The installer is per-user and does not require administrator rights.
