program hostkey_probe;

{ Host-key check: a known server passes without a question; an unknown one
  is asked about, and answering No refuses it and saves nothing.
  Usage: hostkey_probe <known-host> <unknown-host> }

{$mode objfpc}{$H+}

uses
  SysUtils, uModels, uHostKey;

type
  TAnswer = class
    Asked: Integer;
    function Confirm(const Title, Question: string): Boolean;
    procedure Log(const Text: string);
  end;

function TAnswer.Confirm(const Title, Question: string): Boolean;
begin
  Inc(Asked);
  WriteLn('--- question: ', Title);
  WriteLn(Question);
  WriteLn('--- answered: No');
  Result := False;
end;

procedure TAnswer.Log(const Text: string);
begin
  WriteLn('log: ', Text);
end;

var
  S: TConnectionSettings;
  A: TAnswer;
  Ok: Boolean;
  ErrorText: string;
begin
  A := TAnswer.Create;
  S := Default(TConnectionSettings);
  S.UserName := 'nobody';
  S.Port := 22;

  S.Host := ParamStr(1);
  Ok := EnsureHostKnown(S, @A.Confirm, @A.Log, ErrorText);
  WriteLn('known-host=', Ok, ' asked=', A.Asked, ' error=', ErrorText);
  if (not Ok) or (A.Asked <> 0) then
    Halt(1);

  S.Host := ParamStr(2);
  Ok := EnsureHostKnown(S, @A.Confirm, @A.Log, ErrorText);
  WriteLn('unknown-host=', Ok, ' asked=', A.Asked, ' error=', ErrorText);
  if Ok or (A.Asked <> 1) then
    Halt(2);
  A.Free;
end.
