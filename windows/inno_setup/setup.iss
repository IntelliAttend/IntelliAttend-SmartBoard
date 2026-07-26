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
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

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
// Detect existing installation and offer to close the app before upgrade
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // Try to close existing instance silently
  Exec(ExpandConstant('{app}\{#MyAppExeName}'), '--exit', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
