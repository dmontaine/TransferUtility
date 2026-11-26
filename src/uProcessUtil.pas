unit uProcessUtil;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, StrUtils, {$IFDEF UNIX}BaseUnix,{$ENDIF} uModels;

type
  TProcessResult = record
    ExitCode: Integer;
    Output: string;
    TimedOut: Boolean;
  end;

function EnvironmentSnapshot: TStringList;
procedure SetEnvironmentValue(List: TStringList; const Name, Value: string);
procedure RemoveEnvironmentValue(List: TStringList; const Name: string);
function ResolveExecutable(const Name: string): string;
function AskPassExecutable: string;
{ Pipes, stderr merged into stdout, and on Windows no console window. }
function ChildProcessOptions: TProcessOptions;
function QuoteShell(const Value: string): string;
function QuoteSftp(const Value: string): string;
function StripAnsi(const Value: string): string;
function NormalizeTerminalText(const Value: string): string;
function RunCapture(const Executable: string; const Args: TNameArray;
  Environment: TStringList; const WorkDir: string; TimeoutMs: Integer;
  const InputText: string = ''): TProcessResult;
function HomeDir: string;
{ The user's .ssh folder, with a trailing path delimiter. }
function SshDir: string;
function ExpandHome(const Path: string): string;
{ The login name, for key comments and the default user. }
function LocalUserName: string;
{ A fixed-width font that the platform has. }
function MonospaceFontName: string;
{ What the desktop calls the place deleted files go: "Trash" or "Recycle Bin". }
function TrashName: string;
{ Moves files and folders where they can be restored; never erases them. }
function MoveToTrash(const Paths: TNameArray; out ErrorText: string): Boolean;
function FriendlySshError(const Output, Host: string; Port: Integer;
  HavePassword: Boolean = True): string;
procedure SetSshSecrets(Env: TStringList; const Password, Passphrase: string);

implementation

{$IFDEF WINDOWS}
uses
  ShellApi;  { not Windows: its GetEnvironmentVariable would hide SysUtils' }
{$ENDIF}

function EnvironmentSnapshot: TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create;
  try
    for I := 0 to GetEnvironmentVariableCount - 1 do
      Result.Add(GetEnvironmentString(I));
  except
    Result.Free;
    raise;
  end;
end;

procedure SetEnvironmentValue(List: TStringList; const Name, Value: string);
var
  Index: Integer;
begin
  Index := List.IndexOfName(Name);
  if Index >= 0 then
    List[Index] := Name + '=' + Value
  else
    List.Add(Name + '=' + Value);
end;

procedure RemoveEnvironmentValue(List: TStringList; const Name: string);
var
  Index: Integer;
begin
  Index := List.IndexOfName(Name);
  if Index >= 0 then
    List.Delete(Index);
end;

function ResolveExecutable(const Name: string): string;
var
  PathValue, ExeName: string;
begin
  Result := '';
  if Name = '' then
    Exit;
  if Pos(PathDelim, Name) > 0 then
  begin
    if FileExists(Name) then
      Result := ExpandFileName(Name);
    Exit;
  end;
  ExeName := Name;
  {$IFDEF WINDOWS}
  if ExtractFileExt(ExeName) = '' then
    ExeName := ExeName + '.exe';
  { The OpenSSH that ships with Windows first: an ssh.exe from Git or MSYS that
    happens to be on PATH handles askpass and pipes differently. }
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('SystemRoot')) +
    'System32\OpenSSH\' + ExeName;
  if FileExists(Result) then
    Exit;
  Result := '';
  {$ENDIF}
  PathValue := GetEnvironmentVariable('PATH');
  Result := ExeSearch(ExeName, PathValue);
  if Result <> '' then
    Result := ExpandFileName(Result);
end;

function ChildProcessOptions: TProcessOptions;
begin
  Result := [poUsePipes, poStderrToOutPut];
  {$IFDEF WINDOWS}
  Include(Result, poNoConsole);
  {$ENDIF}
end;

function QuoteShell(const Value: string): string;
begin
  Result := #39 + StringReplace(Value, #39, #39 + '\' + #39 + #39, [rfReplaceAll]) + #39;
end;

function QuoteSftp(const Value: string): string;
begin
  Result := '"' + StringReplace(StringReplace(Value, #92, #92 + #92,
    [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"';
end;

function AskPassExecutable: string;
begin
  { The helper must sit beside the program.  There is deliberately no fallback
    to the GUI executable: that one initialises GTK before it could answer. }
  Result := IncludeTrailingPathDelimiter(ExtractFileDir(ExpandFileName(ParamStr(0)))) +
    'sd-askpass' {$IFDEF WINDOWS} + '.exe' {$ENDIF};
  if not FileExists(Result) then
    Result := '';
end;

function StripAnsi(const Value: string): string;
var
  I, J, L: Integer;
  C: Char;
begin
  Result := '';
  SetLength(Result, Length(Value));
  I := 1;
  J := 0;
  L := Length(Value);
  while I <= L do
  begin
    C := Value[I];
    if C = #27 then
    begin
      Inc(I);
      if I > L then
        Break;
      if Value[I] = '[' then
      begin
        Inc(I);
        while (I <= L) and not (Value[I] in ['@'..'~']) do
          Inc(I);
        if I <= L then
          Inc(I);
      end
      else if Value[I] = ']' then
      begin
        Inc(I);
        while I <= L do
        begin
          if Value[I] = #7 then
          begin
            Inc(I);
            Break;
          end;
          if (Value[I] = #27) and (I < L) and (Value[I + 1] = '\') then
          begin
            Inc(I, 2);
            Break;
          end;
          Inc(I);
        end;
      end
      else
        Inc(I);
    end
    else if (C = #8) and (J > 0) then
    begin
      Dec(J);
      Inc(I);
    end
    else if (C = #13) or (C = #10) or (C = #9) or (Ord(C) >= 32) then
    begin
      Inc(J);
      Result[J] := C;
      Inc(I);
    end
    else
      Inc(I);
  end;
  SetLength(Result, J);
end;

function NormalizeTerminalText(const Value: string): string;
begin
  Result := StringReplace(StripAnsi(Value), #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function RunCapture(const Executable: string; const Args: TNameArray;
  Environment: TStringList; const WorkDir: string; TimeoutMs: Integer;
  const InputText: string): TProcessResult;
var
  Proc: TProcess;
  I: Integer;
  Buffer: array[0..16383] of Byte;
  ReadCount: Integer;
  Started: QWord;
  Output: string;
  FeedInput: Boolean;
begin
  Result.ExitCode := -1;
  Result.Output := '';
  Result.TimedOut := False;
  if Executable = '' then
  begin
    Result.Output := 'No executable was supplied.';
    Exit;
  end;

  Proc := TProcess.Create(nil);
  try
    Proc.Executable := Executable;
    for I := 0 to High(Args) do
      Proc.Parameters.Add(Args[I]);
    Proc.Options := ChildProcessOptions;
    if WorkDir <> '' then
      Proc.CurrentDirectory := WorkDir;
    if (Environment <> nil) and (Environment.Count > 0) then
      Proc.Environment.Assign(Environment);

    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        Result.Output := E.Message;
        Exit;
      end;
    end;

    Output := '';
    FeedInput := InputText <> '';
    if FeedInput then
    begin
      try
        Proc.Input.Write(InputText[1], Length(InputText));
      except
        on E: Exception do
          Output := Output + E.Message + LineEnding;
      end;
    end;
    Proc.CloseInput;

    Started := GetTickCount64;
    while Proc.Running or (Proc.Output.NumBytesAvailable > 0) do
    begin
      if Proc.Output.NumBytesAvailable > 0 then
      begin
        ReadCount := Proc.Output.Read(Buffer, SizeOf(Buffer));
        if ReadCount > 0 then
        begin
          SetLength(Output, Length(Output) + ReadCount);
          Move(Buffer[0], Output[Length(Output) - ReadCount + 1], ReadCount);
        end;
      end
      else
        Sleep(15);

      if (TimeoutMs > 0) and (GetTickCount64 - Started > QWord(TimeoutMs)) then
      begin
        Result.TimedOut := True;
        try
          Proc.Terminate(1);
        except
          end;
        Break;
      end;
    end;

    if Proc.Running then
    begin
      try
        Proc.WaitOnExit;
      except
        end;
    end;

    if Proc.Running then
      Result.ExitCode := -1
    else
      Result.ExitCode := Proc.ExitStatus;
  finally
    Proc.Free;
  end;

  Result.Output := Output;
end;

function HomeDir: string;
begin
  {$IFDEF WINDOWS}
  { %USERPROFILE%, where Windows OpenSSH keeps .ssh.  HOME is ignored: Git and
    MSYS set it to other places. }
  Result := GetEnvironmentVariable('USERPROFILE');
  {$ELSE}
  Result := GetEnvironmentVariable('HOME');
  {$ENDIF}
  if Result = '' then
    Result := GetUserDir;
  Result := ExcludeTrailingPathDelimiter(Result);
end;

function SshDir: string;
begin
  Result := IncludeTrailingPathDelimiter(HomeDir) + '.ssh' + PathDelim;
end;

function LocalUserName: string;
begin
  {$IFDEF WINDOWS}
  Result := GetEnvironmentVariable('USERNAME');
  {$ELSE}
  Result := GetEnvironmentVariable('USER');
  {$ENDIF}
end;

function MonospaceFontName: string;
begin
  {$IFDEF WINDOWS}
  Result := 'Consolas';
  {$ELSE}
  Result := 'Monospace';
  {$ENDIF}
end;

function TrashName: string;
begin
  {$IFDEF WINDOWS}
  Result := 'Recycle Bin';
  {$ELSE}
  Result := 'Trash';
  {$ENDIF}
end;

{$IFDEF WINDOWS}
function MoveToTrash(const Paths: TNameArray; out ErrorText: string): Boolean;
var
  Op: TSHFileOpStructW;
  From: UnicodeString;
  I, Code: Integer;
begin
  { One call for all paths: a double-NUL-terminated list.  FOF_ALLOWUNDO sends
    them to the Recycle Bin; the program has already asked for confirmation. }
  ErrorText := '';
  From := '';
  for I := 0 to High(Paths) do
    From := From + UTF8Decode(Paths[I]) + #0;
  From := From + #0;
  FillChar(Op, SizeOf(Op), 0);
  Op.wFunc := FO_DELETE;
  Op.pFrom := PWideChar(From);
  Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  Code := SHFileOperationW(@Op);
  Result := (Code = 0) and not Op.fAnyOperationsAborted;
  if not Result then
    ErrorText := Format('Windows could not move the items to the Recycle Bin ' +
      '(code %d).', [Code]);
end;
{$ELSE}
function MoveToTrash(const Paths: TNameArray; out ErrorText: string): Boolean;
var
  Exe: string;
  Args: TNameArray;
  R: TProcessResult;
  I: Integer;
begin
  ErrorText := '';
  Result := False;
  Exe := ResolveExecutable('gio');
  if Exe = '' then
  begin
    ErrorText := 'The "gio" tool is needed to move files to the Trash and was ' +
      'not found.  Delete the files with your file manager instead.';
    Exit;
  end;
  SetLength(Args, Length(Paths) + 2);
  Args[0] := 'trash';
  Args[1] := '--';
  for I := 0 to High(Paths) do
    Args[I + 2] := Paths[I];
  R := RunCapture(Exe, Args, nil, '', 30000);
  Result := R.ExitCode = 0;
  if not Result then
    ErrorText := Trim(R.Output);
end;
{$ENDIF}

function ExpandHome(const Path: string): string;
begin
  if (Path = '~') or (Copy(Path, 1, 2) = '~/') {$IFDEF WINDOWS} or
     (Copy(Path, 1, 2) = '~\') {$ENDIF} then
    Result := HomeDir + Copy(Path, 2, MaxInt)
  else
    Result := Path;
  {$IFDEF WINDOWS}
  Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
  {$ENDIF}
end;

function FriendlySshError(const Output, Host: string; Port: Integer;
  HavePassword: Boolean): string;
var
  Target: string;
begin
  { Turn the ssh failures a person can act on into plain advice. }
  Result := '';
  if Port = 22 then
    Target := Host
  else
    Target := '[' + Host + ']:' + IntToStr(Port);
  if Pos('IDENTIFICATION HAS CHANGED', Output) > 0 then
    Result := 'The SD server''s host key is not the one this computer saved the ' +
      'last time it connected.  Either the server was reinstalled or its key was ' +
      'replaced, or someone is intercepting the connection.  Ask the SD ' +
      'administrator.  If the key really was replaced, remove the old one with' +
      LineEnding + LineEnding + '    ssh-keygen -R ''' + Target + '''' + LineEnding +
      LineEnding + 'and connect again; you will be asked to accept the new key.'
  else if Pos('Host key verification failed', Output) > 0 then
    Result := 'The SD server''s host key could not be verified, so the connection ' +
      'was refused.'
  else if (Pos('Permission denied', Output) > 0) and not HavePassword then
    Result := 'The SD server refused the login: no password was entered, and ' +
      'the server did not accept this computer''s ssh key.  Enter your ' +
      'password, or give your public key to the SD administrator (Menu > ' +
      'SSH key setup).'
  else if Pos('Permission denied', Output) > 0 then
    Result := 'The SD server refused the login (Permission denied).  Check the ' +
      'user name and password, or the key chosen in SSH key setup.';
end;

procedure SetSshSecrets(Env: TStringList; const Password, Passphrase: string);
begin
  { Read by sd-askpass: the password for the login prompt, the passphrase for
    a key prompt.  Only in the child environment; never on disk or argv. }
  if Password <> '' then
    SetEnvironmentValue(Env, 'SDTU_SSH_PASSWORD', Password)
  else
    RemoveEnvironmentValue(Env, 'SDTU_SSH_PASSWORD');
  if Passphrase <> '' then
    SetEnvironmentValue(Env, 'SDTU_SSH_PASSPHRASE', Passphrase)
  else
    RemoveEnvironmentValue(Env, 'SDTU_SSH_PASSPHRASE');
end;

{$IFDEF UNIX}
initialization
  { Writing to a child that has already exited (ssh refusing a connection
    before reading its batch, say) must be an error we can report, not a
    SIGPIPE that silently kills the whole program.  Windows has no SIGPIPE. }
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
{$ENDIF}
end.
