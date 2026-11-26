program sftp_probe;

{$mode objfpc}{$H+}

uses
  SysUtils, uModels, uSftpClient;

var
  Settings: TConnectionSettings;
  Client: TSftpClient;
  Entries: TFileEntries;
  ErrorText: string;
begin
  FillChar(Settings, SizeOf(Settings), 0);
  Settings.Host := 'fake-sd';
  Settings.Port := 22;
  Settings.UserName := 'don';

  Client := TSftpClient.Create(Settings);
  try
    if not Client.List(Entries, ErrorText) then
    begin
      WriteLn('list failed: ', ErrorText);
      Halt(1);
    end;
    WriteLn('entries=', Length(Entries));
    if Length(Entries) <> 3 then
      Halt(2);
    WriteLn('name0=', Entries[0].Name, ' size0=', Entries[0].Size);
    WriteLn('name1=', Entries[1].Name, ' size1=', Entries[1].Size);
    if (Entries[0].Name <> 'hello.bas') or (Entries[0].Size <> 11) then
      Halt(3);
    if (Entries[1].Name <> 'report with spaces.txt') or (Entries[1].Size <> 23) then
      Halt(4);
    WriteLn('name2=', Entries[2].Name, ' size2=', Entries[2].Size);
    if (Entries[2].Name <> 'Failure notes.txt') or (Entries[2].Size <> 5) then
      Halt(5);
  finally
    Client.Free;
  end;
end.
