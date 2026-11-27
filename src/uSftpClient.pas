unit uSftpClient;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, RegExpr, uModels;

type
  TSftpClient = class
  private
    FSettings: TConnectionSettings;
    FLastOutput: string;
    function BuildArguments: TNameArray;
    function BuildEnvironment: TStringList;
    function RunBatch(const BatchText, WorkDir: string;
      out Output: string; out ExitCode: Integer): Boolean;
    function LooksLikeTransferError(const Output: string): Boolean;
    function RunChunked(const Command: string; const First, Second: TNameArray;
      const FallbackError: string; out ErrorText: string): Boolean;
    function ParseLongListing(const Output: string): TFileEntries;
  public
    constructor Create(const Settings: TConnectionSettings);
    function List(out Entries: TFileEntries; out ErrorText: string): Boolean;
    function PutFiles(const LocalPaths, RemoteNames: TNameArray;
      out ErrorText: string): Boolean;
    function GetFiles(const RemoteNames, LocalPaths: TNameArray;
      out ErrorText: string): Boolean;
    function RemoveFiles(const RemoteNames: TNameArray;
      out ErrorText: string): Boolean;
    property LastOutput: string read FLastOutput;
  end;

implementation

uses
  DateUtils, uProcessUtil;

const
  { A long-listing row as printed by OpenSSH sftp "ls -l". }
  ListingPattern = '^([-dl])([rwxstST-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{1,2}:\d{2}|\d{4})\s+(.+)$';
  { Files per sftp run, so the batch sent on stdin stays far below a pipe buffer. }
  FilesPerBatch = 100;

constructor TSftpClient.Create(const Settings: TConnectionSettings);
begin
  inherited Create;
  FSettings := Settings;
  FLastOutput := '';
end;

function TSftpClient.BuildArguments: TNameArray;
  procedure Add(const Value: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Value;
  end;
begin
  Result := nil;
  { Every -o option must come BEFORE "-b": sftp turns -b into
    "-oBatchMode=yes" at the point where it reads it, and ssh keeps the first
    value it sees for an option.  With -b first, BatchMode=no below was
    ignored, so ssh never asked sd-askpass and every password login over
    SFTP was refused. }
  Add('-P');
  Add(IntToStr(FSettings.Port));
  Add('-o');
  Add('ConnectTimeout=15');
  Add('-o');
  Add('ServerAliveInterval=30');
  Add('-o');
  Add('NumberOfPasswordPrompts=1');
  Add('-o');
  { Without the askpass helper ssh would wait on a prompt nobody can answer. }
  if AskPassExecutable = '' then
    Add('BatchMode=yes')
  else
    Add('BatchMode=no');
  Add('-o');
  Add('ForwardAgent=no');
  Add('-o');
  Add('ClearAllForwardings=yes');
  Add('-o');
  Add('Compression=no');
  Add('-o');
  Add('ControlMaster=no');
  Add('-o');
  Add('ControlPath=none');
  Add('-o');
  Add('LogLevel=ERROR');
  { New host keys are confirmed in a dialog before sftp runs (uHostKey). }
  Add('-o');
  Add('StrictHostKeyChecking=yes');
  if FSettings.KeyFile <> '' then
  begin
    Add('-i');
    Add(ExpandHome(FSettings.KeyFile));
  end;
  { "-b -" reads the batch from standard input, so no batch file is written to
    a shared temporary directory.  It must stay after the -o options. }
  Add('-b');
  Add('-');
  { "--" ends option parsing, so the destination is never read as an option. }
  Add('--');
  Add(FSettings.UserName + '@' + FSettings.Host);
end;

function TSftpClient.BuildEnvironment: TStringList;
begin
  Result := EnvironmentSnapshot;
  SetEnvironmentValue(Result, 'TERM', 'xterm-256color');
  if AskPassExecutable <> '' then
  begin
    SetEnvironmentValue(Result, 'SSH_ASKPASS_REQUIRE', 'force');
    SetEnvironmentValue(Result, 'SSH_ASKPASS', AskPassExecutable);
  end;
  {$IFDEF UNIX}
  if GetEnvironmentVariable('DISPLAY') = '' then
    SetEnvironmentValue(Result, 'DISPLAY', ':0');
  {$ENDIF}
  SetSshSecrets(Result, FSettings.Password, FSettings.Passphrase);
end;

function TSftpClient.RunBatch(const BatchText, WorkDir: string;
  out Output: string; out ExitCode: Integer): Boolean;
var
  Exe: string;
  Env: TStringList;
  ResultData: TProcessResult;
begin
  Result := False;
  Output := '';
  ExitCode := -1;
  Exe := ResolveExecutable('sftp');
  if Exe = '' then
  begin
    Output := 'The OpenSSH "sftp" client was not found in PATH.';
    Exit;
  end;

  Env := BuildEnvironment;
  try
    ResultData := RunCapture(Exe, BuildArguments, Env, WorkDir, 180000, BatchText);
  finally
    Env.Free;
  end;
  Output := ResultData.Output;
  FLastOutput := Output;
  if FriendlySshError(Output, FSettings.Host, FSettings.Port,
    FSettings.Password <> '') <> '' then
    Output := FriendlySshError(Output, FSettings.Host, FSettings.Port,
    FSettings.Password <> '') +
      LineEnding + LineEnding + Output;
  ExitCode := ResultData.ExitCode;
  if ResultData.TimedOut then
  begin
    Output := Output + LineEnding + 'The SFTP operation timed out.';
    Exit;
  end;
  Result := ExitCode = 0;
end;

function TSftpClient.LooksLikeTransferError(const Output: string): Boolean;
var
  Lines: TStringList;
  I: Integer;
  Line: string;
  R: TRegExpr;
begin
  Result := False;
  Lines := TStringList.Create;
  R := TRegExpr.Create(ListingPattern);
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then
        Continue;
      { Only sftp's own messages are examined.  Echoed batch commands, progress
        lines and directory listings contain user file names, and a name such
        as "Failure report.txt" must not look like an error. }
      if (Copy(Line, 1, 5) = 'sftp>') or
         (Copy(Line, 1, 10) = 'Uploading ') or
         (Copy(Line, 1, 9) = 'Fetching ') or
         (Copy(Line, 1, 26) = 'Remote working directory: ') or
         R.Exec(Lines[I]) then
        Continue;
      if (Pos('Permission denied', Line) > 0) or
         (Pos('No such file', Line) > 0) or
         (Pos('not found', Line) > 0) or
         (Pos('Failure', Line) > 0) or
         (Pos('Couldn''t', Line) > 0) or
         (Pos('Could not', Line) > 0) or
         (Pos('Connection closed', Line) > 0) or
         (Pos('Connection refused', Line) > 0) or
         (Pos('Host key verification failed', Line) > 0) or
         (Pos('remote readdir', Line) > 0) or
         (Pos('remote open', Line) > 0) or
         (Pos('dest open', Line) > 0) or
         (Pos('not plain text', Line) > 0) or
         (Pos('over xferfile', Line) > 0) or
         (Pos('over xferslot', Line) > 0) or
         (Pos('name is there', Line) > 0) then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    R.Free;
    Lines.Free;
  end;
end;

function TSftpClient.ParseLongListing(const Output: string): TFileEntries;
var
  Lines: TStringList;
  I, Count: Integer;
  Line, Name, MonthName, DayText, TimeText: string;
  R: TRegExpr;
  Month, Day, Year, Hour, Minute, Second: LongInt;
  IsDir: Boolean;
  Size: Int64;
  Dt: TDateTime;
begin
  Result := nil;
  Count := 0;
  Lines := TStringList.Create;
  R := TRegExpr.Create;
  try
    R.Expression := ListingPattern;
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if not R.Exec(Line) then
        Continue;
      Name := R.Match[7];
      if (Name = '') or (Name = '.') or (Name = '..') then
        Continue;
      { SD refuses links; a link row would also carry " -> target" in its name. }
      if R.Match[1] = 'l' then
        Continue;
      IsDir := R.Match[1] = 'd';
      if not TryStrToInt64(R.Match[3], Size) then
        Size := 0;
      MonthName := R.Match[4];
      DayText := R.Match[5];
      TimeText := R.Match[6];
      Month := 0;
      case MonthName of
        'Jan': Month := 1;
        'Feb': Month := 2;
        'Mar': Month := 3;
        'Apr': Month := 4;
        'May': Month := 5;
        'Jun': Month := 6;
        'Jul': Month := 7;
        'Aug': Month := 8;
        'Sep': Month := 9;
        'Oct': Month := 10;
        'Nov': Month := 11;
        'Dec': Month := 12;
      end;
      Dt := 0;
      if (Month > 0) and TryStrToInt(DayText, Day) then
      begin
        if Pos(':', TimeText) > 0 then
        begin
          Year := YearOf(Date);
          if TryStrToInt(Copy(TimeText, 1, Pos(':', TimeText) - 1), Hour) and
             TryStrToInt(Copy(TimeText, Pos(':', TimeText) + 1, MaxInt), Minute) then
          begin
            Second := 0;
            try
              Dt := EncodeDate(Word(Year), Word(Month), Word(Day)) +
                EncodeTime(Word(Hour), Word(Minute), Word(Second), 0);
              { ls shows a time instead of a year for the last six months, so
                a date that lands in the future belongs to last year. }
              if Dt > Now + 1 then
                Dt := IncYear(Dt, -1);
            except
              Dt := 0;
            end;
          end;
        end
        else if TryStrToInt(TimeText, Year) then
        begin
          try
            Dt := EncodeDate(Word(Year), Word(Month), Word(Day));
          except
            Dt := 0;
          end;
        end;
      end;
      SetLength(Result, Count + 1);
      Result[Count].Name := Name;
      Result[Count].Size := Size;
      Result[Count].Modified := Dt;
      Result[Count].IsDir := IsDir;
      Inc(Count);
    end;
  finally
    R.Free;
    Lines.Free;
  end;
end;

function TSftpClient.List(out Entries: TFileEntries; out ErrorText: string): Boolean;
var
  Output: string;
  ExitCode: Integer;
begin
  Result := False;
  SetLength(Entries, 0);
  ErrorText := '';
  if not RunBatch('pwd' + LineEnding + 'ls -l' + LineEnding, GetCurrentDir, Output, ExitCode) then
  begin
    ErrorText := Trim(Output);
    if ErrorText = '' then
      ErrorText := 'SFTP could not list the SD Core transfer directory.';
    Exit;
  end;
  if LooksLikeTransferError(Output) then
  begin
    ErrorText := Trim(Output);
    if ErrorText = '' then
      ErrorText := 'SFTP reported an error while listing the SD Core transfer directory.';
    Exit;
  end;
  Entries := ParseLongListing(Output);
  Result := True;
end;

function TSftpClient.RunChunked(const Command: string;
  const First, Second: TNameArray; const FallbackError: string;
  out ErrorText: string): Boolean;
var
  I, Start: Integer;
  Batch, Output: string;
  ExitCode: Integer;
begin
  Result := False;
  ErrorText := '';
  Start := 0;
  while Start <= High(First) do
  begin
    Batch := '';
    I := Start;
    while (I <= High(First)) and (I < Start + FilesPerBatch) do
    begin
      { No "-" prefix: sftp stops at the first failure and exits non-zero. }
      Batch := Batch + Command + ' ' + QuoteSftp(First[I]);
      if Second <> nil then
        Batch := Batch + ' ' + QuoteSftp(Second[I]);
      Batch := Batch + LineEnding;
      Inc(I);
    end;
    if (not RunBatch(Batch, GetCurrentDir, Output, ExitCode)) or
       LooksLikeTransferError(Output) then
    begin
      ErrorText := Trim(Output);
      if ErrorText = '' then
        ErrorText := FallbackError;
      Exit;
    end;
    Start := I;
  end;
  Result := True;
end;

function TSftpClient.PutFiles(const LocalPaths, RemoteNames: TNameArray;
  out ErrorText: string): Boolean;
begin
  Result := False;
  ErrorText := '';
  if Length(LocalPaths) = 0 then
  begin
    ErrorText := 'No local files were selected.';
    Exit;
  end;
  if Length(LocalPaths) <> Length(RemoteNames) then
  begin
    ErrorText := 'Internal error: local and remote file counts differ.';
    Exit;
  end;
  Result := RunChunked('put', LocalPaths, RemoteNames,
    'SFTP could not upload the selected files.', ErrorText);
end;

function TSftpClient.GetFiles(const RemoteNames, LocalPaths: TNameArray;
  out ErrorText: string): Boolean;
begin
  Result := False;
  ErrorText := '';
  if Length(RemoteNames) = 0 then
  begin
    ErrorText := 'No SD Core files were selected.';
    Exit;
  end;
  if Length(RemoteNames) <> Length(LocalPaths) then
  begin
    ErrorText := 'Internal error: remote and local file counts differ.';
    Exit;
  end;
  Result := RunChunked('get', RemoteNames, LocalPaths,
    'SFTP could not download the selected files.', ErrorText);
end;

function TSftpClient.RemoveFiles(const RemoteNames: TNameArray;
  out ErrorText: string): Boolean;
begin
  { SD lets an sftp client delete only a file it has just sent in the same
    transfer, which is exactly the clean-up case this is used for. }
  ErrorText := '';
  Result := True;
  if Length(RemoteNames) > 0 then
    Result := RunChunked('rm', RemoteNames, nil,
      'SFTP could not remove the file.', ErrorText);
end;

end.
