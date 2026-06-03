#define MyAppName "LIUNIAN的个性化地图"
#define MyAppExeName "appmap_demo2024.exe"
#define MyAppVersion "1.0"
#define MyAppPublisher "fadaway123"
#define MyAppURL "https://github.com/fadaway123/map_demo2024"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\map_demo2024
DefaultGroupName={#MyAppName}
OutputDir=..\installer_output
OutputBaseFilename=map_demo2024_Setup
SetupIconFile=APP封面.ico
UninstallDisplayIcon={app}\APP封面.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\build\release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "APP封面.ico"; DestDir: "{app}"

Source: "必看！！.txt"; DestDir: "{app}"; Flags: isreadme

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\APP封面.ico"
Name: "{group}\卸载{#MyAppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\APP封面.ico"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动程序"; Flags: postinstall nowait skipifsilent
