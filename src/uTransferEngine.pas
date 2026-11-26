unit uTransferEngine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uModels, uSDSession, uSftpClient;

type
  TTransferLog = procedure(const Text: string) of object;

  TTransferEngine = class
  private
    FSettings: TConnectionSettings;
    FLog: TTransferLog;
    FConfirm: TConfirmEvent;
    procedure Log(const Text: string);
    function LocalSize(const FileName: string): Int64;
    function FindRemote(const Entries: TFileEntries; const Name: string;
      out Entry: TFileEntry): Boolean;
    function BuildRemoteNames(const LocalPaths: TNameArray;
      out RemoteNames: TNameArray; out ErrorText: string): Boolean;
    function ValidateUploadFiles(const LocalPaths: TNameArray;
      out ErrorText: string): Boolean;
    function ValidateDownloadTargets(const RemoteNames: TNameArray;
      const LocalDir: string; Overwrite: Boolean;
      out LocalPaths: TNameArray; out ErrorText: string): Boolean;
    function StartSession(out Session: TSDSession; out ErrorText: string): Boolean;
    function MakeSftp(out Client: TSftpClient; out ErrorText: string): Boolean;
    function CloseAndSummarize(Session: TSDSession; var Summary,
      ErrorText: string): Boolean;
    function ClosedFileCount(const Summary: string): Integer;
    function CleanError(const Text: string): string;
    function ArrivedNames(const Before, After: TFileEntries;
      const Names: TNameArray): TNameArray;
    function CheckBpTargets(Session: TSDSession; const RemoteNames: TNameArray;
      Overwrite: Boolean; out ErrorText: string): Boolean;
  public
    constructor Create(const Settings: TConnectionSettings; LogProc: TTransferLog;
      ConfirmProc: TConfirmEvent);
    function TestLogin(out ErrorText: string): Boolean;
    function ListFile(const FileName: string; out Entries: TFileEntries;
      out ErrorText: string): Boolean;
    function RenameRecord(const FileName, OldName, NewName: string;
      out Entries: TFileEntries; out ErrorText: string): Boolean;
    function DeleteRecords(const FileName: string; const Names: TNameArray;
      out Entries: TFileEntries; out ErrorText: string): Boolean;
    function ListAfter(Session: TSDSession; const FileName: string;
      out Entries: TFileEntries): Boolean;
    function Upload(const LocalPaths: TNameArray; Overwrite, ToBp: Boolean;
      out Entries: TFileEntries; out Summary, ErrorText: string): Boolean;
    function Download(const SourceFile, SourceIds: string;
      const RemoteNames: TNameArray; const LocalDir: string;
      Overwrite: Boolean; out Entries: TFileEntries; out Summary,
      ErrorText: string): Boolean;
  end;

implementation

uses
  uProcessUtil, uHostKey, RegExpr;

constructor TTransferEngine.Create(const Settings: TConnectionSettings;
  LogProc: TTransferLog; ConfirmProc: TConfirmEvent);
begin
  inherited Create;
  FSettings := Settings;
  FLog := LogProc;
  FConfirm := ConfirmProc;
end;

procedure TTransferEngine.Log(const Text: string);
begin
  if Assigned(FLog) and (Text <> '') then
    FLog(Text);
end;

function TTransferEngine.CleanError(const Text: string): string;
begin
  Result := Trim(Text);
  if Length(Result) > 4000 then
    Result := Copy(Result, 1, 4000) + '...';
end;

function TTransferEngine.LocalSize(const FileName: string): Int64;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

function TTransferEngine.FindRemote(const Entries: TFileEntries;
  const Name: string; out Entry: TFileEntry): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Entries) do
    if Entries[I].Name = Name then
    begin
      Entry := Entries[I];
      Exit(True);
    end;
end;

function TTransferEngine.BuildRemoteNames(const LocalPaths: TNameArray;
  out RemoteNames: TNameArray; out ErrorText: string): Boolean;
var
  I, J: Integer;
  Name, Reason: string;
begin
  Result := False;
  ErrorText := '';
  SetLength(RemoteNames, Length(LocalPaths));
  for I := 0 to High(LocalPaths) do
  begin
    Name := ExtractFileName(ExcludeTrailingPathDelimiter(LocalPaths[I]));
    if not IsValidSdName(Name, Reason) then
    begin
      ErrorText := Format('The local file "%s" cannot be uploaded: %s', [Name, Reason]);
      Exit;
    end;
    for J := 0 to I - 1 do
      if SameFileName(RemoteNames[J], Name) then
      begin
        ErrorText := 'Two selected files have the same name: ' + Name;
        Exit;
      end;
    RemoteNames[I] := Name;
  end;
  Result := True;
end;

function TTransferEngine.ValidateUploadFiles(const LocalPaths: TNameArray;
  out ErrorText: string): Boolean;
var
  I: Integer;
  Reason, Name: string;
  Size: Int64;
begin
  Result := False;
  ErrorText := '';
  if Length(LocalPaths) = 0 then
  begin
    ErrorText := 'Select one or more local files to upload.';
    Exit;
  end;
  for I := 0 to High(LocalPaths) do
  begin
    if not FileExists(LocalPaths[I]) then
    begin
      ErrorText := 'The local file does not exist: ' + LocalPaths[I];
      Exit;
    end;
    if DirectoryExists(LocalPaths[I]) then
    begin
      ErrorText := 'SD accepts plain files only, not directories: ' + LocalPaths[I];
      Exit;
    end;
    Name := ExtractFileName(ExcludeTrailingPathDelimiter(LocalPaths[I]));
    if not IsValidSdName(Name, Reason) then
    begin
      ErrorText := Format('The local file "%s" cannot be uploaded: %s', [Name, Reason]);
      Exit;
    end;
    if not IsPlainTextFile(LocalPaths[I], Reason) then
    begin
      ErrorText := Format('The local file "%s" cannot be uploaded: %s', [Name, Reason]);
      Exit;
    end;
    Size := LocalSize(LocalPaths[I]);
    Log(Format('Ready to upload %s (%s).', [Name, FormatByteCount(Size)]));
  end;
  Result := True;
end;

function TTransferEngine.ValidateDownloadTargets(const RemoteNames: TNameArray;
  const LocalDir: string; Overwrite: Boolean; out LocalPaths: TNameArray;
  out ErrorText: string): Boolean;
var
  I: Integer;
  Reason, Dir, Target: string;
begin
  Result := False;
  ErrorText := '';
  Dir := IncludeTrailingPathDelimiter(ExpandFileName(LocalDir));
  if not DirectoryExists(Dir) then
  begin
    ErrorText := 'The local destination folder does not exist: ' + Dir;
    Exit;
  end;
  if Length(RemoteNames) = 0 then
  begin
    ErrorText := 'Select one or more SD files to download.';
    Exit;
  end;
  SetLength(LocalPaths, Length(RemoteNames));
  for I := 0 to High(RemoteNames) do
  begin
    if not IsValidSdName(RemoteNames[I], Reason) then
    begin
      ErrorText := Format('The SD file "%s" cannot be downloaded: %s', [RemoteNames[I], Reason]);
      Exit;
    end;
    Target := IncludeTrailingPathDelimiter(Dir) + RemoteNames[I];
    if DirectoryExists(Target) then
    begin
      ErrorText := 'The local destination is a directory: ' + Target;
      Exit;
    end;
    if FileExists(Target) and not Overwrite then
    begin
      ErrorText := 'The local file already exists; enable Overwrite or choose another folder: ' + Target;
      Exit;
    end;
    LocalPaths[I] := Target;
    Log('Ready to download ' + RemoteNames[I] + ' to ' + Target + '.');
  end;
  Result := True;
end;

function TTransferEngine.StartSession(out Session: TSDSession;
  out ErrorText: string): Boolean;
var
  Reason: string;
begin
  Session := nil;
  Result := False;
  if not IsValidSshTarget(FSettings.Host, FSettings.UserName, Reason) then
  begin
    ErrorText := Reason;
    Exit;
  end;
  if ((FSettings.Password <> '') or (FSettings.Passphrase <> '')) and
     (AskPassExecutable = '') then
  begin
    ErrorText := 'The sd-askpass helper was not found beside sd-transfer, so the ' +
      'password cannot be given to ssh.  Keep both files in the same folder.';
    Exit;
  end;
  { Windows Solo listens on 24251 instead of 4251 when Windows has reserved
    4251.  Use whichever answers; later sftp connections in this job follow. }
  if (FSettings.AltPort > 0) and not SshPortAnswers(FSettings.Host, FSettings.Port) then
  begin
    if SshPortAnswers(FSettings.Host, FSettings.AltPort) then
    begin
      Log(Format('Nothing answers on port %d; this server uses port %d.',
        [FSettings.Port, FSettings.AltPort]));
      FSettings.Port := FSettings.AltPort;
    end;
  end;
  { Ask about an unknown host key here, in a dialog, rather than let ssh ask
    in a terminal nobody sees. }
  if not EnsureHostKnown(FSettings, FConfirm, @Log, ErrorText) then
    Exit;
  Session := TSDSession.Create(FSettings, AskPassExecutable, @Log);
  if Session.StartSession then
  begin
    Log('SSH login succeeded; SD command prompt reached.');
    Result := True;
    Exit;
  end;
  ErrorText := CleanError(Session.LastError);
  FreeAndNil(Session);
  Result := False;
end;

function TTransferEngine.MakeSftp(out Client: TSftpClient;
  out ErrorText: string): Boolean;
begin
  Client := TSftpClient.Create(FSettings);
  ErrorText := '';
  Result := True;
end;

function TTransferEngine.CloseAndSummarize(Session: TSDSession;
  var Summary, ErrorText: string): Boolean;
begin
  { Closes the slot but leaves the session at the SD prompt, so a listing can
    follow; the caller's finally block ends the session. }
  Summary := '';
  ErrorText := '';
  if Session.SlotOpen then
  begin
    if not Session.CloseTransfer then
    begin
      ErrorText := CleanError(Session.LastError);
      if ErrorText = '' then
        ErrorText := 'SD did not confirm that the transfer closed.';
      Exit(False);
    end;
    Summary := Session.LastSummary;
  end;
  Result := True;
end;

function TTransferEngine.ArrivedNames(const Before, After: TFileEntries;
  const Names: TNameArray): TNameArray;
var
  I: Integer;
  Old, New: TFileEntry;
begin
  { Selected names that are new, or changed, in the after-listing. }
  Result := nil;
  for I := 0 to High(Names) do
    if FindRemote(After, Names[I], New) then
      if (not FindRemote(Before, Names[I], Old)) or (Old.Size <> New.Size) or
         (Old.Modified <> New.Modified) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Names[I];
      end;
end;

function TTransferEngine.CheckBpTargets(Session: TSDSession;
  const RemoteNames: TNameArray; Overwrite: Boolean; out ErrorText: string): Boolean;
var
  BpEntries: TFileEntries;
  Entry: TFileEntry;
  I: Integer;
begin
  { Refuse before anything is sent when bp already has one of the names and
    Overwrite is off: COPY would leave the file stranded in xfer.in. }
  Result := False;
  ErrorText := '';
  if not Session.ListRecords(SDProgramFile, BpEntries, ErrorText) then
  begin
    ErrorText := 'Could not list ' + SDProgramFile + ': ' + CleanError(ErrorText);
    Exit;
  end;
  if not Overwrite then
    for I := 0 to High(RemoteNames) do
      if FindRemote(BpEntries, RemoteNames[I], Entry) then
      begin
        ErrorText := SDProgramFile + ' already has ' + RemoteNames[I] +
          '.  Turn on Overwrite to replace it.';
        Exit;
      end;
  Result := True;
end;
function TTransferEngine.ListFile(const FileName: string; out Entries: TFileEntries;
  out ErrorText: string): Boolean;
var
  Session: TSDSession;
begin
  Result := False;
  Entries := nil;
  ErrorText := '';
  if not StartSession(Session, ErrorText) then
    Exit;
  try
    if not Session.ListRecords(FileName, Entries, ErrorText) then
    begin
      { xfer.in and xfer.out are made on first use: until then, empty. }
      if ((FileName = SDUploadDirectory) or (FileName = SDDownloadDirectory)) and
         (Pos('not found', LowerCase(ErrorText)) > 0) then
      begin
        Entries := nil;
        ErrorText := '';
      end
      else
      begin
        ErrorText := CleanError(ErrorText);
        Exit;
      end;
    end;
    Log(Format('%s: %d file(s).', [FileName, Length(Entries)]));
    Result := True;
  finally
    Session.AbortSession;
    Session.Free;
  end;
end;

function TTransferEngine.ListAfter(Session: TSDSession; const FileName: string;
  out Entries: TFileEntries): Boolean;
var
  ErrorText: string;
begin
  { The file as it is now, in the same session; xfer.in / xfer.out that do
    not exist yet are empty. }
  Result := Session.ListRecords(FileName, Entries, ErrorText);
  if (not Result) and (Pos('not found', LowerCase(ErrorText)) > 0) then
  begin
    Entries := nil;
    Result := True;
  end;
end;

function TTransferEngine.RenameRecord(const FileName, OldName, NewName: string;
  out Entries: TFileEntries; out ErrorText: string): Boolean;
var
  Session: TSDSession;
  Problems: string;
begin
  Result := False;
  Entries := nil;
  ErrorText := '';
  if not StartSession(Session, ErrorText) then
    Exit;
  try
    Result := Session.RenameRecord(FileName, OldName, NewName, Problems);
    if not Result then
    begin
      ErrorText := 'SD did not rename ' + OldName + ' in ' + FileName + '.';
      if Problems <> '' then
        ErrorText := ErrorText + LineEnding + LineEnding + Problems;
    end;
    ListAfter(Session, FileName, Entries);
  finally
    Session.AbortSession;
    Session.Free;
  end;
end;

function TTransferEngine.DeleteRecords(const FileName: string; const Names: TNameArray;
  out Entries: TFileEntries; out ErrorText: string): Boolean;
var
  Session: TSDSession;
  Problems: string;
begin
  Result := False;
  Entries := nil;
  ErrorText := '';
  if not StartSession(Session, ErrorText) then
    Exit;
  try
    Result := Session.DeleteRecords(FileName, Names, Problems);
    if not Result then
      ErrorText := 'SD did not delete everything from ' + FileName + ':' +
        LineEnding + LineEnding + Problems
    else
      Log(Format('%d file(s) deleted from %s.', [Length(Names), FileName]));
    ListAfter(Session, FileName, Entries);
  finally
    Session.AbortSession;
    Session.Free;
  end;
end;

function TTransferEngine.ClosedFileCount(const Summary: string): Integer;
var
  R: TRegExpr;
begin
  Result := -1;
  if Trim(Summary) = '' then
    Exit;
  R := TRegExpr.Create;
  try
    R.Expression := '([0-9]+)\s+file\(s\)';
    R.InputString := Summary;
    if R.Exec then
      Result := StrToIntDef(R.Match[1], -1);
  finally
    R.Free;
  end;
end;

function TTransferEngine.TestLogin(out ErrorText: string): Boolean;
var
  Session: TSDSession;
  Problems: string;
begin
  Result := False;
  ErrorText := '';
  if not StartSession(Session, ErrorText) then
    Exit;
  try
    Log('Login test complete.');
    { Not a reason to refuse the connection: the account still works, and
      receive/send would make the files themselves. }
    if not Session.EnsureTransferFiles(Problems) then
      Log('Note: ' + Problems);
    Result := True;
  finally
    Session.AbortSession;
    Session.Free;
  end;
end;

function TTransferEngine.Upload(const LocalPaths: TNameArray; Overwrite, ToBp: Boolean;
  out Entries: TFileEntries; out Summary, ErrorText: string): Boolean;
var
  Session: TSDSession;
  Client: TSftpClient;
  RemoteNames, LocalNames, Arrived, BadName: TNameArray;
  Before, After: TFileEntries;
  RemoveError, Problems: string;
  ReceiveOverwrite: Boolean;
  Copied: Integer;
  BpEntries: TFileEntries;
  I: Integer;
  Entry: TFileEntry;
  VerificationError: string;
  CloseOK, Verified: Boolean;
  ServerFiles: Integer;
  LocalBytes: Int64;
begin
  Result := False;
  SetLength(Entries, 0);
  Summary := '';
  ErrorText := '';
  if not ValidateUploadFiles(LocalPaths, ErrorText) then
    Exit;
  if not BuildRemoteNames(LocalPaths, RemoteNames, ErrorText) then
    Exit;
  LocalNames := LocalPaths;
  if not StartSession(Session, ErrorText) then
    Exit;
  Client := nil;
  try
    { Into bp: the files travel through xfer.in and are then copied, by name,
      with COPY ... DELETING at the SD prompt.  Only these files reach bp and
      only they leave xfer.in.  xfer.in is just a transit folder here, so a
      stale file of the same name there is replaced; the Overwrite choice
      applies to bp. }
    if ToBp and not CheckBpTargets(Session, RemoteNames, Overwrite, ErrorText) then
      Exit;
    ReceiveOverwrite := Overwrite or ToBp;
    if not Session.ActivateReceive(ReceiveOverwrite) then
    begin
      ErrorText := CleanError(Session.LastError);
      Exit;
    end;
    Client := TSftpClient.Create(FSettings);
    if not Client.List(Before, ErrorText) then
    begin
      ErrorText := CleanError(ErrorText);
      Exit;
    end;
    if not ReceiveOverwrite then
    begin
      VerificationError := '';
      for I := 0 to High(RemoteNames) do
      begin
        if FindRemote(Before, RemoteNames[I], Entry) then
        begin
          VerificationError := 'The SD file already exists (enable Overwrite to replace it): ' + RemoteNames[I];
          Break;
        end;
      end;
      if VerificationError <> '' then
      begin
        ErrorText := VerificationError;
        Exit;
      end;
    end;
    if not Client.PutFiles(LocalNames, RemoteNames, ErrorText) then
    begin
      ErrorText := CleanError(ErrorText);
      { A file that arrived whole is already kept by SD; say which ones did so
        the user does not upload them twice. }
      if Client.List(After, VerificationError) then
      begin
        Arrived := ArrivedNames(Before, After, RemoteNames);
        Entries := After;
        if Length(Arrived) > 0 then
          ErrorText := ErrorText + LineEnding + LineEnding +
            'These files did reach SD and were kept: ' + JoinNames(Arrived)
        else
          ErrorText := ErrorText + LineEnding + LineEnding +
            'None of the selected files was stored on SD.';
      end;
      Exit;
    end;
    if not Client.List(After, ErrorText) then
    begin
      ErrorText := CleanError(ErrorText);
      Exit;
    end;
    Verified := True;
    VerificationError := '';
    for I := 0 to High(RemoteNames) do
    begin
      LocalBytes := LocalSize(LocalPaths[I]);
      if not FindRemote(After, RemoteNames[I], Entry) then
      begin
        Verified := False;
        VerificationError := 'SD did not list the uploaded file: ' + RemoteNames[I];
        Break;
      end;
      if Entry.Size <> LocalBytes then
      begin
        Verified := False;
        VerificationError := Format('Size check failed for %s: local %d bytes, SD %d bytes.',
          [RemoteNames[I], LocalBytes, Entry.Size]);
        { SD lets the sender delete a file it has just sent; do not leave a
          file behind that does not match the original. }
        SetLength(BadName, 1);
        BadName[0] := RemoteNames[I];
        if Client.RemoveFiles(BadName, RemoveError) then
        begin
          VerificationError := VerificationError + '  The SD copy was removed.';
          if Client.List(After, RemoveError) then ;
        end
        else
          VerificationError := VerificationError + '  The SD copy could not be removed: ' +
            CleanError(RemoveError);
        Break;
      end;
    end;
    Entries := After;
    CloseOK := CloseAndSummarize(Session, Summary, ErrorText);
    if not Verified then
    begin
      ErrorText := VerificationError;
      Exit;
    end;
    if not CloseOK then
      Exit;
    ServerFiles := ClosedFileCount(Summary);
    if (ServerFiles >= 0) and (ServerFiles <> Length(RemoteNames)) then
    begin
      ErrorText := Format('SD reported %d received file(s), but %d were selected.',
        [ServerFiles, Length(RemoteNames)]);
      Exit;
    end;
    if ToBp then
    begin
      Session.CopyRecords(SDUploadDirectory, SDProgramFile, RemoteNames, Overwrite,
        True, Copied, Problems);
      if Copied < Length(RemoteNames) then
      begin
        ErrorText := Format('The files reached %s, but only %d of %d were copied ' +
          'into %s.  The others are still in %s.',
          [SDUploadDirectory, Copied, Length(RemoteNames), SDProgramFile, SDUploadDirectory]);
        if Problems <> '' then
          ErrorText := ErrorText + LineEnding + LineEnding + Problems;
        if Session.ListRecords(SDProgramFile, BpEntries, RemoveError) then
          Entries := BpEntries;
        Exit;
      end;
      Log(Format('%d file(s) copied into %s and removed from %s.',
        [Copied, SDProgramFile, SDUploadDirectory]));
      { Show bp, not xfer.in, after an upload into bp. }
      if Session.ListRecords(SDProgramFile, BpEntries, RemoveError) then
        Entries := BpEntries;
    end;
    if not ToBp then
      ListAfter(Session, SDUploadDirectory, Entries);
    Log(Format('Upload complete: %d file(s).', [Length(RemoteNames)]));
    Result := True;
  finally
    Client.Free;
    Session.AbortSession;
    Session.Free;
  end;
end;

function TTransferEngine.Download(const SourceFile, SourceIds: string;
  const RemoteNames: TNameArray; const LocalDir: string; Overwrite: Boolean;
  out Entries: TFileEntries; out Summary, ErrorText: string): Boolean;
var
  Session: TSDSession;
  Client: TSftpClient;
  LocalPaths, Names: TNameArray;
  Before, After: TFileEntries;
  I: Integer;
  Entry: TFileEntry;
  VerificationError: string;
  CloseOK, Verified: Boolean;
  ServerFiles: Integer;
  RemoteBytes, LocalBytes: Int64;
  SendOK: Boolean;
  OutEntries: TFileEntries;
begin
  Result := False;
  SetLength(Entries, 0);
  Summary := '';
  ErrorText := '';
  if not ValidateDownloadTargets(RemoteNames, LocalDir, Overwrite, LocalPaths,
    ErrorText) then
    Exit;
  Names := RemoteNames;
  if not StartSession(Session, ErrorText) then
    Exit;
  Client := nil;
  try
    if SourceFile = SDDownloadDirectory then
      SendOK := Session.ActivateSendOut(Names)
    else
      SendOK := Session.ActivateSend(SourceFile, SourceIds);
    if not SendOK then
    begin
      ErrorText := CleanError(Session.LastError);
      Exit;
    end;
    Client := TSftpClient.Create(FSettings);
    if not Client.List(Before, ErrorText) then
    begin
      ErrorText := CleanError(ErrorText);
      Exit;
    end;
    VerificationError := '';
    for I := 0 to High(Names) do
      if not FindRemote(Before, Names[I], Entry) then
      begin
        VerificationError := 'SD is not offering the file: ' + Names[I];
        Break;
      end;
    if VerificationError <> '' then
    begin
      ErrorText := VerificationError;
      Exit;
    end;
    if not Client.GetFiles(Names, LocalPaths, ErrorText) then
    begin
      ErrorText := CleanError(ErrorText);
      Exit;
    end;
    if not Client.List(After, ErrorText) then
    begin
      ErrorText := CleanError(ErrorText);
      Exit;
    end;
    Verified := True;
    VerificationError := '';
    for I := 0 to High(Names) do
    begin
      if not FileExists(LocalPaths[I]) then
      begin
        Verified := False;
        VerificationError := 'The local file was not created: ' + LocalPaths[I];
        Break;
      end;
      if not FindRemote(After, Names[I], Entry) then
      begin
        Verified := False;
        VerificationError := 'SD did not list the downloaded file: ' + Names[I];
        Break;
      end;
      RemoteBytes := Entry.Size;
      LocalBytes := LocalSize(LocalPaths[I]);
      if RemoteBytes <> LocalBytes then
      begin
        Verified := False;
        VerificationError := Format('Size check failed for %s: SD %d bytes, local %d bytes.',
          [Names[I], RemoteBytes, LocalBytes]);
        Break;
      end;
    end;
    Entries := After;
    CloseOK := CloseAndSummarize(Session, Summary, ErrorText);
    if not Verified then
    begin
      ErrorText := VerificationError;
      Exit;
    end;
    if not CloseOK then
      Exit;
    ServerFiles := ClosedFileCount(Summary);
    if (ServerFiles >= 0) and (ServerFiles <> Length(Names)) then
    begin
      ErrorText := Format('SD reported %d sent file(s), but %d were selected.',
        [ServerFiles, Length(Names)]);
      Exit;
    end;
    { From bp, xfer.out only carried copies for this download; remove them so
      they do not pile up there. }
    if SourceFile = SDProgramFile then
    begin
      if Session.DeleteRecords(SDDownloadDirectory, Names, VerificationError) then
        Log(Format('Removed the %d transit cop(ies) from %s.', [Length(Names), SDDownloadDirectory]))
      else
        Log('Could not remove the transit copies from ' + SDDownloadDirectory + ': ' +
          VerificationError);
    end;
    { Show xfer.out as it is now. }
    if Session.ListRecords(SDDownloadDirectory, OutEntries, VerificationError) then
      Entries := OutEntries
    else if Pos('not found', LowerCase(VerificationError)) > 0 then
      Entries := nil;
    Log(Format('Download complete: %d file(s).', [Length(Names)]));
    Result := True;
  finally
    Client.Free;
    Session.AbortSession;
    Session.Free;
  end;
end;

end.
