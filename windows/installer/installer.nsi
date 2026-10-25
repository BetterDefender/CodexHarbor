Unicode true
!include "MUI2.nsh"

!ifndef ARCH
  !define ARCH "x64"
!endif
!ifndef APPDIR
  !error "APPDIR is required"
!endif
!ifndef OUTFILE
  !error "OUTFILE is required"
!endif
!ifndef ICONFILE
  !define ICONFILE "..\assets\icon.ico"
!endif
!ifndef LICENSEFILE
  !define LICENSEFILE "LICENSE.txt"
!endif

!define PRODUCT_NAME "Codex Harbor"
!define PRODUCT_VERSION "1.0.0"
!define PRODUCT_PUBLISHER "Gh0stX"

Name "${PRODUCT_NAME}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\Codex Harbor"
InstallDirRegKey HKCU "Software\Codex Harbor" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma

VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "FileDescription" "Codex Harbor installer (${ARCH})"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "LegalCopyright" "© 2026 Gh0stX"

!define MUI_ABORTWARNING
!define MUI_ICON "${ICONFILE}"
!define MUI_UNICON "${ICONFILE}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Codex Harbor.exe"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSEFILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY
  FindWindow $0 "Chrome_WidgetWin_1" "${PRODUCT_NAME}"
  StrCmp $0 0 installer_ready
  MessageBox MB_OK|MB_ICONEXCLAMATION "Codex Harbor is running. Close it before installing.$\r$\n$\r$\n请先退出 Codex Harbor，再运行安装程序。"
  Abort
installer_ready:
FunctionEnd

Section "Codex Harbor" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${APPDIR}/*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\Codex Harbor"
  CreateShortcut "$SMPROGRAMS\Codex Harbor\Codex Harbor.lnk" "$INSTDIR\Codex Harbor.exe"
  CreateShortcut "$SMPROGRAMS\Codex Harbor\Uninstall Codex Harbor.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\Codex Harbor.lnk" "$INSTDIR\Codex Harbor.exe"

  WriteRegStr HKCU "Software\Codex Harbor" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Codex Harbor" "Version" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Codex Harbor" "Architecture" "${ARCH}"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "DisplayIcon" "$INSTDIR\Codex Harbor.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\Codex Harbor.lnk"
  Delete "$SMPROGRAMS\Codex Harbor\Codex Harbor.lnk"
  Delete "$SMPROGRAMS\Codex Harbor\Uninstall Codex Harbor.lnk"
  RMDir "$SMPROGRAMS\Codex Harbor"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexHarbor"
  DeleteRegKey HKCU "Software\Codex Harbor"
SectionEnd
