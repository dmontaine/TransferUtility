program close_probe;

{$mode objfpc}{$H+}

uses
  SysUtils, uModels, uSDSession;

var
  Settings: TConnectionSettings;
  Session: TSDSession;
  Ok: Boolean;
  Names: TNameArray;
begin
  Settings := Default(TConnectionSettings);
  Settings.Host := 'fake-sd';
  Settings.Port := 22;
  Settings.UserName := 'don';

  Session := TSDSession.Create(Settings, '', nil);
  try
    Ok := Session.StartSession;
    WriteLn('start=', Ok, ' error=', Session.LastError);
    if not Ok then
      Halt(1);
    Ok := Session.ActivateReceive(False);
    WriteLn('receive=', Ok, ' error=', Session.LastError);
    if not Ok then
      Halt(2);
    Ok := Session.CloseTransfer;
    WriteLn('close=', Ok, ' summary=', Session.LastSummary);
    if not Ok then
      Halt(3);

    { Download from xfer.out: "send xfer.out <names>".  The session stays at
      the prompt after a close. }
    SetLength(Names, 1);
    Names[0] := 'hello.bas';
    Ok := Session.ActivateSendOut(Names);
    WriteLn('send-xfer.out=', Ok, ' error=', Session.LastError);
    if not Ok then
      Halt(5);
    Ok := Session.CloseTransfer;
    WriteLn('close-send=', Ok);
    if not Ok then
      Halt(6);
  finally
    Session.AbortSession;
    Session.Free;
  end;
end.
