; Spider Buddy for Windows — per-user installer.
;
; Build through tools/windows/package.ps1. It passes MyAppVersion and SourceDir.
; The setup is Authenticode-signed by the release script; the appcast points at that
; signed file and is itself signed with the separate Windows update key.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\publish"
#endif

#define MyAppName "Spider Buddy"
#define MyAppPublisher "Ephemerill"
#define MyAppExeName "SpiderBuddy.exe"
#define MyAppId "{{6A0C5F3E-2E0B-4C71-9D4A-8E5B1F7C2A11}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/Ephemerill/spider-buddy
AppSupportURL=https://github.com/Ephemerill/spider-buddy/issues
AppUpdatesURL=https://github.com/Ephemerill/spider-buddy/releases
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} setup
VersionInfoCompany={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\SpiderBuddy
DefaultGroupName=Spider Buddy
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\build\windows\installer
OutputBaseFilename=SpiderBuddy-{#MyAppVersion}-setup
SetupIconFile=..\Resources\AppIcon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern
WizardImageFile=installer-art.bmp
WizardSmallImageFile=installer-small.bmp
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
SetupLogging=yes
CloseApplications=force
RestartApplications=no
AllowNoIcons=yes
DirExistsWarning=no
UsePreviousAppDir=yes
ChangesAssociations=no
ChangesEnvironment=no
AppMutex=Local\SpiderBuddy.SingleInstance
SetupMutex=Local\SpiderBuddy.Setup
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\Resources\AppIcon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Spider Buddy"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\AppIcon.ico"
Name: "{group}\Uninstall Spider Buddy"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Spider Buddy"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\AppIcon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Spider Buddy"; WorkingDir: "{app}"; Flags: nowait; Check: ShouldLaunchApp

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function CmdLineParamExists(const Value: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Value) = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

function ShouldLaunchApp: Boolean;
begin
  // /NOAPP lets the installer test and unattended deployments install without
  // starting the spider. Silent updates otherwise relaunch it for the user.
  Result := not CmdLineParamExists('/NOAPP');
end;
