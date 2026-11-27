unit uDialogs;

{ Windows opened from the main window's menu button: SSH key setup, Help and
  About.  Built in code like the main form (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Clipbrd, LCLIntf, uModels;

type
  TKeySetupForm = class(TForm)
  private
    FKeyCombo: TComboBox;
    FPassEdit: TEdit;
    FPubMemo: TMemo;
    FPubNote: TLabel;
    FNewName: TEdit;
    FNewPass1: TEdit;
    FNewPass2: TEdit;
    function AddGroup(const ACaption: string; ATop: Integer): TGroupBox;
    function AddNote(AParent: TWinControl; const AText: string; ATop: Integer): TLabel;
    procedure FillKeyList;
    procedure ShowPublicKey;
    procedure KeyChanged(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    function GetKeyFile: string;
    function GetPassphrase: string;
  public
    constructor CreateSetup(AOwner: TComponent; const AKeyFile, APassphrase: string);
    property KeyFile: string read GetKeyFile;
    property Passphrase: string read GetPassphrase;
  end;

procedure ShowAboutWindow(AOwner: TComponent);
procedure ShowHelpWindow(AOwner: TComponent);
{ Creates an Ed25519 key pair at Path; never overwrites. }
function GenerateKey(const Path, Passphrase: string; out ErrorText: string): Boolean;

implementation

uses
  Process, {$IFDEF UNIX}BaseUnix,{$ENDIF} uProcessUtil;

const
  DefaultKeyNames: array[0..2] of string = ('id_ed25519', 'id_ecdsa', 'id_rsa');

  LicenseText =
    'BSD 2-Clause License' + LineEnding + LineEnding +
    AppCopyright + LineEnding + 'All rights reserved.' + LineEnding + LineEnding +
    'Redistribution and use in source and binary forms, with or without ' +
    'modification, are permitted provided that the following conditions are met:' +
    LineEnding + LineEnding +
    '1. Redistributions of source code must retain the above copyright notice, ' +
    'this list of conditions and the following disclaimer.' + LineEnding + LineEnding +
    '2. Redistributions in binary form must reproduce the above copyright notice, ' +
    'this list of conditions and the following disclaimer in the documentation ' +
    'and/or other materials provided with the distribution.' + LineEnding + LineEnding +
    'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" ' +
    'AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE ' +
    'IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ' +
    'ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE ' +
    'LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR ' +
    'CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF ' +
    'SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS ' +
    'INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN ' +
    'CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ' +
    'ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE ' +
    'POSSIBILITY OF SUCH DAMAGE.';

  HelpText =
    'SD CORE TRANSFER UTILITY' + LineEnding +
    'Moves plain-text files between this computer and your account on an SD Core ' +
    'server, over the same ssh login you use to reach SD Core.' + LineEnding + LineEnding +

    'CONNECTING' + LineEnding +
    '1. Choose the Server type: which edition of SD Core the server runs.  It ' +
    'decides the ssh port (SD Core for Linux and for Windows use the ' +
    'machine''s ssh on port 22; the two Solo editions run their own ssh on ' +
    'port 4251, and Windows Solo is found on 24251 automatically if Windows ' +
    'has reserved 4251).' + LineEnding +
    '2. Enter the Host (name or address) and your SD Core user name.' + LineEnding +
    '3. Enter your password, or leave it empty if you sign in with an ssh key.' +
    LineEnding + '4. Click Connect.  The rest of ' +
    'the window stays grayed until the login has been checked.  While ' +
    'connected the connection details are locked; press Disconnect to change ' +
    'them.  Each listing and transfer still signs in for its own short SD Core ' +
    'session, as SD Core transfers require.' + LineEnding + LineEnding +
    'The first time you reach a server you are shown its host key fingerprint ' +
    'and asked whether to trust it.  If your administrator gave you a ' +
    'fingerprint, compare the two.  After that the key is remembered in ' +
    '~/.ssh/known_hosts.  If a server''s key ever changes you are told so and ' +
    'the connection is refused.' + LineEnding + LineEnding +
    'The password is kept in memory only and is never written to disk.' +
    LineEnding + LineEnding +

    'SSH KEYS' + LineEnding +
    'If you already use ssh keys (~/.ssh/id_ed25519 and so on, or ssh-agent), ' +
    'nothing needs setting: they are used as the ssh command would use them.  ' +
    'Use Menu > SSH key setup to choose a particular key, give its passphrase, ' +
    'create a new key, or copy your public key to give to the SD Core administrator, ' +
    'who installs it for your account.' + LineEnding + LineEnding +

    'MOVING FILES' + LineEnding +
    'Files are moved by dragging them from one pane to the other; there is no ' +
    'transfer button.  Select one or more files (Ctrl-click or Shift-click for ' +
    'several), then drag the selection onto the other pane and let go.' +
    LineEnding + LineEnding +
    'Upload and Download at the top choose the direction.  Upload puts your ' +
    'computer on the left and SD Core on the right; Download swaps them, so files ' +
    'always move from left to right.  Turn on Overwrite to replace a file of ' +
    'the same name at the destination.' + LineEnding + LineEnding +

    'THE TWO LISTS' + LineEnding +
    'The buttons above the SD Core list choose what it shows: the transfer folder ' +
    '(xfer.in when uploading, xfer.out when downloading) or your bp file.  ' +
    'The SD Core list loads by itself the first time it is shown after Connect.  ' +
    'Each list has its own Refresh button beside it: the one above the SD Core ' +
    'list lists SD Core again; the one beside the local folder re-reads that ' +
    'folder.  After a download the local folder is re-read automatically.' +
    LineEnding + LineEnding +
    'In the local list, double-click a folder to open it, use Up to go back, ' +
    'or Browse to choose another folder.' +
    LineEnding + LineEnding +

    'UPLOADING (Local -> SD Core)' + LineEnding +
    'Only plain-text files can be uploaded.' + LineEnding +
    '  - xfer.in view: the files are put into xfer.in.' + LineEnding +
    '  - bp view: the files go into xfer.in, then just those files are ' +
    'copied into bp and removed from xfer.in.  Nothing else in xfer.in is ' +
    'touched.  With Overwrite off, a program bp already has is refused before ' +
    'anything is sent.' + LineEnding + LineEnding +

    'DOWNLOADING (SD Core -> Local)' + LineEnding +
    '  - xfer.out view: lists the files waiting in xfer.out.' + LineEnding +
    '  - bp view: lists your programs.  They are copied out through xfer.out ' +
    'and those copies are removed afterwards.' + LineEnding +
    'A file whose name contains a space cannot be named in SD Core''s send ' +
    'command; rename it first (right-click > Rename).' + LineEnding + LineEnding +

    'RENAME AND DELETE' + LineEnding +
    'Right-click a file in either list for Rename and Delete.  ' +
    'Right-clicking a file that is not selected selects it.' +
    LineEnding +
    '  - SD Core list: renames or deletes in the file shown (xfer.in, xfer.out ' +
    'or bp) with SD Core''s own CNAME and DELETE.  Deleting on SD Core is permanent and ' +
    'always asks first.  Changing bp needs the same permission as editing it ' +
    'in SD Core.' + LineEnding +
    '  - Local list: renames files or folders; Delete moves them to the ' +
    'Trash, where they can be restored.' + LineEnding + LineEnding +

    'Everything is done with the mouse: buttons, dragging and the ' +
    'right-click menus.  There are no keyboard shortcuts.' + LineEnding +
    LineEnding +

    'IF SOMETHING GOES WRONG' + LineEnding +
    'Every step and every SD Core message is shown in the Activity log.  ' +
    '"File transfer is not turned on" or "may not move files" means the SD Core ' +
    'administrator must enable transfers (XFER=1 in sd.conf, and ' +
    'modify.account <you> xfer-on).';

{ ---------------------------------------------------------------- helpers }

function NewForm(AOwner: TComponent; const ACaption: string; W, H: Integer): TForm;
begin
  Result := TForm.CreateNew(AOwner);
  Result.Caption := ACaption;
  Result.Position := poOwnerFormCenter;
  Result.BorderStyle := bsSizeable;
  Result.ClientWidth := W;
  Result.ClientHeight := H;
end;

function AddButtonBar(AForm: TForm; const Captions: array of string;
  const Results: array of TModalResult): TPanel;
var
  I: Integer;
  B: TButton;
begin
  Result := TPanel.Create(AForm);
  Result.Parent := AForm;
  Result.Align := alBottom;
  Result.BevelOuter := bvNone;
  Result.AutoSize := True;
  Result.BorderSpacing.Around := 8;
  for I := High(Captions) downto 0 do
  begin
    B := TButton.Create(AForm);
    B.Parent := Result;
    B.Align := alRight;
    B.Left := 1000 - I;
    B.Width := 96;
    B.Caption := Captions[I];
    B.ModalResult := Results[I];
    B.BorderSpacing.Left := 8;
    if I = 0 then
      B.Default := True;
  end;
end;

function TextMemo(AForm: TForm; const AText: string): TMemo;
begin
  Result := TMemo.Create(AForm);
  Result.Parent := AForm;
  Result.Align := alClient;
  Result.BorderSpacing.Left := 10;
  Result.BorderSpacing.Right := 10;
  Result.ReadOnly := True;
  Result.WordWrap := True;
  Result.ScrollBars := ssAutoVertical;
  Result.Text := AText;
end;

{ ---------------------------------------------------------------- about }

type
  { A label that opens its caption, a web address, in the default browser. }
  TUrlLabel = class(TLabel)
  protected
    procedure Click; override;
  end;

procedure TUrlLabel.Click;
begin
  inherited Click;
  OpenURL(Caption);
end;

procedure ShowAboutWindow(AOwner: TComponent);
var
  F: TForm;
  Head: TLabel;
  Info: TLabel;
  Link: TUrlLabel;
begin
  F := NewForm(AOwner, 'About ' + AppName, 560, 460);
  try
    Head := TLabel.Create(F);
    Head.Parent := F;
    Head.Align := alTop;
    Head.BorderSpacing.Around := 10;
    Head.Caption := AppName + '  ' + AppVersion;
    Head.Font.Style := [fsBold];
    Head.Font.Size := 13;

    Info := TLabel.Create(F);
    Info.Parent := F;
    Info.Top := 100;
    Info.Align := alTop;
    Info.BorderSpacing.Left := 10;
    Info.BorderSpacing.Right := 10;
    Info.BorderSpacing.Bottom := 10;
    Info.WordWrap := True;
    Info.Caption := 'Moves plain-text files between this computer and an SD Core ' +
      'server over ssh.' + LineEnding + LineEnding + 'Source code:';

    Link := TUrlLabel.Create(F);
    Link.Parent := F;
    Link.Top := 200;
    Link.Align := alTop;
    Link.BorderSpacing.Left := 10;
    Link.BorderSpacing.Bottom := 10;
    Link.Caption := AppSourceUrl;
    Link.Font.Color := clBlue;
    Link.Font.Style := [fsUnderline];
    Link.Cursor := crHandPoint;
    Link.Hint := 'Open in the web browser';
    Link.ShowHint := True;

    Info := TLabel.Create(F);
    Info.Parent := F;
    Info.Top := 300;
    Info.Align := alTop;
    Info.BorderSpacing.Left := 10;
    Info.BorderSpacing.Right := 10;
    Info.BorderSpacing.Bottom := 10;
    Info.WordWrap := True;
    Info.Caption := AppCopyright + LineEnding +
      'Released under the BSD 2-Clause License:';

    AddButtonBar(F, ['Close'], [mrOK]);
    TextMemo(F, LicenseText);
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ ---------------------------------------------------------------- help }

procedure ShowHelpWindow(AOwner: TComponent);
var
  F: TForm;
  M: TMemo;
begin
  F := NewForm(AOwner, AppName + ' - Help', 680, 620);
  try
    AddButtonBar(F, ['Close'], [mrOK]);
    M := TextMemo(F, HelpText);
    M.BorderSpacing.Top := 10;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ ---------------------------------------------------------------- key setup }

constructor TKeySetupForm.CreateSetup(AOwner: TComponent;
  const AKeyFile, APassphrase: string);
var
  Intro: TLabel;
  G: TGroupBox;
  L: TLabel;
  B: TButton;
  Row: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := 'SSH key setup';
  Position := poOwnerFormCenter;
  ClientWidth := 660;
  ClientHeight := 580;
  Constraints.MinWidth := 560;
  Constraints.MinHeight := 540;

  Intro := AddNote(Self, 'Most people need nothing here.  With no key chosen, ' +
    'your usual ssh keys (~/.ssh/id_ed25519 and the like) and ssh-agent are ' +
    'used, just as the ssh command would.  Choose a key only if the SD Core server ' +
    'needs a particular one.', 0);
  Intro.BorderSpacing.Around := 10;
  Intro.Font.Color := clDefault;

  { --- key to use }
  G := AddGroup('Key to use', 100);
  Row := TPanel.Create(Self);
  Row.Parent := G;
  Row.Align := alTop;
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  Row.BorderSpacing.Around := 6;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.Caption := 'Private key ';
  B := TButton.Create(Self);
  B.Parent := Row;
  B.Align := alRight;
  B.Width := 90;
  B.Caption := 'Browse...';
  B.BorderSpacing.Left := 6;
  B.OnClick := @BrowseClick;
  FKeyCombo := TComboBox.Create(Self);
  FKeyCombo.Parent := Row;
  FKeyCombo.Align := alClient;
  FKeyCombo.Style := csDropDown;
  FKeyCombo.TextHint := '(none: use my usual keys)';
  FKeyCombo.OnChange := @KeyChanged;
  FKeyCombo.OnSelect := @KeyChanged;

  Row := TPanel.Create(Self);
  Row.Parent := G;
  Row.Top := 100;
  Row.Align := alTop;
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  Row.BorderSpacing.Left := 6;
  Row.BorderSpacing.Right := 6;
  Row.BorderSpacing.Bottom := 6;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.Caption := 'Passphrase  ';
  FPassEdit := TEdit.Create(Self);
  FPassEdit.Parent := Row;
  FPassEdit.Align := alLeft;
  FPassEdit.Left := 200;
  FPassEdit.Width := 220;
  FPassEdit.EchoMode := emPassword;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alClient;
  L.Left := 500;
  L.Layout := tlCenter;
  L.BorderSpacing.Left := 10;
  L.Font.Color := clGrayText;
  L.Caption := 'only if the key has one; kept in memory, never saved';

  { --- public key }
  G := AddGroup('Your public key: give this to the SD Core administrator', 200);
  FPubMemo := TMemo.Create(Self);
  FPubMemo.Parent := G;
  FPubMemo.Align := alTop;
  FPubMemo.Height := 76;
  FPubMemo.BorderSpacing.Around := 6;
  FPubMemo.ReadOnly := True;
  FPubMemo.WordWrap := True;
  FPubMemo.Font.Name := MonospaceFontName;
  FPubMemo.Font.Size := 9;
  Row := TPanel.Create(Self);
  Row.Parent := G;
  Row.Top := 200;
  Row.Align := alTop;
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  Row.BorderSpacing.Left := 6;
  Row.BorderSpacing.Right := 6;
  Row.BorderSpacing.Bottom := 6;
  B := TButton.Create(Self);
  B.Parent := Row;
  B.Align := alRight;
  B.Width := 150;
  B.Caption := 'Copy to clipboard';
  B.OnClick := @CopyClick;
  FPubNote := TLabel.Create(Self);
  FPubNote.Parent := Row;
  FPubNote.Align := alClient;
  FPubNote.WordWrap := True;
  FPubNote.Font.Color := clGrayText;
  FPubNote.Caption := 'The administrator adds this line to your account''s ' +
    '~/.ssh/authorized_keys on the SD Core server.  It is safe to share; never ' +
    'share the private key.';

  { --- new key }
  G := AddGroup('Create a new key', 300);
  Row := TPanel.Create(Self);
  Row.Parent := G;
  Row.Align := alTop;
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  Row.BorderSpacing.Around := 6;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.Caption := 'Save as  ';
  FNewName := TEdit.Create(Self);
  FNewName.Parent := Row;
  FNewName.Align := alClient;

  Row := TPanel.Create(Self);
  Row.Parent := G;
  Row.Top := 100;
  Row.Align := alTop;
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  Row.BorderSpacing.Left := 6;
  Row.BorderSpacing.Right := 6;
  Row.BorderSpacing.Bottom := 6;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.Caption := 'Passphrase  ';
  FNewPass1 := TEdit.Create(Self);
  FNewPass1.Parent := Row;
  FNewPass1.Align := alLeft;
  FNewPass1.Left := 100;
  FNewPass1.Width := 160;
  FNewPass1.EchoMode := emPassword;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.Left := 300;
  L.Layout := tlCenter;
  L.BorderSpacing.Left := 10;
  L.Caption := 'Again  ';
  FNewPass2 := TEdit.Create(Self);
  FNewPass2.Parent := Row;
  FNewPass2.Align := alLeft;
  FNewPass2.Left := 400;
  FNewPass2.Width := 160;
  FNewPass2.EchoMode := emPassword;
  B := TButton.Create(Self);
  B.Parent := Row;
  B.Align := alRight;
  B.Width := 110;
  B.Caption := 'Create key';
  B.OnClick := @CreateClick;
  AddNote(G, 'An Ed25519 key.  Leave the passphrase empty for a key without ' +
    'one (it is then protected only by your account''s file permissions).', 200)
    .BorderSpacing.Around := 6;

  with AddButtonBar(Self, ['OK', 'Cancel'], [mrNone, mrCancel]) do
    TButton(Controls[ControlCount - 1]).OnClick := @OkClick;

  FillKeyList;
  FKeyCombo.Text := AKeyFile;
  FPassEdit.Text := APassphrase;
  ShowPublicKey;
end;

function TKeySetupForm.AddGroup(const ACaption: string; ATop: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := Self;
  Result.Top := ATop;
  Result.Align := alTop;
  Result.AutoSize := True;
  Result.Caption := ' ' + ACaption + ' ';
  Result.BorderSpacing.Left := 10;
  Result.BorderSpacing.Right := 10;
  Result.BorderSpacing.Bottom := 8;
end;

function TKeySetupForm.AddNote(AParent: TWinControl; const AText: string;
  ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Top := ATop;
  Result.Align := alTop;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.Font.Color := clGrayText;
  Result.Caption := AText;
end;

procedure TKeySetupForm.FillKeyList;
var
  SR: TSearchRec;
  Dir, Priv, NewKeyName: string;
  I: Integer;
begin
  { Every key pair in ~/.ssh: a .pub file with its private half beside it. }
  FKeyCombo.Items.Clear;
  Dir := SshDir;
  if FindFirst(Dir + '*.pub', faAnyFile, SR) = 0 then
  begin
    repeat
      Priv := Dir + ChangeFileExt(SR.Name, '');
      if FileExists(Priv) then
        FKeyCombo.Items.Add('~/.ssh/' + ExtractFileName(Priv));
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  { A name for a new key that does not overwrite anything. }
  NewKeyName := '~/.ssh/id_ed25519';
  I := 1;
  while FileExists(ExpandHome(NewKeyName)) do
  begin
    if I = 1 then
      NewKeyName := '~/.ssh/id_ed25519_sd'
    else
      NewKeyName := '~/.ssh/id_ed25519_sd' + IntToStr(I);
    Inc(I);
  end;
  FNewName.Text := NewKeyName;
end;

procedure TKeySetupForm.ShowPublicKey;
var
  Key, Pub: string;
  I: Integer;
  L: TStringList;
begin
  Key := ExpandHome(Trim(FKeyCombo.Text));
  if Key = '' then
  begin
    { No key chosen: show the first default key ssh would offer. }
    for I := 0 to High(DefaultKeyNames) do
      if FileExists(SshDir + DefaultKeyNames[I] + '.pub') then
      begin
        Key := SshDir + DefaultKeyNames[I];
        Break;
      end;
    if Key = '' then
    begin
      FPubMemo.Text := '(You have no ssh key yet.  Create one below if the SD Core ' +
        'server is to accept a key instead of a password.)';
      Exit;
    end;
  end;
  Pub := Key + '.pub';
  if not FileExists(Pub) then
  begin
    FPubMemo.Text := '(No public key file ' + Pub + ' beside this key.)';
    Exit;
  end;
  L := TStringList.Create;
  try
    L.LoadFromFile(Pub);
    FPubMemo.Text := Trim(L.Text);
  finally
    L.Free;
  end;
end;

procedure TKeySetupForm.KeyChanged(Sender: TObject);
begin
  ShowPublicKey;
end;

procedure TKeySetupForm.BrowseClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Choose an SSH private key';
    Dlg.Filter := 'All files|*';
    Dlg.Options := Dlg.Options + [ofForceShowHidden];
    Dlg.InitialDir := ExcludeTrailingPathDelimiter(SshDir);
    if Dlg.Execute then
    begin
      FKeyCombo.Text := Dlg.FileName;
      ShowPublicKey;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TKeySetupForm.CopyClick(Sender: TObject);
begin
  if Pos('ssh-', FPubMemo.Text) = 1 then
    Clipboard.AsText := FPubMemo.Text
  else
    ShowMessage('There is no public key to copy.');
end;

{$IFDEF WINDOWS}
function GenerateKey(const Path, Passphrase: string; out ErrorText: string): Boolean;
var
  Exe, AskPass: string;
  Env: TStringList;
  R: TProcessResult;
  Args: TNameArray;
begin
  { Windows has no "script" to give ssh-keygen a terminal.  Its two passphrase
    prompts go to sd-askpass instead (SSH_ASKPASS_REQUIRE=force), which answers
    from the environment, so the passphrase is never on a command line.
    SDTU_KEYGEN lets the helper answer an empty passphrase (no passphrase). }
  Result := False;
  ErrorText := '';
  Exe := ResolveExecutable('ssh-keygen');
  if Exe = '' then
  begin
    ErrorText := 'The OpenSSH tool ssh-keygen.exe was not found.  Turn on the ' +
      'Windows optional feature "OpenSSH Client".';
    Exit;
  end;
  AskPass := AskPassExecutable;
  if AskPass = '' then
  begin
    ErrorText := 'sd-askpass.exe must be beside sd-transfer.exe to create a key.';
    Exit;
  end;
  SetLength(Args, 7);
  Args[0] := '-q';
  Args[1] := '-t';
  Args[2] := 'ed25519';
  Args[3] := '-C';
  Args[4] := LocalUserName + ' (SD Core Transfer Utility)';
  Args[5] := '-f';
  Args[6] := Path;
  Env := EnvironmentSnapshot;
  try
    SetEnvironmentValue(Env, 'SSH_ASKPASS', AskPass);
    SetEnvironmentValue(Env, 'SSH_ASKPASS_REQUIRE', 'force');
    SetEnvironmentValue(Env, 'SDTU_KEYGEN', '1');
    RemoveEnvironmentValue(Env, 'SDTU_SSH_PASSWORD');
    SetEnvironmentValue(Env, 'SDTU_SSH_PASSPHRASE', Passphrase);
    R := RunCapture(Exe, Args, Env, '', 30000);
  finally
    Env.Free;
  end;
  if R.TimedOut then
  begin
    ErrorText := 'ssh-keygen did not finish.';
    Exit;
  end;
  Result := (R.ExitCode = 0) and FileExists(Path);
  if not Result then
    ErrorText := Trim(StripAnsi(R.Output));
end;
{$ELSE}
function GenerateKey(const Path, Passphrase: string; out ErrorText: string): Boolean;
var
  Comment, Output, CommandText, Chunk: string;
  CR: Char;
  P: TProcess;
  Buf: array[0..4095] of Char;
  N: Integer;
  Deadline: QWord;
  SentFirst, SentSecond: Boolean;
begin
  Result := False;
  ErrorText := '';
  CR := #13;
  Comment := GetEnvironmentVariable('USER') + ' (SD Core Transfer Utility)';
  { Answer ssh-keygen's own prompts through a terminal, so a passphrase never
    appears on a command line other users could read.  (An empty answer means
    no passphrase; an empty "-N" argument would be dropped by TProcess.) }
  CommandText := 'ssh-keygen -q -t ed25519 -C ' + QuoteShell(Comment) + ' -f ' +
    QuoteShell(Path);
  P := TProcess.Create(nil);
  try
    P.Executable := ResolveExecutable('script');
    if P.Executable = '' then
    begin
      ErrorText := 'The "script" command is needed to set a passphrase.';
      Exit;
    end;
    P.Parameters.Add('-qec');
    P.Parameters.Add(CommandText);
    P.Parameters.Add('/dev/null');
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    Output := '';
    SentFirst := False;
    SentSecond := False;
    Deadline := GetTickCount64 + 30000;
    while (P.Running or (P.Output.NumBytesAvailable > 0)) and (GetTickCount64 < Deadline) do
    begin
      if P.Output.NumBytesAvailable > 0 then
      begin
        N := P.Output.Read(Buf, SizeOf(Buf));
        if N > 0 then
        begin
          SetString(Chunk, PChar(@Buf[0]), N);
          Output := Output + Chunk;
        end;
      end
      else
        Sleep(20);
      if (not SentSecond) and SentFirst and (Pos('again', LowerCase(Output)) > 0) then
      begin
        if Passphrase <> '' then
          P.Input.Write(Passphrase[1], Length(Passphrase));
        P.Input.Write(CR, 1);
        SentSecond := True;
      end
      else if (not SentFirst) and (Pos('enter passphrase', LowerCase(Output)) > 0) then
      begin
        if Passphrase <> '' then
          P.Input.Write(Passphrase[1], Length(Passphrase));
        P.Input.Write(CR, 1);
        SentFirst := True;
      end;
    end;
    if P.Running then
    begin
      P.Terminate(1);
      ErrorText := 'ssh-keygen did not finish.';
      Exit;
    end;
    Result := (P.ExitStatus = 0) and FileExists(Path);
    if not Result then
      ErrorText := Trim(StripAnsi(Output));
  finally
    P.Free;
  end;
end;
{$ENDIF}

procedure TKeySetupForm.CreateClick(Sender: TObject);
var
  Path, ErrorText: string;
begin
  Path := ExpandHome(Trim(FNewName.Text));
  if Path = '' then
    Exit;
  if FileExists(Path) or FileExists(Path + '.pub') then
  begin
    ShowMessage(Path + ' already exists.  Choose another name; an existing key ' +
      'is never overwritten.');
    Exit;
  end;
  if FNewPass1.Text <> FNewPass2.Text then
  begin
    ShowMessage('The two passphrases are not the same.');
    Exit;
  end;
  if not DirectoryExists(ExtractFileDir(Path)) then
  begin
    ForceDirectories(ExtractFileDir(Path));
    {$IFDEF UNIX}
    fpChmod(ExtractFileDir(Path), &700);
    {$ENDIF}
  end;
  Screen.Cursor := crHourGlass;
  try
    if not GenerateKey(Path, FNewPass1.Text, ErrorText) then
    begin
      MessageDlg('SSH key setup', 'The key was not created.' + LineEnding +
        LineEnding + ErrorText, mtError, [mbOK], 0);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  FillKeyList;
  FKeyCombo.Text := Path;
  FPassEdit.Text := FNewPass1.Text;
  FNewPass1.Text := '';
  FNewPass2.Text := '';
  ShowPublicKey;
  MessageDlg('SSH key setup', 'The key was created and is now selected.' +
    LineEnding + LineEnding + 'Copy the public key shown and give it to your ' +
    'SD Core administrator; the key works once it is installed for your account.',
    mtInformation, [mbOK], 0);
end;

procedure TKeySetupForm.OkClick(Sender: TObject);
var
  Key: string;
begin
  Key := ExpandHome(Trim(FKeyCombo.Text));
  if (Key <> '') and not FileExists(Key) then
  begin
    ShowMessage('The key file does not exist: ' + Key);
    Exit;
  end;
  ModalResult := mrOK;
end;

function TKeySetupForm.GetKeyFile: string;
begin
  Result := Trim(FKeyCombo.Text);
end;

function TKeySetupForm.GetPassphrase: string;
begin
  Result := FPassEdit.Text;
end;

end.
