program sdtransfer;

{$mode objfpc}{$H+}
{ A windowed program on Windows: no console window behind the main form. }
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}

uses
  { FPC only links its thread driver when cthreads is the first unit.  Without
    it the TTransferThread that StartJob creates aborts the whole process with
    runtime error 232 the moment a job button is clicked. }
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Interfaces, Forms, uModels, uMain;

{ The program icon (sdtransfer.ico); lazbuild makes sdtransfer.res from it.
  Windows shows it for the window, the taskbar and Explorer. }
{$IFDEF WINDOWS}{$R *.res}{$ENDIF}

begin
  if ParamStr(1) = '--version' then
  begin
    { A GUI program on Windows may have no standard output to write to. }
    {$I-}
    WriteLn(AppName, ' ', AppVersion);
    {$I+}
    Halt(0);
  end;

  Application.Initialize;
  Application.Title := AppName;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
