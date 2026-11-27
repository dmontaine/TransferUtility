program session_probe;

{$mode objfpc}{$H+}

uses
  SysUtils, uModels, uSDSession;

var
  Settings: TConnectionSettings;
  Session: TSDSession;
  Started, Rejected, Listed: Boolean;
  Entries: TFileEntries;
  Names: TNameArray;
  Copied: Integer;
  ErrorText: string;
  I: Integer;
begin
  FillChar(Settings, SizeOf(Settings), 0);
  Settings.Host := 'fake-sd';
  Settings.Port := 22;
  Settings.UserName := 'don';

  Session := TSDSession.Create(Settings, '', nil);
  try
    Started := Session.StartSession;
    WriteLn('start=', Started, ' error=', Session.LastError);
    if not Started then
      Halt(1);
    { The account already has both files: CREATE.FILE must leave them alone. }
    Listed := Session.EnsureTransferFiles(ErrorText);
    WriteLn('ensure-xfer-files=', Listed, ' problems=', ErrorText);
    Rejected :=Session.ActivateSend('ZZZ_NOT_AN_SD_FILE_9Q', 'NOPE');
    WriteLn('missing-source-send=', Rejected, ' error=', Session.LastError);

    if Rejected then
      Halt(2);

    { Record listing from the SD prompt (used for the bp view). }
    Listed := Session.ListRecords('bp', Entries, ErrorText);
    WriteLn('list-bp=', Listed, ' count=', Length(Entries), ' error=', ErrorText);
    for I := 0 to High(Entries) do
      WriteLn('  bp: ', Entries[I].Name, ' (', Entries[I].Size, ')');
    if not Listed then
      Halt(3);
    Listed := Session.ListRecords('xfer.out', Entries, ErrorText);
    WriteLn('list-xfer.out=', Listed, ' count=', Length(Entries), ' error=', ErrorText);
    if not Listed then
      Halt(5);
    { bp through xfer.in: COPY ... DELETING copies only the named file and
      takes it out of xfer.in; then remove it from bp again. }
    SetLength(Names, 1);
    Names[0] := 'ZZ_SDTU_PROBE';
    Listed := Session.CopyRecords('xfer.in', 'bp', Names, False, True, Copied, ErrorText);
    WriteLn('copy-to-bp=', Listed, ' copied=', Copied, ' problems=', ErrorText);
    if not Listed then
      Halt(6);
    Listed := Session.CopyRecords('xfer.in', 'bp', Names, False, True, Copied, ErrorText);
    WriteLn('copy-again=', Listed, ' copied=', Copied, ' problems=', ErrorText);
    if Listed or (Copied <> 0) then
      Halt(7);
    { Rename (right-click Rename): to a name with spaces, then a rename whose
      old name is gone must fail with SD's reason. }
    Listed := Session.RenameRecord('bp', 'ZZ_SDTU_PROBE', 'ZZ SDTU RENAMED', ErrorText);
    WriteLn('rename=', Listed, ' problems=', ErrorText);
    if not Listed then
      Halt(9);
    Listed := Session.RenameRecord('bp', 'ZZ_SDTU_PROBE', 'ZZ_OTHER', ErrorText);
    WriteLn('rename-missing=', Listed, ' problems=', ErrorText);
    if Listed or (ErrorText = '') then
      Halt(10);
    Names[0] := 'ZZ SDTU RENAMED';
    Listed := Session.DeleteRecords('bp', Names, ErrorText);
    WriteLn('delete-from-bp=', Listed, ' problems=', ErrorText);
    if not Listed then
      Halt(8);

    Listed := Session.ListRecords('NO_SUCH_FILE_ZZ9', Entries, ErrorText);
    WriteLn('list-missing=', Listed, ' error=', ErrorText);
    if Listed or (Pos('not found', ErrorText) = 0) then
      Halt(4);
  finally
    Session.AbortSession;
    Session.Free;
  end;
end.
