; sd-transfer.iss - Inno Setup 6 script for SD Core Transfer Utility on Windows.
;
; Built by WindowsVersion\build.ps1 -Installer, which builds and strips the two
; programs first and passes the version from src\uModels.pas:
;
;   powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1 -Installer
;
; Output: build\installer\transfer-utility-setup.exe
;
; WHERE IT INSTALLS.  For all users, in C:\Program Files\SD Core Transfer Utility,
; which needs an administrator's consent: only administrators can then replace
; sd-transfer.exe or sd-askpass.exe, the program that is handed the SD Core password.
; That is the tighter default.  An administrator who wants a person to install
; it for themselves without administrator rights can have them run the setup
; with /CURRENTUSER (it then goes to %LOCALAPPDATA%\Programs, a folder that
; person can write to).  Nothing else is loosened.
;
; WHAT IT DOES NOT TOUCH.  Settings live in
; %LOCALAPPDATA%\sd-transfer-utility\settings.ini and keys and known_hosts in
; %USERPROFILE%\.ssh; uninstalling leaves both alone.  No password is ever
; stored.

#ifndef AppVer
  #define AppVer "1.1.0"
#endif
#define AppName      "SD Core Transfer Utility"
#define AppPublisher "SD Core"
#define AppExe       "sd-transfer.exe"
#define Root         ".."
#define AppUrl       "https://github.com/dmontaine/TransferUtility"

[Setup]
; Never change AppId: it is how an upgrade finds the installed copy.
AppId={{A9E15E9F-4D5B-42E8-AC05-AA9DF7E5DD5D}
AppName={#AppName}
AppVersion={#AppVer}
AppVerName={#AppName} {#AppVer}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
AppCopyright=Copyright (c) 2026 Donald Montaine
VersionInfoVersion={#AppVer}
VersionInfoDescription={#AppName} setup
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile={#Root}\LICENSE
OutputDir={#Root}\build\installer
OutputBaseFilename=transfer-utility-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Windows 10 1809 or later: the first release with the OpenSSH Client feature.
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName} {#AppVer}
; An upgrade while the program is open asks to close it rather than failing.
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; The two programs must sit in the same folder: sd-askpass hands ssh the
; password typed into sd-transfer.
Source: "{#Root}\bin\sd-transfer.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Root}\bin\sd-askpass.exe";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#Root}\LICENSE";             DestDir: "{app}"; DestName: "LICENSE.txt"
Source: "{#Root}\docs\USER_GUIDE.md";  DestDir: "{app}"; DestName: "USER_GUIDE.md"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\User guide"; Filename: "{app}\USER_GUIDE.md"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[InstallDelete]
; Shortcuts from before the rename to "SD Core Transfer Utility": an upgrade
; would otherwise leave them beside the new ones.
Type: files; Name: "{group}\SD Transfer Utility.lnk"
Type: files; Name: "{group}\Uninstall SD Transfer Utility.lnk"
Type: files; Name: "{autodesktop}\SD Transfer Utility.lnk"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
{ The utility runs Windows' own OpenSSH (ssh.exe, sftp.exe, ssh-keygen.exe,
  ssh-keyscan.exe in System32\OpenSSH).  Setup does not install it - that is
  a Windows feature the person or the administrator turns on - but says so
  before installing, so nobody is left with a program that cannot connect. }

function OpenSshPresent: Boolean;
var
  Dir: String;
begin
  Dir := ExpandConstant('{sys}\OpenSSH\');
  Result := FileExists(Dir + 'ssh.exe') and FileExists(Dir + 'sftp.exe') and
    FileExists(Dir + 'ssh-keygen.exe') and FileExists(Dir + 'ssh-keyscan.exe');
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if OpenSshPresent then
    Exit;
  if WizardSilent then
  begin
    Log('Windows OpenSSH Client was not found; installing anyway (silent).');
    Exit;
  end;
  Result := MsgBox(
    'SD Core Transfer Utility needs the Windows "OpenSSH Client" feature, which is ' +
    'not turned on on this computer.' + #13#10#13#10 +
    'Turn it on in Settings > System > Optional features > Add a feature > ' +
    'OpenSSH Client, or in an administrator PowerShell:' + #13#10#13#10 +
    '    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0' + #13#10#13#10 +
    'Install SD Core Transfer Utility now anyway?', mbConfirmation, MB_YESNO) = IDYES;
end;
