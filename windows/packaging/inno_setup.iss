[Setup]
AppId={{io.github.quantumheart.kohera}
AppName=Kohera
AppVersion={#AppVersion}
AppPublisher=Kohera
AppPublisherURL=https://github.com/Quantumheart/Kohera
DefaultDirName={autopf}\Kohera
DefaultGroupName=Kohera
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=kohera-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Kohera"; Filename: "{app}\kohera.exe"; AppUserModelID: "io.github.quantumheart.kohera"
Name: "{autodesktop}\Kohera"; Filename: "{app}\kohera.exe"; Tasks: desktopicon; AppUserModelID: "io.github.quantumheart.kohera"

[Run]
Filename: "{app}\kohera.exe"; Description: "{cm:LaunchProgram,Kohera}"; Flags: nowait postinstall skipifsilent
