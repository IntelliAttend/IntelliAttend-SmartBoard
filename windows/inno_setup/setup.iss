; ══════════════════════════════════════════════════════════════════════════════
; IntelliAttend SmartBoard — Inno Setup Script
;
; Produces a single setup.exe that installs the Flutter app to:
;   %LOCALAPPDATA%\IntelliAttendSmartBoard\
;
; Usage:
;   iscc /DAppVersion=5.5.0.12 /DSourceDir=<flutter_build_output> setup.iss
;
; Silent install:  setup.exe /SILENT
; Very silent:     setup.exe /VERYSILENT
; ══════════════════════════════════════════════════════════════════════════════

#define MyAppName "IntelliAttend SmartBoard"
#define MyAppPublisher "IntelliAttend"
#define MyAppURL "https://intelliattend.com"
#define MyAppExeName "intelliattend_smartboard.exe"

; Defaults — overridden by /D flags from CI
#ifndef AppVersion
  #define AppVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
; Phase 1 isolation: update_agent.exe is built separately by CI and installed
; OUTSIDE {app} (see [Files]). It must NOT live inside SourceDir or it would be
; copied into {app} and overwritten while running during self-update.
#ifndef AgentDir
  #define AgentDir "..\..\build\windows\x64\update_agent\Release"
#endif

[Setup]
AppId={{865FA9F9-CBE0-4650-8444-D3B4168B49C1}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={localappdata}\IntelliAttendSmartBoard
DefaultGroupName={#MyAppName}
DisableDirPage=no
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir=..\..\build\windows\x64\runner\Release
OutputBaseFilename=IntelliAttendSmartBoard-{#AppVersion}-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=force
RestartApplications=no
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; update_agent.exe is EXCLUDED from the recursive {app} copy (Phase 1): the
; running agent must never be overwritten by the app installer. It is installed
; to a dedicated directory outside {app} below.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "update_agent.exe"; Flags: recursesubdirs ignoreversion

; The update agent is installed OUTSIDE the app directory
; (%LOCALAPPDATA%\IntelliAttend\UpdateAgent\) so a self-update can never
; overwrite the running agent (Windows locks running images). The Check skips
; the copy while the agent is running (detected via its update_agent.running
; marker) — a fresh install has no marker, so the agent IS installed there.
Source: "{#AgentDir}\update_agent.exe"; DestDir: "{localappdata}\IntelliAttend\UpdateAgent"; Flags: ignoreversion uninsneveruninstall; Check: not AgentRunning

[Dirs]
Name: "{app}\data"; Flags: uninsalwaysuninstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Returns True if the update agent is currently running. The agent drops
// update_agent.running in its home dir at boot and removes it on exit; while
// the marker exists the installer must NOT overwrite the running exe.
function AgentRunning(): Boolean;
var
  Marker: String;
begin
  Marker := ExpandConstant('{localappdata}\IntelliAttend\UpdateAgent\update_agent.running');
  Result := FileExists(Marker);
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  ExePath: String;
begin
  Result := True;
  ExePath := ExpandConstant('{localappdata}\IntelliAttendSmartBoard\{#MyAppExeName}');
  Exec(ExePath, '--exit', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

// The update agent (update_agent.exe) verifies every installer and every
// installed exe with WinVerifyTrust. Releases are signed with a self-signed
// IntelliAttend root, so that root must be present in the user's Trusted
// Root store or every self-update is rejected. Install it on first install
// (and every update) — idempotent, and CurrentUser\Root needs no admin.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  CerPath: String;
begin
  if CurStep = ssPostInstall then begin
    CerPath := ExpandConstant('{app}\intelliattend_signing.cer');
    if FileExists(CerPath) then begin
      Exec('certutil.exe', '-user -addstore Root "' + CerPath + '"', '',
           SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
