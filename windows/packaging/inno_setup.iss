[Setup]
AppId={{com.example.lattice}
AppName=Lattice
AppVersion={#AppVersion}
AppPublisher=Lattice
AppPublisherURL=https://github.com/Quantumheart/Lattice
DefaultDirName={autopf}\Lattice
DefaultGroupName=Lattice
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=lattice-windows-x64-setup
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
Name: "{group}\Lattice"; Filename: "{app}\lattice.exe"
Name: "{autodesktop}\Lattice"; Filename: "{app}\lattice.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lattice.exe"; Description: "{cm:LaunchProgram,Lattice}"; Flags: nowait postinstall skipifsilent
