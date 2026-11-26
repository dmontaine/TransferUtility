unit uSDSession;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, uModels;

type
  TSessionLogEvent = procedure(const Text: string) of object;

  ESessionError = class(Exception);

  TSDSession = class
  private
    FConnection: TConnectionSettings;
    FProcess: TProcess;
    FBuffer: string;
    FNorm: string;          { FBuffer with terminal codes removed, kept up to date as data arrives }
    FEscState: Integer;     { position inside an escape sequence split across reads }
    FCsiParams: string;     { parameter bytes of the CSI sequence being read }
    FLastWasCR: Boolean;    { a CR was just turned into LF; swallow a following LF }
    FLog: TSessionLogEvent;
    FLastSummary: string;
    FLastError: string;
    FSlotOpen: Boolean;
    FSentAltT: Boolean;
    FCommandStart: Integer;
    FAskPassPath: string;
    procedure AppendOutput(const Data: string);
    function ReadAvailable(TimeoutMs: Integer): Boolean;
    function NormalizedBuffer: string;
    function LastNonEmptyLine(const Text: string): string;
    function PromptVisible: Boolean;
    function TextEndsInPrompt(const Text: string): Boolean;
    function HomeScreenVisible: Boolean;
    function ContainsAny(const Needles: TNameArray; out Found: string): Boolean;
    function CommandOutput: string;
    function LastUsefulErrorLine(const Text: string): string;
    procedure SendRaw(const Text: string);
    procedure SendLine(const Text: string);
    function WaitForStartup(TimeoutMs: Integer): Boolean;
    function WaitForReady(const Marker: string; TimeoutMs: Integer): Boolean;
    function WaitForPrompt(TimeoutMs: Integer): Boolean;
    function WaitForCommandPrompt(TimeoutMs: Integer): Boolean;
    function RunReceive(const CommandText, Marker: string): Boolean;
    function BuildSshArgs: TStringList;
    function BuildSshCommand: string;
    function BuildEnvironment: TStringList;
    procedure StopProcess;
    procedure LogText(const Text: string);
  public
    constructor Create(const Connection: TConnectionSettings; const AskPassPath: string;
      LogEvent: TSessionLogEvent);
    destructor Destroy; override;
    function StartSession: Boolean;
    function ActivateReceive(const Overwrite: Boolean): Boolean;
    { COPY FROM one file TO another at the SD prompt; returns how many were
      copied, and SD's lines about the ones that were not in Problems. }
    function CopyRecords(const FromFile, ToFile: string; const Names: TNameArray;
      Overwrite, Deleting: Boolean; out Copied: Integer; out Problems: string): Boolean;
    function DeleteRecords(const FileName: string; const Names: TNameArray;
      out Problems: string): Boolean;
    { Makes xfer.in and xfer.out the way SD's receive/send would, if missing. }
    function EnsureTransferFiles(out Problems: string): Boolean;
    function RenameRecord(const FileName, OldName, NewName: string;
      out Problems: string): Boolean;
    function ListRecords(const FileName: string; out Entries: TFileEntries;
      out ErrorText: string): Boolean;
    function ActivateSend(const SourceFile, RecordIds: string): Boolean;
    { Opens a send slot for files already in xfer.out. }
    function ActivateSendOut(const Names: TNameArray): Boolean;
    function CloseTransfer: Boolean;
    procedure AbortSession;
    { For tests: feed terminal output as if it came from ssh, and ask whether
      the text so far ends in the SD prompt. }
    procedure FeedOutput(const Data: string);
    function AtPrompt: Boolean;
    property NormalizedText: string read FNorm;
    property LastSummary: string read FLastSummary;
    property LastError: string read FLastError;
    property Transcript: string read FBuffer;
    property SlotOpen: Boolean read FSlotOpen;
  end;

implementation

uses
  StrUtils, Math, RegExpr, uProcessUtil;

const
  StartupTimeout = 30000;
  PromptTimeout = 10000;
  ErrorNeedles: array[0..12] of string = (
    'Permission denied',
    'Host key verification failed',
    'Connection refused',
    'Connection timed out',
    'Could not resolve hostname',
    'No route to host',
    'Too many authentication failures',
    'File transfer is not turned on for this system',
    'may not move files over its ssh login',
    'A transfer is opened from your own account',
    'Command Syntax:',
    'Nothing was copied, so no transfer was opened',
    'not plain text'
  );

constructor TSDSession.Create(const Connection: TConnectionSettings;
  const AskPassPath: string; LogEvent: TSessionLogEvent);
begin
  inherited Create;
  FConnection := Connection;
  FAskPassPath := AskPassPath;
  FLog := LogEvent;
  FSlotOpen := False;
  FLastSummary := '';
  FLastError := '';
  FSentAltT := False;
  FCommandStart := 0;
end;

destructor TSDSession.Destroy;
begin
  AbortSession;
  inherited Destroy;
end;

procedure TSDSession.LogText(const Text: string);
begin
  if Assigned(FLog) and (Text <> '') then
    FLog(Text);
end;

procedure TSDSession.AppendOutput(const Data: string);
const
  StNormal = 0; StEsc = 1; StCsi = 2; StOsc = 3; StOscEsc = 4;
var
  I, J: Integer;
  C: Char;
  Clean: string;

  function LastOut: Char;
  begin
    if J > 0 then
      Result := Clean[J]
    else if FNorm <> '' then
      Result := FNorm[Length(FNorm)]
    else
      Result := #10;
  end;

  procedure Emit(Ch: Char);
  begin
    Inc(J);
    if J > Length(Clean) then
      SetLength(Clean, Length(Clean) * 2 + 16);
    Clean[J] := Ch;
  end;

  procedure EndCsi(Final: Char);
  var
    P, N, K: Integer;
    Col: string;
  begin
    { SD Core for Windows reaches us through the server's ConPTY, which
      redraws instead of streaming: a new line is often "ESC [ row ; 1 H"
      rather than CR LF, and a run of spaces is "ESC [ n C".  Read those as
      the line break and the spaces they stand for, or the prompt ":" ends
      up glued to the banner and never looks like a prompt. }
    case Final of
      'H', 'f':
        begin
          P := Pos(';', FCsiParams);
          if P > 0 then
            Col := Copy(FCsiParams, P + 1, MaxInt)
          else
            Col := '';
          if (Col = '') or (StrToIntDef(Col, 0) <= 1) then
            if LastOut <> #10 then
            begin
              Emit(#10);
              FLastWasCR := False;
            end;
        end;
      'E':
        if LastOut <> #10 then
        begin
          Emit(#10);
          FLastWasCR := False;
        end;
      'C':
        begin
          N := StrToIntDef(FCsiParams, 1);
          if N < 1 then N := 1;
          if N > 400 then N := 400;
          for K := 1 to N do
            Emit(' ');
          FLastWasCR := False;
        end;
    end;
  end;

begin
  if Data = '' then
    Exit;
  FBuffer := FBuffer + Data;

  { Normalise only the new bytes: strip ANSI/OSC sequences, apply backspaces,
    and turn CR, LF and CRLF into a single LF.  Re-normalising the whole
    transcript on every 20-50 ms poll grew quadratically with the output. }
  SetLength(Clean, Length(Data));
  J := 0;
  for I := 1 to Length(Data) do
  begin
    C := Data[I];
    case FEscState of
      StEsc:
        if C = '[' then
        begin
          FEscState := StCsi;
          FCsiParams := '';
        end
        else if C = ']' then FEscState := StOsc
        else FEscState := StNormal;
      StCsi:
        if C in ['@'..'~'] then
        begin
          FEscState := StNormal;
          EndCsi(C);
        end
        else
          FCsiParams := FCsiParams + C;
      StOsc:
        if C = #7 then FEscState := StNormal
        else if C = #27 then FEscState := StOscEsc;
      StOscEsc:
        if C = '\' then FEscState := StNormal else FEscState := StOsc;
    else
      if C = #27 then
        FEscState := StEsc
      else if C = #8 then
      begin
        if J > 0 then
          Dec(J)
        else if FNorm <> '' then
          SetLength(FNorm, Length(FNorm) - 1);
      end
      else if C = #13 then
      begin
        Emit(#10);
        FLastWasCR := True;
      end
      else if C = #10 then
      begin
        if FLastWasCR then
          FLastWasCR := False
        else
        begin
          Emit(#10);
        end;
      end
      else if (C = #9) or (Ord(C) >= 32) then
      begin
        Emit(C);
        FLastWasCR := False;
      end;
    end;
  end;
  SetLength(Clean, J);
  FNorm := FNorm + Clean;
end;

procedure TSDSession.FeedOutput(const Data: string);
begin
  AppendOutput(Data);
end;

function TSDSession.AtPrompt: Boolean;
begin
  Result := PromptVisible;
end;

function TSDSession.CommandOutput: string;
begin
  { Only what SD printed after the prompt was reached.  The login banner or
    message of the day must never be mistaken for an SD error. }
  Result := Copy(FNorm, FCommandStart + 1, MaxInt);
end;

function TSDSession.ReadAvailable(TimeoutMs: Integer): Boolean;
var
  Buffer: array[0..16383] of Byte;
  Data: string;
  Count: Integer;
  Deadline: QWord;
  SawData: Boolean;
begin
  Result := False;
  if FProcess = nil then
    Exit;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    SawData := False;
    try
      if FProcess.Output.NumBytesAvailable > 0 then
      begin
        Count := FProcess.Output.Read(Buffer, SizeOf(Buffer));
        if Count > 0 then
        begin
          SetLength(Data, Count);
          Move(Buffer[0], Data[1], Count);
          AppendOutput(Data);
          Result := True;
          SawData := True;
        end;
      end;
    except
      Break;
    end;
    if FProcess.Running and not SawData then
      Sleep(20);
    if not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0) then
      Break;
  until (GetTickCount64 >= Deadline) or (not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0));
end;

function TSDSession.NormalizedBuffer: string;
begin
  Result := FNorm;
end;

function TSDSession.LastNonEmptyLine(const Text: string): string;
var
  P, StartPos: Integer;
begin
  Result := '';
  P := Length(Text);
  while P > 0 do
  begin
    while (P > 0) and (Text[P] in [#10, #13, ' ', #9]) do
      Dec(P);
    if P = 0 then
      Break;
    StartPos := P;
    while (StartPos > 1) and not (Text[StartPos - 1] in [#10, #13]) do
      Dec(StartPos);
    Result := Trim(Copy(Text, StartPos, P - StartPos + 1));
    Exit;
  end;
end;

function TSDSession.TextEndsInPrompt(const Text: string): Boolean;
var
  Line: string;
begin
  Line := LastNonEmptyLine(Text);
  Result := (Line = ':') or (Line = ':>');
end;

function TSDSession.PromptVisible: Boolean;
begin
  Result := TextEndsInPrompt(NormalizedBuffer);
end;

function TSDSession.HomeScreenVisible: Boolean;
var
  Text: string;
begin
  Text := NormalizedBuffer;
  Result := (Pos('Terminal', Text) > 0) and
    ((Pos('Sign out', Text) > 0) or (Pos('My programs', Text) > 0) or
     (Pos('My tools', Text) > 0) or (Pos('type exit to come back', Text) > 0));
end;

function TSDSession.ContainsAny(const Needles: TNameArray; out Found: string): Boolean;
var
  Text: string;
  I: Integer;
begin
  Result := False;
  Found := '';
  Text := FNorm;
  for I := 0 to High(Needles) do
    if PosEx(Needles[I], Text, FCommandStart + 1) > 0 then
    begin
      Found := Needles[I];
      Exit(True);
    end;
end;

function TSDSession.LastUsefulErrorLine(const Text: string): string;
var
  Lines: TStringList;
  I: Integer;
  Line: string;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := Lines.Count - 1 downto 0 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then
        Continue;
      if (Pos('Permission denied', Line) > 0) or
         (Pos('Host key verification failed', Line) > 0) or
         (Pos('Connection refused', Line) > 0) or
         (Pos('Connection timed out', Line) > 0) or
         (Pos('Could not resolve hostname', Line) > 0) or
         (Pos('No route to host', Line) > 0) or
         (Pos('Too many authentication failures', Line) > 0) or
         (Pos('File transfer is not turned on', Line) > 0) or
         (Pos('may not move files', Line) > 0) or
         (Pos('A transfer is opened from your own account', Line) > 0) or
         (Pos('Command Syntax:', Line) > 0) or
         (Pos('Nothing was copied', Line) > 0) or
         (Pos('not plain text', Line) > 0) or
         (Pos('Cannot open', Line) > 0) or
         (Pos('has no record', Line) > 0) or
         (Pos('VOC as something other', Line) > 0) or
         (Pos('No transfer is open', Line) > 0) or
         (Pos('no slot is open', Line) > 0) then
      begin
        Result := Line;
        Exit;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TSDSession.SendRaw(const Text: string);
begin
  if (FProcess = nil) or not FProcess.Running then
    raise ESessionError.Create('The SD session is no longer running.');
  if Text <> '' then
    FProcess.Input.Write(Text[1], Length(Text));
end;

procedure TSDSession.SendLine(const Text: string);
begin
  { A PTY terminal's Enter key is a carriage return, not a line feed. }
  SendRaw(Text + #13);
end;

function TSDSession.BuildSshArgs: TStringList;
var
  Args: TStringList;
  Target: string;
begin
  { The ssh options, one per item, unquoted: on Windows they become TProcess
    parameters, on Linux BuildSshCommand quotes them for script -c. }
  Target := FConnection.UserName + '@' + FConnection.Host;
  Args := TStringList.Create;
  try
    Args.Add('-tt');
    Args.Add('-p');
    Args.Add(IntToStr(FConnection.Port));
    Args.Add('-o');
    Args.Add('ConnectTimeout=15');
    Args.Add('-o');
    Args.Add('ServerAliveInterval=30');
    Args.Add('-o');
    Args.Add('ServerAliveCountMax=3');
    Args.Add('-o');
    Args.Add('NumberOfPasswordPrompts=1');
    Args.Add('-o');
    { Without the askpass helper ssh would wait on a prompt in the PTY that
      nobody can answer; fail at once instead. }
    if FAskPassPath = '' then
      Args.Add('BatchMode=yes')
    else
      Args.Add('BatchMode=no');
    Args.Add('-o');
    Args.Add('ControlMaster=no');
    Args.Add('-o');
    Args.Add('ControlPath=none');
    Args.Add('-o');
    Args.Add('ClearAllForwardings=yes');
    Args.Add('-o');
    Args.Add('PermitLocalCommand=no');
    Args.Add('-o');
    { New host keys are confirmed in a dialog before ssh runs (uHostKey). }
    Args.Add('StrictHostKeyChecking=yes');
    if Trim(FConnection.KeyFile) <> '' then
    begin
      Args.Add('-i');
      Args.Add(ExpandHome(FConnection.KeyFile));
    end;
    Args.Add('-o');
    Args.Add('LogLevel=ERROR');
    Args.Add('--');
    Args.Add(Target);
    Result := Args;
  except
    Args.Free;
    raise;
  end;
end;

function TSDSession.BuildSshCommand: string;
var
  Args: TStringList;
  Ssh: string;
  I: Integer;
begin
  Ssh := ResolveExecutable('ssh');
  if Ssh = '' then
    raise ESessionError.Create('The OpenSSH client (ssh) was not found in PATH.');
  Args := BuildSshArgs;
  try
    Result := 'stty rows 50 cols 160 2>/dev/null || true; exec ' + QuoteShell(Ssh);
    for I := 0 to Args.Count - 1 do
      if Copy(Args[I], 1, 1) = '-' then
        Result := Result + ' ' + Args[I]
      else
        Result := Result + ' ' + QuoteShell(Args[I]);
  finally
    Args.Free;
  end;
end;

function TSDSession.BuildEnvironment: TStringList;
begin
  Result := EnvironmentSnapshot;
  SetEnvironmentValue(Result, 'TERM', 'xterm-256color');
  SetEnvironmentValue(Result, 'LINES', '50');
  SetEnvironmentValue(Result, 'COLUMNS', '160');
  SetEnvironmentValue(Result, 'LC_ALL', 'C');
  if FAskPassPath <> '' then
  begin
    SetEnvironmentValue(Result, 'SSH_ASKPASS', FAskPassPath);
    SetEnvironmentValue(Result, 'SSH_ASKPASS_REQUIRE', 'force');
  end;
  {$IFDEF UNIX}
  if GetEnvironmentVariable('DISPLAY') = '' then
    SetEnvironmentValue(Result, 'DISPLAY', ':0');
  {$ENDIF}
  SetSshSecrets(Result, FConnection.Password, FConnection.Passphrase);
end;

function TSDSession.StartSession: Boolean;
var
  {$IFDEF UNIX}
  ScriptExe, CommandText: string;
  Args: TNameArray;
  {$ELSE}
  Ssh: string;
  SshArgs: TStringList;
  {$ENDIF}
  Env: TStringList;
begin
  Result := False;
  FLastError := '';
  FLastSummary := '';
  FBuffer := '';
  FNorm := '';
  FEscState := 0;
  FLastWasCR := False;
  FCommandStart := 0;
  FSlotOpen := False;
  FSentAltT := False;

  {$IFDEF WINDOWS}
  { No PTY wrapper on Windows: ssh -tt asks the server for a terminal even
    though its own standard input is a pipe. }
  Ssh := ResolveExecutable('ssh');
  if Ssh = '' then
  begin
    FLastError := 'The OpenSSH client (ssh.exe) was not found.  Turn on the ' +
      'Windows optional feature "OpenSSH Client".';
    Exit;
  end;
  try
    SshArgs := BuildSshArgs;
    Env := BuildEnvironment;
    try
      FProcess := TProcess.Create(nil);
      FProcess.Executable := Ssh;
      FProcess.Parameters.Assign(SshArgs);
      { Windows ssh.exe reports its console's window size to the server as
        the terminal size.  The hidden console poNoConsole gives is 120x30,
        which wraps the 130-column SORT listing (26 Nov 2026: "decision.txt"
        and "1090" came back on separate lines).  A new hidden console asked
        for 160x50 character cells has a 160-column window (rows stay at 30,
        conhost's default window height; SD then starts at the prompt rather
        than the 140x43 home screen).  Measured: no window and no Windows
        Terminal appears, with Windows deciding the default terminal. }
      FProcess.Options := [poUsePipes, poStderrToOutPut, poNewConsole];
      FProcess.ShowWindow := swoHide;
      FProcess.StartupOptions := [suoUseShowWindow, suoUseCountChars];
      FProcess.WindowColumns := 160;
      FProcess.WindowRows := 50;
      FProcess.Environment.Assign(Env);
      FProcess.Execute;
    finally
      Env.Free;
      SshArgs.Free;
    end;
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      StopProcess;
      Exit;
    end;
  end;
  {$ELSE}
  ScriptExe := ResolveExecutable('script');
  if ScriptExe = '' then
  begin
    FLastError := 'The util-linux "script" command was not found.  It is used to give the SD session a real PTY of 160x50.';
    Exit;
  end;

  try
    CommandText := BuildSshCommand;
    SetLength(Args, 3);
    Args[0] := '-qefc';
    Args[1] := CommandText;
    Args[2] := '/dev/null';
    Env := BuildEnvironment;
    try
      FProcess := TProcess.Create(nil);
      FProcess.Executable := ScriptExe;
      FProcess.Parameters.Add(Args[0]);
      FProcess.Parameters.Add(Args[1]);
      FProcess.Parameters.Add(Args[2]);
      FProcess.Options := ChildProcessOptions;
      FProcess.Environment.Assign(Env);
      FProcess.Execute;
    finally
      Env.Free;
    end;
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      StopProcess;
      Exit;
    end;
  end;
  {$ENDIF}

  Result := WaitForStartup(StartupTimeout);
  if Result then
    FCommandStart := Length(FNorm)
  else
  begin
    if FriendlySshError(FNorm, FConnection.Host, FConnection.Port,
      FConnection.Password <> '') <> '' then
      FLastError := FriendlySshError(FNorm, FConnection.Host, FConnection.Port,
      FConnection.Password <> '');
    if FLastError = '' then
      FLastError := LastUsefulErrorLine(NormalizedBuffer);
    if FLastError = '' then
      FLastError := 'The SD session did not reach a command prompt.';
    LogText('The SD session did not start: ' + FLastError);
    { What the server sent last, so a prompt that was not recognised can be
      seen.  It holds no password: those reach ssh only through sd-askpass. }
    if Trim(FNorm) <> '' then
      LogText('Last output from the server:' + LineEnding +
        Copy(FNorm, Max(1, Length(FNorm) - 1500 + 1), 1500))
    else
      LogText('The server sent nothing before the session gave up.');
  end;
end;

function TSDSession.WaitForStartup(TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
  Text: string;
  AltTDeadline: QWord;
begin
  Result := False;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while GetTickCount64 < Deadline do
  begin
    ReadAvailable(40);
    Text := NormalizedBuffer;

    if PromptVisible then
      Exit(True);

    if (FProcess = nil) or (not FProcess.Running and
      (FProcess.Output.NumBytesAvailable = 0)) then
    begin
      FLastError := LastUsefulErrorLine(Text);
      if FLastError = '' then
        FLastError := 'SSH ended before the SD prompt appeared.';
      Exit(False);
    end;

    { No error-phrase scan here: before the prompt the text is ssh output plus
      the server's banner.  Real ssh failures end the process, handled above. }

    if FProcess = nil then
    begin
      FLastError := 'The SSH session ended before the SD prompt appeared.';
      Exit(False);
    end;
    if not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0) then
    begin
      FLastError := LastUsefulErrorLine(Text);
      if FLastError = '' then
        FLastError := 'The SSH session ended before the SD prompt appeared.';
      Exit(False);
    end;

    if Pos('home needs a terminal', Text) > 0 then
    begin
      FLastError := 'The account starts in the SD home screen, but this client could not obtain a terminal.';
      Exit(False);
    end;

    if Pos('This account starts at the home screen, which could not open', Text) > 0 then
    begin
      FLastError := 'The account starts in the SD home screen, but its terminal is smaller than 140x43 or otherwise unsupported.';
      Exit(False);
    end;

    if HomeScreenVisible then
    begin
      if not FSentAltT then
      begin
        LogText('SD started in its home screen; opening the Terminal tile.');
        SendRaw(#27 + 't');
        FSentAltT := True;
      end;
    end;

    if FSentAltT then
    begin
      AltTDeadline := GetTickCount64 + 1000;
      while GetTickCount64 < AltTDeadline do
      begin
        ReadAvailable(40);
        if PromptVisible then
          Exit(True);
      end;
    end;

    if FProcess = nil then
      Break;
    if not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0) then
    begin
      FLastError := LastUsefulErrorLine(Text);
      if FLastError = '' then
        FLastError := 'The SSH session ended before the SD prompt appeared.';
      Exit(False);
    end;
  end;

  if PromptVisible then
    Result := True
  else
    FLastError := LastUsefulErrorLine(NormalizedBuffer);
  if (not Result) and (FLastError = '') then
    FLastError := 'Timed out waiting for the SD command prompt.';
end;

function TSDSession.WaitForReady(const Marker: string; TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
  Text: string;
  Found: string;
begin
  Result := False;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while GetTickCount64 < Deadline do
  begin
    ReadAvailable(50);
    Text := NormalizedBuffer;
    if Pos(Marker, Text) > 0 then
      Exit(True);

    if TextEndsInPrompt(CommandOutput) then
    begin
      Found := LastUsefulErrorLine(CommandOutput);
      if Found <> '' then
        FLastError := Found
      else
        FLastError := 'The SD command returned to the prompt without opening a transfer.';
      Exit(False);
    end;

    if ContainsAny(ErrorNeedles, Found) then
    begin
      FLastError := LastUsefulErrorLine(CommandOutput);
      if FLastError = '' then
        FLastError := Found;
      Exit(False);
    end;

    if (FProcess = nil) or (not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0)) then
    begin
      FLastError := LastUsefulErrorLine(CommandOutput);
      if FLastError = '' then
        FLastError := 'The SD session ended before the transfer became ready.';
      Exit(False);
    end;
  end;
  FLastError := LastUsefulErrorLine(CommandOutput);
  if FLastError = '' then
    FLastError := 'Timed out waiting for SD to open the transfer.';
end;

function TSDSession.WaitForPrompt(TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
  Found: string;
begin
  Result := False;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while GetTickCount64 < Deadline do
  begin
    ReadAvailable(40);
    if PromptVisible then
      Exit(True);
    if ContainsAny(ErrorNeedles, Found) then
      Exit(False);
    if (FProcess = nil) or (not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0)) then
      Exit(False);
  end;
end;

function TSDSession.RunReceive(const CommandText, Marker: string): Boolean;
begin
  Result := False;
  FCommandStart := Length(FNorm);
  LogText('SD command: ' + CommandText);
  try
    SendLine(CommandText);
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Result := WaitForReady(Marker, 15000);
end;

function TSDSession.ActivateReceive(const Overwrite: Boolean): Boolean;
begin
  { "RECEIVE [OVERWRITE]" is the whole syntax in every SD edition. }
  Result := False;
  FLastError := '';
  if not WaitForPrompt(PromptTimeout) then
  begin
    if FLastError = '' then
      FLastError := 'The SD command prompt is not available.';
    Exit(False);
  end;
  if Overwrite then
    Result := RunReceive('receive overwrite', 'Ready to receive into xfer.in.')
  else
    Result := RunReceive('receive', 'Ready to receive into xfer.in.');
  if Result then
  begin
    FSlotOpen := True;
    LogText('The receive slot is open.');
  end
  else
    LogText('SD refused receive: ' + FLastError);
end;
function TSDSession.ActivateSend(const SourceFile, RecordIds: string): Boolean;
var
  CommandText, Marker, Ids: string;
  Parts: TNameArray;
  I: Integer;
  Reason: string;
begin
  Result := False;
  FLastError := '';
  if not WaitForPrompt(PromptTimeout) then
  begin
    if FLastError = '' then
      FLastError := 'The SD command prompt is not available.';
    Exit(False);
  end;

  if (Pos(' ', Trim(SourceFile)) > 0) or (Pos(#9, SourceFile) > 0) or
     (Pos(#10, SourceFile) > 0) or (Pos(#13, SourceFile) > 0) then
  begin
    FLastError := 'Download source: the SD file name must be one token with no spaces.';
    Exit(False);
  end;
  if not IsValidSdName(Trim(SourceFile), Reason) then
  begin
    FLastError := 'Download source file: ' + Reason;
    Exit(False);
  end;
  Ids := Trim(RecordIds);
  if Ids = '' then
  begin
    FLastError := 'Download source: enter at least one SD record id.';
    Exit(False);
  end;
  if (Pos(#10, Ids) > 0) or (Pos(#13, Ids) > 0) then
  begin
    FLastError := 'Download source: line breaks are not allowed in the record id list.';
    Exit(False);
  end;

  Parts := SplitTokens(Ids);
  if Length(Parts) = 0 then
  begin
    FLastError := 'Download source: enter at least one SD record id.';
    Exit(False);
  end;
  CommandText := 'send ' + Trim(SourceFile);
  for I := 0 to High(Parts) do
  begin
    if not IsValidSdName(Parts[I], Reason) then
    begin
      FLastError := Format('Download record id "%s": %s', [Parts[I], Reason]);
      Exit(False);
    end;
    CommandText := CommandText + ' ' + Parts[I];
  end;

  Marker := 'Ready to send from xfer.out.';
  FCommandStart := Length(NormalizedBuffer);
  LogText('SD command: ' + CommandText);
  try
    SendLine(CommandText);
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      Exit(False);
    end;
  end;

  Result := WaitForReady(Marker, 30000);
  if Result then
  begin
    FSlotOpen := True;
    LogText('The send slot is open.');
  end
  else
    LogText('SD refused send: ' + FLastError);
end;

function TSDSession.ActivateSendOut(const Names: TNameArray): Boolean;
const
  Marker = 'Ready to send from xfer.out.';
var
  CommandText: string;
  I: Integer;
begin
  { "SEND file id [id ...]": naming xfer.out's own files copies each onto
    itself and opens the slot for them. }
  Result := False;
  FLastError := '';
  if Length(Names) = 0 then
  begin
    FLastError := 'No files were selected.';
    Exit;
  end;
  if not WaitForPrompt(PromptTimeout) then
  begin
    FLastError := 'The SD command prompt is not available.';
    Exit;
  end;
  CommandText := 'send ' + SDDownloadDirectory;
  for I := 0 to High(Names) do
  begin
    if Pos(' ', Names[I]) > 0 then
    begin
      FLastError := 'The send command cannot name a file with a space in it: ' +
        Names[I] + '.  Rename it in SD to download it.';
      Exit;
    end;
    CommandText := CommandText + ' ' + Names[I];
  end;
  FCommandStart := Length(FNorm);
  LogText('SD command: ' + CommandText);
  try
    SendLine(CommandText);
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Result := WaitForReady(Marker, 30000);
  if Result then
  begin
    FSlotOpen := True;
    LogText('The send slot is open.');
  end
  else
    LogText('SD refused send: ' + FLastError);
end;


function IsEchoOf(const Line, CommandText: string): Boolean;
  function Squeeze(const T: string): string;
  begin
    Result := UpperCase(StringReplace(T, ' ', '', [rfReplaceAll]));
  end;
begin
  { SD's line editor echoes a typed command, sometimes redrawn with the
    spaces squeezed out; either form starts with the command's own words. }
  Result := Pos(Squeeze(Copy(CommandText, 1, 24)), Squeeze(Line)) > 0;
end;

function QuoteIds(const Names: TNameArray; First, Last: Integer): string;
var
  I: Integer;
begin
  { SD record ids in double quotes, so names with spaces stay one id.  A
    transferable name never contains a double quote. }
  Result := '';
  for I := First to Last do
    Result := Result + ' "' + Names[I] + '"';
end;

function TSDSession.CopyRecords(const FromFile, ToFile: string;
  const Names: TNameArray; Overwrite, Deleting: Boolean; out Copied: Integer;
  out Problems: string): Boolean;
const
  MaxLine = 140;   { keep each command inside the 160-column terminal }
var
  Start, Stop, I, N: Integer;
  CommandText, Options, Line: string;
  Lines: TStringList;
  R: TRegExpr;
begin
  Result := False;
  Copied := 0;
  Problems := '';
  Options := '';
  if Overwrite then
    Options := Options + ' OVERWRITING';
  if Deleting then
    Options := Options + ' DELETING';
  R := TRegExpr.Create('^\s*(\d+) record\(s\) copied');
  Lines := TStringList.Create;
  try
    Start := 0;
    while Start <= High(Names) do
    begin
      { As many ids per command as fit on one line. }
      Stop := Start;
      while (Stop < High(Names)) and (Length('COPY FROM ' + FromFile + ' TO ' + ToFile +
        QuoteIds(Names, Start, Stop + 1) + Options) <= MaxLine) do
        Inc(Stop);
      CommandText := 'COPY FROM ' + FromFile + ' TO ' + ToFile +
        QuoteIds(Names, Start, Stop) + Options;
      if not WaitForPrompt(PromptTimeout) then
      begin
        Problems := 'The SD command prompt is not available.';
        Exit;
      end;
      FCommandStart := Length(FNorm);
      LogText('SD command: ' + CommandText);
      SendLine(CommandText);
      if not WaitForCommandPrompt(60000) then
      begin
        Problems := Problems + 'SD did not finish the copy.' + LineEnding;
        Exit;
      end;
      Lines.Text := CommandOutput;
      for I := 0 to Lines.Count - 1 do
      begin
        Line := Trim(Lines[I]);
        if (Line = '') or (Line = ':') or IsEchoOf(Line, CommandText) then
          Continue;
        if R.Exec(Line) then
        begin
          if TryStrToInt(R.Match[1], N) then
            Inc(Copied, N);
        end
        else
          Problems := Problems + Line + LineEnding;
      end;
      Start := Stop + 1;
    end;
  finally
    Lines.Free;
    R.Free;
  end;
  Problems := Trim(Problems);
  if Problems <> '' then
    LogText(Problems);
  Result := Copied = Length(Names);
end;


function TSDSession.RenameRecord(const FileName, OldName, NewName: string;
  out Problems: string): Boolean;
var
  CommandText, Line: string;
  Lines: TStringList;
  I: Integer;
begin
  { CNAME file "old" TO "new" prints "'old' renamed to 'new'"; anything else
    it prints is the reason it did not. }
  Result := False;
  Problems := '';
  if not WaitForPrompt(PromptTimeout) then
  begin
    Problems := 'The SD command prompt is not available.';
    Exit;
  end;
  CommandText := 'CNAME ' + FileName + ' "' + OldName + '" TO "' + NewName + '"';
  FCommandStart := Length(FNorm);
  LogText('SD command: ' + CommandText);
  SendLine(CommandText);
  if not WaitForCommandPrompt(60000) then
  begin
    Problems := 'SD did not finish the rename.';
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := CommandOutput;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line = ':') or IsEchoOf(Line, CommandText) then
        Continue;
      if Pos('renamed to', Line) > 0 then
        Result := True
      else
        Problems := Problems + Line + LineEnding;
    end;
  finally
    Lines.Free;
  end;
  Problems := Trim(Problems);
  if Result then
    LogText(Format('%s: %s renamed to %s.', [FileName, OldName, NewName]));
end;

function TSDSession.EnsureTransferFiles(out Problems: string): Boolean;
const
  Names: array[0..1] of string = ('xfer.in', 'xfer.out');
var
  CommandText, Line, Said: string;
  Lines: TStringList;
  I, N: Integer;
  Ok: Boolean;
begin
  { SD's receive and send make xfer.in and xfer.out on first use; until then
    the SD pane has nothing to list (owner, 26 Nov 2026: the utility creates
    them).  "CREATE.FILE DATA <name> DIRECTORY" typed in lower case makes
    exactly what gpl.bp/xfer makes: a data-only directory file in the
    account's own directory and the VOC entry  <name> = F / <name>, which
    xfer's own VOC check accepts.  An existing file is left alone ("DATA part
    of file already exists"). }
  Result := True;
  Problems := '';
  for N := 0 to High(Names) do
  begin
    if not WaitForPrompt(PromptTimeout) then
    begin
      Problems := Problems + 'The SD command prompt is not available.' + LineEnding;
      Result := False;
      Break;
    end;
    CommandText := 'CREATE.FILE DATA ' + Names[N] + ' DIRECTORY';
    FCommandStart := Length(FNorm);
    SendLine(CommandText);
    if not WaitForCommandPrompt(30000) then
    begin
      Problems := Problems + 'SD did not answer CREATE.FILE for ' + Names[N] + '.' + LineEnding;
      Result := False;
      Continue;
    end;
    Ok := False;
    Said := '';
    Lines := TStringList.Create;
    try
      Lines.Text := CommandOutput;
      for I := 0 to Lines.Count - 1 do
      begin
        Line := Trim(Lines[I]);
        if (Line = '') or (Line = ':') or (Line = '::') or IsEchoOf(Line, CommandText) then
          Continue;
        if Pos('already exists', Line) > 0 then
          Ok := True
        else if Pos('Created DATA part', Line) > 0 then
        begin
          Ok := True;
          LogText('Created ' + Names[N] + ' in the SD account (it is made on first use otherwise).');
        end
        else
          Said := Said + Line + ' ';
      end;
    finally
      Lines.Free;
    end;
    if not Ok then
    begin
      Result := False;
      Problems := Problems + 'Could not create ' + Names[N] + ': ' + Trim(Said) + LineEnding;
    end;
  end;
  Problems := Trim(Problems);
end;

function TSDSession.DeleteRecords(const FileName: string; const Names: TNameArray;
  out Problems: string): Boolean;
var
  Line, CommandText: string;
  Lines: TStringList;
  I: Integer;
begin
  Result := False;
  Problems := '';
  if Length(Names) = 0 then
    Exit(True);
  if not WaitForPrompt(PromptTimeout) then
  begin
    Problems := 'The SD command prompt is not available.';
    Exit;
  end;
  CommandText := 'DELETE ' + FileName + QuoteIds(Names, 0, High(Names));
  FCommandStart := Length(FNorm);
  LogText('SD command: ' + CommandText);
  SendLine(CommandText);
  if not WaitForCommandPrompt(60000) then
  begin
    Problems := 'SD did not finish the delete.';
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := CommandOutput;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line = ':') or IsEchoOf(Line, CommandText) or
         (Pos('record(s) deleted', Line) > 0) then
        Continue;
      Problems := Problems + Line + LineEnding;
    end;
  finally
    Lines.Free;
  end;
  Problems := Trim(Problems);
  Result := Problems = '';
end;
function TSDSession.CloseTransfer: Boolean;
var
  Deadline: QWord;
  Text: string;
  P, Q: Integer;
begin
  Result := False;
  FLastSummary := '';
  if (FProcess = nil) or not FProcess.Running then
  begin
    FSlotOpen := False;
    Exit(False);
  end;
  if not FSlotOpen then
    Exit(False);

  try
    SendLine('');
  except
    end;
  FSlotOpen := False;
  Deadline := GetTickCount64 + 15000;
  while GetTickCount64 < Deadline do
  begin
    ReadAvailable(50);
    if Pos('Transfer closed', CommandOutput) > 0 then
    begin
      Result := True;
      Break;
    end;
    if not FProcess.Running and (FProcess.Output.NumBytesAvailable = 0) then
      Break;
  end;
  if not Result then
    Exit;

  { Everything SD says after "Transfer closed" up to its prompt is the
    summary: SHA-256 lines, and for receive into bp the copy report. }
  WaitForCommandPrompt(30000);
  Text := CommandOutput;
  P := Pos('Transfer closed', Text);
  Text := Copy(Text, P, MaxInt);
  Q := Length(Text);
  while (Q > 0) and (Text[Q] in [':', '>', ' ', #10, #13, #9]) do
    Dec(Q);
  FLastSummary := Trim(Copy(Text, 1, Q));
  LogText('SD transfer closed.');
  if FLastSummary <> '' then
    LogText(FLastSummary);
  { The session stays at the prompt for any further command; AbortSession
    quits it. }
  FCommandStart := Length(FNorm);
end;

function TSDSession.WaitForCommandPrompt(TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
begin
  { The prompt must appear in what followed the command; the prompt that was
    already on screen before it was sent does not count. }
  Result := False;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while GetTickCount64 < Deadline do
  begin
    ReadAvailable(40);
    if TextEndsInPrompt(CommandOutput) then
      Exit(True);
    if (FProcess = nil) or (not FProcess.Running and
      (FProcess.Output.NumBytesAvailable = 0)) then
      Exit(False);
  end;
end;

function FindEntryIndex(const Entries: TFileEntries; Count: Integer;
  const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if Entries[I].Name = Name then
      Exit(I);
  Result := -1;
end;

function TSDSession.ListRecords(const FileName: string; out Entries: TFileEntries;
  out ErrorText: string): Boolean;
const
  EchoEnd = 'COL.HDR.SUP';
var
  CommandText, Line, Messages: string;
  Lines: TStringList;
  I, Start, Count: Integer;
  Size: Int64;
  R: TRegExpr;
  Reason: string;
begin
  { Lists a file's record ids, with each record's length, from the SD prompt.
    No transfer slot is needed.  The id column is 120 wide so long names are
    not wrapped (a plain ID.ONLY listing wraps at 12). }
  Result := False;
  Entries := nil;
  ErrorText := '';
  if not IsValidSdName(FileName, Reason) or (Pos(' ', FileName) > 0) then
  begin
    ErrorText := 'Not a file name SD can list: ' + FileName;
    Exit;
  end;
  if not WaitForPrompt(PromptTimeout) then
  begin
    ErrorText := 'The SD command prompt is not available.';
    Exit;
  end;
  CommandText := 'SORT ' + FileName + ' EVAL "@ID" FMT "120L" EVAL "LEN(@RECORD)"' +
    ' FMT "10R" ID.SUP NO.PAGE COUNT.SUP HDR.SUP ' + EchoEnd;
  FCommandStart := Length(FNorm);
  LogText('SD command: list ' + FileName);
  try
    SendLine(CommandText);
  except
    on E: Exception do
    begin
      ErrorText := E.Message;
      Exit;
    end;
  end;
  if not WaitForCommandPrompt(60000) then
  begin
    ErrorText := 'SD did not finish listing ' + FileName + '.';
    Exit;
  end;

  Lines := TStringList.Create;
  R := TRegExpr.Create('^(.*\S)\s+(\d+)\s*$');
  try
    Lines.Text := CommandOutput;
    { Start after the FIRST echo of the command and skip every echo line.  The
      line editor may redraw the command more than once, and SD Core for
      Windows' ConPTY may repaint it AFTER SD's answer: starting after the
      last echo lost "File not found" there and listed a missing file as
      empty (26 Nov 2026). }
    Start := Lines.Count;
    for I := 0 to Lines.Count - 1 do
      if Pos(EchoEnd, Lines[I]) > 0 then
      begin
        Start := I + 1;
        Break;
      end;
    Count := 0;
    Messages := '';
    I := Start - 1;
    while I < Lines.Count - 1 do
    begin
      Inc(I);
      Line := TrimRight(Lines[I]);
      if (Trim(Line) = '') or (Trim(Line) = ':') or (Trim(Line) = '::') or
         (Pos(EchoEnd, Line) > 0) then
        Continue;
      { A terminal narrower than the 130-column row wraps it: the id on one
        line, the length alone on the next.  Join them back. }
      if (not R.Exec(Line)) and (I + 1 < Lines.Count) and
         TryStrToInt64(Trim(Lines[I + 1]), Size) then
      begin
        Line := Line + '  ' + Trim(Lines[I + 1]);
        Inc(I);
      end;
      if R.Exec(Line) and TryStrToInt64(R.Match[2], Size) then
      begin
        { A repaint can show a line twice; record ids are unique in a file. }
        if FindEntryIndex(Entries, Count, R.Match[1]) >= 0 then
          Continue;
        SetLength(Entries, Count + 1);
        Entries[Count].Name := R.Match[1];
        Entries[Count].Size := Size;
        Entries[Count].Modified := 0;
        Entries[Count].IsDir := False;
        Inc(Count);
      end
      else
        Messages := Messages + Trim(Line) + LineEnding;
    end;
  finally
    R.Free;
    Lines.Free;
  end;
  if (Count = 0) and (Messages <> '') then
  begin
    ErrorText := Trim(Messages);
    Exit;
  end;
  Result := True;
end;

procedure TSDSession.AbortSession;
begin
  if FProcess = nil then
    Exit;
  if FProcess.Running then
  begin
    if FSlotOpen then
    begin
      try
        SendLine('');
      except
        end;
      FSlotOpen := False;
      Sleep(250);
    end;
    try
      SendLine('quit');
    except
      end;
    Sleep(150);
  end;
  StopProcess;
end;

procedure TSDSession.StopProcess;
var
  Deadline: QWord;
begin
  if FProcess = nil then
    Exit;
  if FProcess.Running then
  begin
    try
      FProcess.Terminate(1);
    except
      end;
    Deadline := GetTickCount64 + 2000;
    while FProcess.Running and (GetTickCount64 < Deadline) do
    begin
      ReadAvailable(30);
      Sleep(10);
    end;
    if FProcess.Running then
    begin
      try
        FProcess.Terminate(9);
      except
        end;
    end;
  end;
  FreeAndNil(FProcess);
end;

end.
