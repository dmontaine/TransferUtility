program sdaskpass;

{ OpenSSH askpass helper.  ssh runs it with its prompt as the first argument
  and reads the answer from standard output.  The answers come from the
  environment of the ssh process, set by SD Transfer Utility, and are never
  written to disk:
    SDTU_SSH_PASSPHRASE  for "Enter passphrase for key ..." prompts
    SDTU_SSH_PASSWORD    for the account password
  Any other prompt (for example a host-key yes/no question) is refused: host
  keys are confirmed in the application's own dialog before ssh runs.
  SDTU_KEYGEN=1 is set only when the program creates a key with ssh-keygen
  (Windows, which has no PTY wrapper): an empty passphrase is then a real
  answer (no passphrase) rather than a refusal. }

{$mode objfpc}{$H+}

uses
  SysUtils;

var
  Prompt, Answer: string;
  KeyGen: Boolean;
begin
  Prompt := LowerCase(ParamStr(1));
  if (Pos('yes/no', Prompt) > 0) or (Pos('fingerprint', Prompt) > 0) then
    Halt(1);
  KeyGen := GetEnvironmentVariable('SDTU_KEYGEN') = '1';
  if Pos('passphrase', Prompt) > 0 then
    Answer := GetEnvironmentVariable('SDTU_SSH_PASSPHRASE')
  else if KeyGen then
    Halt(1)
  else
    Answer := GetEnvironmentVariable('SDTU_SSH_PASSWORD');
  if (Answer = '') and not KeyGen then
    Halt(1);
  WriteLn(Answer);
end.
