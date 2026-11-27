unit uModels;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  AppName = 'SD Core Transfer Utility';
  AppVersion = '1.1.0';
  AppCopyright = 'Copyright (c) 2026 Donald Montaine';
  AppSourceUrl = 'https://github.com/dmontaine/TransferUtility';
  SDUploadDirectory = 'xfer.in';
  SDProgramFile = 'bp';
  SDDownloadDirectory = 'xfer.out';
  SDForbiddenNameChars: set of Char = ['*', ',', '=', '>', '<', '%', '/', '+', ':', ';', '?', '"', '\'];

type
  TTransferMode = (tmUpload, tmDownload);

  TFileEntry = record
    Name: string;
    Size: Int64;
    Modified: TDateTime;
    IsDir: Boolean;
  end;

  TFileEntries = array of TFileEntry;

  TNameArray = array of string;

  TConnectionSettings = record
    Host: string;
    UserName: string;
    Password: string;
    KeyFile: string;
    Passphrase: string;     { key passphrase; memory only, like Password }
    Port: Integer;
    AltPort: Integer;       { tried when Port does not answer (Windows Solo); 0 = none }
  end;

  { Asks the person a yes/no question; called from a worker thread through
    Synchronize, so it may show a dialog. }
  TConfirmEvent = function(const Title, Question: string): Boolean of object;

  TTransferRequest = record
    Mode: TTransferMode;
    Overwrite: Boolean;
    LocalPaths: TNameArray;
    RemoteNames: TNameArray;
    LocalDir: string;
    SourceFile: string;
    SourceIds: string;
    UseBp: Boolean;         { the SD side is bp, reached through xfer.in/xfer.out }
    SdFile: string;         { the SD file the SD pane shows: xfer.in, xfer.out or bp }
    NewName: string;        { rename: the new name of RemoteNames[0] }
  end;

  TTransferOutcome = record
    Success: Boolean;
    Message: string;
    Summary: string;
    RemoteEntries: TFileEntries;
    UploadedCount: Integer;
    DownloadedCount: Integer;
  end;

function IsValidSdName(const Name: string; out Reason: string): Boolean;
function IsPlainTextFile(const FileName: string; out Reason: string): Boolean;
function FormatByteCount(Value: Int64): string;
function FormatFileTime(Value: TDateTime): string;
function JoinNames(const Values: TNameArray; const Separator: string = ', '): string;
function SplitTokens(const Text: string): TNameArray;
function IsValidSshTarget(const Host, UserName: string; out Reason: string): Boolean;

implementation

function IsValidSdName(const Name: string; out Reason: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  Reason := '';
  if Name = '' then
  begin
    Reason := 'The file name is empty.';
    Exit;
  end;
  if (Name = '.') or (Name = '..') then
  begin
    Reason := 'The SD Core transfer directory does not accept . or ...';
    Exit;
  end;
  if (Name[1] = '.') or (Name[1] = '~') then
  begin
    Reason := 'The SD Core transfer directory does not accept a name beginning with . or ~.';
    Exit;
  end;
  for I := 1 to Length(Name) do
  begin
    if Name[I] in SDForbiddenNameChars then
    begin
      Reason := Format('The SD Core transfer directory does not accept the character "%s" in a file name.', [Name[I]]);
      Exit;
    end;
    if (Ord(Name[I]) < 32) or (Ord(Name[I]) = 127) then
    begin
      Reason := 'The SD Core transfer directory does not accept control characters in a file name.';
      Exit;
    end;
    if Ord(Name[I]) >= 248 then
    begin
      Reason := 'The SD Core transfer directory does not accept a mark byte (248-255) in a file name.';
      Exit;
    end;
  end;
  Result := True;
end;

function IsPlainTextFile(const FileName: string; out Reason: string): Boolean;
const
  BufferSize = 65536;
var
  Stream: TFileStream;
  Buffer: array[0..BufferSize - 1] of Byte;
  Count, I: Integer;
begin
  Result := False;
  Reason := '';
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      repeat
        Count := Stream.Read(Buffer, SizeOf(Buffer));
        for I := 0 to Count - 1 do
        begin
          if (Buffer[I] = 0) or (Buffer[I] >= 248) then
          begin
            Reason := 'SD Core moves plain text only: this file contains a NUL byte or a byte from 248 to 255.';
            Exit;
          end;
        end;
      until Count = 0;
    finally
      Stream.Free;
    end;
    Result := True;
  except
    on E: Exception do
      Reason := E.Message;
  end;
end;

function FormatByteCount(Value: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  Amount: Double;
  Index: Integer;
begin
  if Value < 1024 then
  begin
    Result := IntToStr(Value) + ' B';
    Exit;
  end;
  Amount := Value;
  Index := 0;
  while (Amount >= 1024) and (Index < High(Units)) do
  begin
    Amount := Amount / 1024;
    Inc(Index);
  end;
  Result := FormatFloat('0.0', Amount) + ' ' + Units[Index];
end;

function FormatFileTime(Value: TDateTime): string;
begin
  if Value = 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', Value);
end;

function JoinNames(const Values: TNameArray; const Separator: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Values) do
  begin
    if I > 0 then
      Result := Result + Separator;
    Result := Result + Values[I];
  end;
end;

function SplitTokens(const Text: string): TNameArray;
var
  I, Start, Count: Integer;
begin
  { Split on runs of blanks.  Quotes have no special meaning, so a token can
    never contain a space: what the UI checks is exactly what is sent to SD. }
  Result := nil;
  Count := 0;
  I := 1;
  while I <= Length(Text) do
  begin
    while (I <= Length(Text)) and (Text[I] in [' ', #9, #10, #13]) do
      Inc(I);
    if I > Length(Text) then
      Break;
    Start := I;
    while (I <= Length(Text)) and not (Text[I] in [' ', #9, #10, #13]) do
      Inc(I);
    SetLength(Result, Count + 1);
    Result[Count] := Copy(Text, Start, I - Start);
    Inc(Count);
  end;
end;

function IsValidSshTarget(const Host, UserName: string; out Reason: string): Boolean;
  function Clean(const Value, What: string): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    if Value = '' then
    begin
      Reason := 'Enter the ' + What + '.';
      Exit;
    end;
    { A leading "-" would be read by ssh/sftp as an option. }
    if Value[1] = '-' then
    begin
      Reason := 'The ' + What + ' cannot start with "-".';
      Exit;
    end;
    for I := 1 to Length(Value) do
      if (Value[I] <= ' ') or (Value[I] = #127) then
      begin
        Reason := 'The ' + What + ' cannot contain spaces or control characters.';
        Exit;
      end;
    Result := True;
  end;
begin
  Reason := '';
  Result := Clean(Host, 'SD Core server host name or address') and
    Clean(UserName, 'SD Core user name');
  if Result and (Pos('@', UserName) > 0) then
  begin
    Reason := 'The SD Core user name cannot contain "@"; put the host in the Host field.';
    Result := False;
  end;
end;

end.
