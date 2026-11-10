; Inno Setup script: turns the Windows build into OChaThai-Setup.exe
; Build first with build_windows.bat (or the GitHub workflow), then:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows_installer.iss

#define MyAppName "O'Cha Thai"
#define MyAppExe "order_printer.exe"
#define MyAppVersion "1.0.0"

[Setup]
AppId={{8F3C2A51-5B7E-4C2B-9D41-0C7A1E6B2F90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Korvipong Ltd
DefaultDirName={autopf}\OCha Thai
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=OChaThai-Setup
SetupIconFile=assets\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
