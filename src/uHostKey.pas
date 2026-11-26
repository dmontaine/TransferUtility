unit uHostKey;

{ Host-key confirmation, done before ssh or sftp runs.

  ssh itself always runs with StrictHostKeyChecking=yes, so it never asks a
  question nobody can answer and never accepts a key silently.  Instead:

    1. "ssh -G" tells us the real host name, port, known_hosts files and any
       HostKeyAlias from the person's own ssh configuration;
    2. "ssh-keygen -F" looks the server up in those files;
    3. if it is not there, "ssh-keyscan" reads the server's keys,
       "ssh-keygen -l" turns them into fingerprints, and the person is asked
       the same yes/no question ssh would ask, in a dialog;
    4. on yes the keys are appended to the first known_hosts file.

  A key that is present but different is NOT handled here: ssh refuses the
  connection and the person is told how to remove the old key, as ssh does. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uModels;

type
  THostKeyLog = procedure(const Text: string) of object;

function EnsureHostKnown(const Settings: TConnectionSettings;
  Confirm: TConfirmEvent; Log: THostKeyLog; out ErrorText: string): Boolean;
{ True when an ssh server answers on Host:Port (it offers a host key). }
function SshPortAnswers(const Host: string; Port: Integer): Boolean;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF} uProcessUtil;

const
  ToolTimeout = 15000;

type
  TSshView = record
    HostName: string;
    Port: Integer;
    HostKeyAlias: string;
    KnownHostsFiles: TNameArray;
  end;

function RunTool(const Name: string; const Args: TNameArray;
  const InputText: string; out Output: string): Integer;
var
  Exe: string;
  R: TProcessResult;
begin
  Output := '';
  Result := -1;
  Exe := ResolveExecutable(Name);
  if Exe = '' then
  begin
    Output := 'The OpenSSH tool "' + Name + '" was not found in PATH.';
    Exit;
  end;
  R := RunCapture(Exe, Args, nil, '', ToolTimeout, InputText);
  Output := R.Output;
  if R.TimedOut then
    Output := Output + LineEnding + Name + ' timed out.'
  else
    Result := R.ExitCode;
end;

function Args(const Values: array of string): TNameArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I] := Values[I];
end;

function ReadSshView(const Settings: TConnectionSettings; out View: TSshView;
  out ErrorText: string): Boolean;
var
  Output, Line, Key, Value: string;
  Lines: TStringList;
  I, P: Integer;
begin
  Result := False;
  ErrorText := '';
  View.HostName := Settings.Host;
  View.Port := Settings.Port;
  View.HostKeyAlias := '';
  View.KnownHostsFiles := nil;
  if RunTool('ssh', Args(['-G', '-p', IntToStr(Settings.Port), '--',
    Settings.UserName + '@' + Settings.Host]), '', Output) <> 0 then
  begin
    ErrorText := 'Could not read the ssh configuration for ' + Settings.Host +
      ': ' + Trim(Output);
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      P := Pos(' ', Line);
      if P = 0 then
        Continue;
      Key := LowerCase(Copy(Line, 1, P - 1));
      Value := Trim(Copy(Line, P + 1, MaxInt));
      if Key = 'hostname' then
        View.HostName := Value
      else if Key = 'port' then
        View.Port := StrToIntDef(Value, Settings.Port)
      else if Key = 'hostkeyalias' then
        View.HostKeyAlias := Value
      else if (Key = 'userknownhostsfile') or (Key = 'globalknownhostsfile') then
      begin
        { The user's own files first: new keys are written to the first one. }
        if Key = 'userknownhostsfile' then
          View.KnownHostsFiles := Concat(SplitTokens(Value), View.KnownHostsFiles)
        else
          View.KnownHostsFiles := Concat(View.KnownHostsFiles, SplitTokens(Value));
      end;
    end;
  finally
    Lines.Free;
  end;
  if Length(View.KnownHostsFiles) = 0 then
  begin
    SetLength(View.KnownHostsFiles, 1);
    View.KnownHostsFiles[0] := '~/.ssh/known_hosts';
  end;
  for I := 0 to High(View.KnownHostsFiles) do
  begin
    {$IFDEF WINDOWS}
    { Windows OpenSSH names its global files under __PROGRAMDATA__. }
    View.KnownHostsFiles[I] := StringReplace(View.KnownHostsFiles[I],
      '__PROGRAMDATA__', GetEnvironmentVariable('ProgramData'), []);
    {$ENDIF}
    View.KnownHostsFiles[I] := ExpandHome(View.KnownHostsFiles[I]);
  end;
  Result := True;
end;

function LookupName(const View: TSshView): string;
begin
  if View.HostKeyAlias <> '' then
    Result := View.HostKeyAlias
  else
    Result := View.HostName;
  if View.Port <> 22 then
    Result := '[' + Result + ']:' + IntToStr(View.Port);
end;

function AlreadyKnown(const View: TSshView): Boolean;
var
  I: Integer;
  Output: string;
begin
  Result := False;
  for I := 0 to High(View.KnownHostsFiles) do
    if FileExists(View.KnownHostsFiles[I]) and
       (RunTool('ssh-keygen', Args(['-F', LookupName(View), '-f',
         View.KnownHostsFiles[I]]), '', Output) = 0) and (Trim(Output) <> '') then
      Exit(True);
end;

function ScanKeys(const View: TSshView; out KeyLines: TStringList;
  out ErrorText: string): Boolean;
var
  Output, Line: string;
  Lines: TStringList;
  I: Integer;
begin
  Result := False;
  ErrorText := '';
  KeyLines := TStringList.Create;
  RunTool('ssh-keyscan', Args(['-T', '10', '-p', IntToStr(View.Port),
    View.HostName]), '', Output);
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = '#') then
        Continue;
      { "host keytype base64" }
      if Length(SplitTokens(Line)) >= 3 then
        KeyLines.Add(Line);
    end;
  finally
    Lines.Free;
  end;
  if KeyLines.Count = 0 then
  begin
    ErrorText := Format('Could not read the host key of %s port %d.  Check the ' +
      'host name and the server type (port), and that the SD server is running.',
      [View.HostName, View.Port]);
    if Trim(Output) <> '' then
      ErrorText := ErrorText + LineEnding + LineEnding + Trim(Output);
    FreeAndNil(KeyLines);
    Exit;
  end;
  Result := True;
end;

function Fingerprints(KeyLines: TStringList): string;
var
  Output, Line: string;
  Lines: TStringList;
  Parts: TNameArray;
  I: Integer;
begin
  { "256 SHA256:abc... host (ED25519)" -> "ED25519   SHA256:abc..." }
  Result := '';
  RunTool('ssh-keygen', Args(['-l', '-f', '-']), KeyLines.Text, Output);
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      Parts := SplitTokens(Line);
      if (Length(Parts) >= 4) and (Copy(Parts[1], 1, 7) = 'SHA256:') then
        Result := Result + Format('    %-9s %s', [StringReplace(StringReplace(
          Parts[High(Parts)], '(', '', []), ')', '', []), Parts[1]]) + LineEnding;
    end;
  finally
    Lines.Free;
  end;
end;

function SaveKeys(const View: TSshView; KeyLines: TStringList;
  out FileName, ErrorText: string): Boolean;
var
  Dir, Text, Name: string;
  Parts: TNameArray;
  I: Integer;
  {$IFDEF UNIX}
  Fd: Integer;
  IsNew: Boolean;
  {$ELSE}
  F: TFileStream;
  {$ENDIF}
begin
  Result := False;
  ErrorText := '';
  FileName := View.KnownHostsFiles[0];
  Dir := ExtractFileDir(FileName);
  if not DirectoryExists(Dir) then
  begin
    if not ForceDirectories(Dir) then
    begin
      ErrorText := 'Could not create ' + Dir;
      Exit;
    end;
    {$IFDEF UNIX}
    fpChmod(Dir, &700);
    {$ENDIF}
  end;
  { Store under the name ssh will look up (alias and port included). }
  Name := LookupName(View);
  Text := '';
  for I := 0 to KeyLines.Count - 1 do
  begin
    Parts := SplitTokens(KeyLines[I]);
    Text := Text + Name + ' ' + Parts[1] + ' ' + Parts[2] + #10;
  end;
  {$IFDEF WINDOWS}
  { No chmod: a file created in the user's own .ssh folder inherits that
    folder's ACL, which is what Windows OpenSSH checks. }
  try
    if FileExists(FileName) then
    begin
      F := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyWrite);
      F.Seek(0, soEnd);
    end
    else
      F := TFileStream.Create(FileName, fmCreate);
    try
      F.WriteBuffer(Text[1], Length(Text));
    finally
      F.Free;
    end;
  except
    on E: Exception do
    begin
      ErrorText := 'Could not write ' + FileName + ': ' + E.Message;
      Exit;
    end;
  end;
  Result := True;
  {$ELSE}
  IsNew := not FileExists(FileName);
  Fd := fpOpen(FileName, O_WRONLY or O_CREAT or O_APPEND, &600);
  if Fd < 0 then
  begin
    ErrorText := 'Could not write ' + FileName;
    Exit;
  end;
  try
    if fpWrite(Fd, Text[1], Length(Text)) <> Length(Text) then
    begin
      ErrorText := 'Could not write ' + FileName;
      Exit;
    end;
  finally
    fpClose(Fd);
  end;
  if IsNew then
    fpChmod(FileName, &600);
  Result := True;
  {$ENDIF}
end;

function EnsureHostKnown(const Settings: TConnectionSettings;
  Confirm: TConfirmEvent; Log: THostKeyLog; out ErrorText: string): Boolean;
var
  View: TSshView;
  KeyLines: TStringList;
  Shown, Question, FileName: string;
begin
  Result := False;
  if not ReadSshView(Settings, View, ErrorText) then
    Exit;
  if AlreadyKnown(View) then
    Exit(True);

  if Assigned(Log) then
    Log('This computer has not connected to ' + LookupName(View) +
      ' before; reading its host key.');
  if not ScanKeys(View, KeyLines, ErrorText) then
    Exit;
  try
    if View.Port = 22 then
      Shown := View.HostName
    else
      Shown := View.HostName + ', port ' + IntToStr(View.Port);
    Question := 'This computer has not connected to the SD server ' + Shown +
      ' before, so it cannot yet tell whether this really is that server.' +
      LineEnding + LineEnding + 'Its host key fingerprint is:' + LineEnding +
      Fingerprints(KeyLines) + LineEnding +
      'If you can, compare this with the fingerprint your SD administrator gave you.' +
      LineEnding + LineEnding + 'Trust this server and remember its key?';
    if (not Assigned(Confirm)) or
       (not Confirm('New SD server', Question)) then
    begin
      ErrorText := 'Not connected: the server''s host key was not accepted.';
      Exit;
    end;
    if not SaveKeys(View, KeyLines, FileName, ErrorText) then
      Exit;
    if Assigned(Log) then
      Log('Host key for ' + LookupName(View) + ' saved in ' + FileName + '.');
    Result := True;
  finally
    KeyLines.Free;
  end;
end;

function SshPortAnswers(const Host: string; Port: Integer): Boolean;
var
  Output: string;
  Lines: TStringList;
  I: Integer;
begin
  Result := False;
  RunTool('ssh-keyscan', Args(['-T', '5', '-p', IntToStr(Port), Host]), '', Output);
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
      if (Trim(Lines[I]) <> '') and (Trim(Lines[I])[1] <> '#') and
         (Length(SplitTokens(Lines[I])) >= 3) then
        Exit(True);
  finally
    Lines.Free;
  end;
end;

end.
