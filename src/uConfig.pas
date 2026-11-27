unit uConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, uModels;

type
  TAppConfig = record
    Connection: TConnectionSettings;
    Mode: TTransferMode;
    LocalDir: string;
    Overwrite: Boolean;
    UploadToBp: Boolean;
    DownloadFromBp: Boolean;
    ServerType: Integer;    { index into ServerTypes in uMain }
  end;

function DefaultAppConfig: TAppConfig;
function SettingsFileName: string;
procedure LoadAppConfig(out Config: TAppConfig);
procedure SaveAppConfig(const Config: TAppConfig);

implementation

function HomePath: string;
begin
  {$IFDEF WINDOWS}
  Result := GetEnvironmentVariable('USERPROFILE');
  {$ELSE}
  Result := GetEnvironmentVariable('HOME');
  {$ENDIF}
  if Result = '' then
    Result := GetCurrentDir;
end;

function DefaultAppConfig: TAppConfig;
begin
  Result.Connection.Host := '127.0.0.1';
  Result.Connection.Port := 22;
  { Blank on first run: the SD account name is usually not the local login name. }
  Result.Connection.UserName := '';
  Result.Connection.Password := '';
  Result.Connection.KeyFile := '';
  Result.Connection.Passphrase := '';
  Result.Mode := tmUpload;
  Result.LocalDir := HomePath;
  Result.Overwrite := False;
  Result.ServerType := 0;
  Result.UploadToBp := False;
  Result.DownloadFromBp := False;
end;

function SettingsFileName: string;
var
  ConfigHome: string;
begin
  {$IFDEF WINDOWS}
  { %LOCALAPPDATA%\sd-transfer-utility\settings.ini }
  ConfigHome := GetEnvironmentVariable('LOCALAPPDATA');
  if ConfigHome = '' then
    ConfigHome := IncludeTrailingPathDelimiter(HomePath) + 'AppData' + PathDelim + 'Local';
  Result := IncludeTrailingPathDelimiter(ConfigHome) + 'sd-transfer-utility' +
    PathDelim + 'settings.ini';
  Exit;
  {$ENDIF}
  ConfigHome := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if ConfigHome = '' then
    ConfigHome := IncludeTrailingPathDelimiter(HomePath) + '.config';
  Result := IncludeTrailingPathDelimiter(ConfigHome) + 'sd-transfer-utility' +
    PathDelim + 'settings.ini';
end;

procedure LoadAppConfig(out Config: TAppConfig);
var
  Ini: TIniFile;
  FileName: string;
  ModeValue: Integer;
begin
  Config := DefaultAppConfig;
  FileName := SettingsFileName;
  if not FileExists(FileName) then
    Exit;
  Ini := TIniFile.Create(FileName);
  try
    Config.Connection.Host := Ini.ReadString('connection', 'host', Config.Connection.Host);
    Config.Connection.Port := Ini.ReadInteger('connection', 'port', Config.Connection.Port);
    Config.Connection.UserName := Ini.ReadString('connection', 'user', Config.Connection.UserName);
    Config.Connection.KeyFile := Ini.ReadString('connection', 'key', '');
    ModeValue := Ini.ReadInteger('ui', 'mode', Ord(tmUpload));
    if ModeValue = Ord(tmDownload) then
      Config.Mode := tmDownload
    else
      Config.Mode := tmUpload;
    Config.LocalDir := Ini.ReadString('ui', 'local_dir', Config.LocalDir);
    Config.Overwrite := Ini.ReadBool('ui', 'overwrite', False);
    { Older settings had no server type: a Solo port means a Solo server. }
    if Config.Connection.Port = 4251 then
      Config.ServerType := Ini.ReadInteger('connection', 'server_type', 2)
    else
      Config.ServerType := Ini.ReadInteger('connection', 'server_type', 0);
    if (Config.ServerType < 0) or (Config.ServerType > 3) then
      Config.ServerType := 0;
    Config.UploadToBp := Ini.ReadBool('ui', 'upload_to_bp', False);
    Config.DownloadFromBp := Ini.ReadBool('ui', 'download_from_bp', False);
  finally
    Ini.Free;
  end;
end;

procedure SaveAppConfig(const Config: TAppConfig);
var
  Ini: TIniFile;
  FileName: string;
begin
  FileName := SettingsFileName;
  ForceDirectories(ExtractFileDir(FileName));
  Ini := TIniFile.Create(FileName);
  try
    Ini.WriteString('connection', 'host', Config.Connection.Host);
    Ini.WriteInteger('connection', 'port', Config.Connection.Port);
    Ini.WriteString('connection', 'user', Config.Connection.UserName);
    Ini.WriteString('connection', 'key', Config.Connection.KeyFile);
    { Host keys are now confirmed in a dialog; drop the old setting. }
    Ini.DeleteKey('connection', 'accept_new_host_key');
    Ini.WriteInteger('ui', 'mode', Ord(Config.Mode));
    Ini.WriteString('ui', 'local_dir', Config.LocalDir);
    { The typed download source is gone: files are picked in the SD list. }
    Ini.DeleteKey('ui', 'source_file');
    Ini.DeleteKey('ui', 'source_ids');
    Ini.WriteBool('ui', 'overwrite', Config.Overwrite);
    Ini.WriteInteger('connection', 'server_type', Config.ServerType);
    Ini.WriteBool('ui', 'upload_to_bp', Config.UploadToBp);
    Ini.WriteBool('ui', 'download_from_bp', Config.DownloadFromBp);
  finally
    Ini.Free;
  end;
end;

end.
