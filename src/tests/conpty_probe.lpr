program conpty_probe;

{ Offline check of the terminal-text normaliser in uSDSession against output
  shaped like SD Core for Windows sends it through the server's ConPTY: lines
  started with "ESC [ row ; 1 H" instead of CR LF, spaces sent as "ESC [ n C",
  and data split across reads in the middle of an escape sequence.  It also
  checks that plain CR LF output (SD on Linux) reads as before.  No network. }

{$mode objfpc}{$H+}

uses
  SysUtils, uModels, uSDSession;

var
  Failures: Integer = 0;

procedure Check(const Name: string; Cond: Boolean; const Detail: string = '');
begin
  if Cond then
    WriteLn('PASS ', Name)
  else
  begin
    WriteLn('FAIL ', Name, ' ', Detail);
    Inc(Failures);
  end;
end;

function NewSession: TSDSession;
var
  S: TConnectionSettings;
begin
  S := Default(TConnectionSettings);
  S.Host := 'fake';
  S.Port := 22;
  S.UserName := 'probe';
  Result := TSDSession.Create(S, '', nil);
end;

const
  E = #27;
var
  T: TSDSession;
  Banner: string;
begin
  { 1. The banner and prompt as ConPTY sends them: the 26 Nov 2026 failure. }
  Banner := E + '[?25l' + E + '[2J' + E + '[m' + E + '[H' +
    E + '[28;1HSD Core for Windows, version WC2.0-0' +
    E + '[29;1H(c) 2000-2026 by Ladybridge Systems and Other Contributors' +
    E + '[30;1HThis program is free software and is supplied with ABSOLUTELY NO WARRANTY.' +
    E + '[31;1HYou are welcome to modify or redistribute this software subject to certain' +
    E + '[32;1Hconditions.' + E + '[2CFor details type CONFIG GPL, for contributors type CONFIG CONTRIB.' +
    E + '[34;1H:' + E + '[?25h';
  T := NewSession;
  try
    T.FeedOutput(Banner);
    Check('conpty prompt seen', T.AtPrompt, '[' + T.NormalizedText + ']');
    Check('conpty lines kept apart',
      Pos('Contributors' + #10 + 'This program', T.NormalizedText) > 0);
    Check('conpty spaces restored', Pos('conditions.  For details', T.NormalizedText) > 0);
  finally
    T.Free;
  end;

  { 2. The same, split into one-byte reads (escape sequences cut in half). }
  T := NewSession;
  try
    Banner := E + '[3;1HCONFIG CONTRIB.' + E + '[5;1H:';
    while Banner <> '' do
    begin
      T.FeedOutput(Copy(Banner, 1, 1));
      Delete(Banner, 1, 1);
    end;
    Check('split reads prompt seen', T.AtPrompt, '[' + T.NormalizedText + ']');
  finally
    T.Free;
  end;

  { 3. A cursor move to a column other than 1 is not a line break. }
  T := NewSession;
  try
    T.FeedOutput('LIST' + E + '[7;20Hrest' + #13#10 + ':');
    Check('mid-line move joins', Pos('LISTrest', T.NormalizedText) > 0, '[' + T.NormalizedText + ']');
    Check('mid-line then prompt', T.AtPrompt);
  finally
    T.Free;
  end;

  { 4. Plain CR LF output, as from SD on Linux, is unchanged. }
  T := NewSession;
  try
    T.FeedOutput('SD Core for Linux' + #13#10 + 'line two' + #13#10 + ':');
    Check('linux prompt seen', T.AtPrompt);
    Check('linux text unchanged', T.NormalizedText = 'SD Core for Linux' + #10 +
      'line two' + #10 + ':', '[' + T.NormalizedText + ']');
  finally
    T.Free;
  end;

  { 5. CR, an erase-line code, then LF: still one line break. }
  T := NewSession;
  try
    T.FeedOutput('a' + #13 + E + '[K' + #10 + 'b');
    Check('cr erase lf one break', T.NormalizedText = 'a' + #10 + 'b', '[' + T.NormalizedText + ']');
  finally
    T.Free;
  end;

  { 6. The prompt glued to the banner, as the old code produced, is NOT a prompt. }
  T := NewSession;
  try
    T.FeedOutput('type CONFIG CONTRIB.:');
    Check('glued prompt rejected', not T.AtPrompt);
  finally
    T.Free;
  end;

  if Failures = 0 then
    WriteLn('ALL PASS')
  else
    WriteLn(Failures, ' FAILED');
  Halt(Failures);
end.
