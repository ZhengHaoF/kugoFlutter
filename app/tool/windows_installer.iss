; Per-user installer of the exact saved production Release bundle.
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#if !FileExists(SourceDir + "\overtone.exe")
  #error Missing production executable
#endif
#if !FileExists(SourceDir + "\flutter_windows.dll")
  #error Missing Flutter runtime
#endif

[Setup]
AppId=overtone.ZhengHaoF
AppName=泛音
AppVersion={#AppVersion}
AppVerName=泛音 {#AppVersion}
DefaultDirName={localappdata}\Programs\overtone
DefaultGroupName=overtone
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=overtone-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\overtone.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\泛音"; Filename: "{app}\overtone.exe"; WorkingDir: "{app}"; IconFilename: "{app}\data\flutter_assets\assets\app_icon.ico"; AppUserModelID: "com.kugo.player"
Name: "{autodesktop}\泛音"; Filename: "{app}\overtone.exe"; WorkingDir: "{app}"; IconFilename: "{app}\data\flutter_assets\assets\app_icon.ico"; AppUserModelID: "com.kugo.player"; Tasks: desktopicon

[Run]
Filename: "{app}\overtone.exe"; Description: "Launch 泛音"; Flags: nowait postinstall skipifsilent
