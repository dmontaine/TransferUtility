unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, Buttons, Menus, LCLType, uModels, uConfig, uLocalPane, uRemotePane;

type
  TJobKind = (jkTest, jkPreview, jkUpload, jkDownload, jkRename, jkDelete);

  { The four SD editions this client is for, and their ssh ports.  The full
    editions use the machine's own sshd; each Solo edition runs its own. }
  TServerType = record
    Name: string;
    Port: Integer;
    AltPort: Integer;   { tried when Port does not answer; 0 = none }
  end;

const
  { Windows Solo moves to 24251 when Windows has reserved 4251. }
  ServerTypes: array[0..3] of TServerType = (
    (Name: 'SD Core for Linux'; Port: 22; AltPort: 0),
    (Name: 'SD Core for Windows'; Port: 22; AltPort: 0),
    (Name: 'SD Core Solo for Linux'; Port: 4251; AltPort: 0),
    (Name: 'SD Core Solo for Windows'; Port: 4251; AltPort: 24251));

type

  TThreadLogProc = procedure(const Text: string) of object;

  TTransferThread = class(TThread)
  private
    FSettings: TConnectionSettings;
    FKind: TJobKind;
    FRequest: TTransferRequest;
    FOnLog: TThreadLogProc;
    FOnFinished: TNotifyEvent;
    FPendingLog: string;
    FAskTitle, FAskText: string;
    FAskAnswer: Boolean;
    procedure EngineLog(const Text: string);
    function EngineConfirm(const Title, Question: string): Boolean;
    procedure SyncConfirm;
    procedure SyncLog;
    procedure SyncFinished;
  protected
    procedure Execute; override;
  public
    ResultOK: Boolean;
    ResultError: string;
    ResultMessage: string;
    ResultSummary: string;
    ResultEntries: TFileEntries;
    constructor Create(const Settings: TConnectionSettings; Kind: TJobKind;
      const Request: TTransferRequest);
    property OnLog: TThreadLogProc read FOnLog write FOnLog;
    property OnFinished: TNotifyEvent read FOnFinished write FOnFinished;
  end;


  TMainForm = class(TForm)
  private
    FConnGroup: TGroupBox;
    FServerType: TComboBox;
    FHostEdit: TEdit;
    FUserEdit: TEdit;
    FPasswordEdit: TEdit;
    FTest: TButton;
    FConnectState: TLabel;
    FMenuButton: TSpeedButton;
    FMenu: TPopupMenu;
    FKeyFile: string;
    FPassphrase: string;
    FUploadBp: Boolean;
    FDownloadBp: Boolean;
    FBpEntries: TFileEntries;
    FBpLoaded: Boolean;
    FCurrentUseBp: Boolean;
    FConnected: Boolean;
    FRenameFrom, FRenameTo: string;    { the SD rename being run }
    FDeleteNames: TNameArray;          { the SD files being deleted }
    FSdMenu: TPopupMenu;
    FLocalMenu: TPopupMenu;    { login checked with Connect; the rest of the window is usable }

    FModeBar: TPanel;
    FModeUpload: TSpeedButton;
    FModeDownload: TSpeedButton;
    FOverwrite: TCheckBox;


    FBottomPanel: TPanel;
    FStatusPanel: TPanel;
    FStatus: TLabel;
    FLog: TMemo;
    FLogSplitter: TSplitter;
    FSplitRatio: Double;

    FPanesPanel: TPanel;
    FLeftHost: TPanel;
    FRightHost: TPanel;
    FSplitter: TSplitter;
    FLocalPane: TLocalPane;
    FRemotePane: TRemotePane;

    FMode: TTransferMode;
    FConfig: TAppConfig;
    FBusy: Boolean;
    FUploadEntries: TFileEntries;
    FDownloadEntries: TFileEntries;
    FUploadLoaded: Boolean;
    FDownloadLoaded: Boolean;
    FWorker: TTransferThread;
    FCurrentKind: TJobKind;
    FCurrentMode: TTransferMode;

    procedure BuildUi;
    procedure BuildConnectionGroup;
    procedure BuildModeBar;
    procedure BuildBottomPanel;
    procedure BuildPanes;
    function NewLabel(AParent: TWinControl; const ACaption: string;
      ABold: Boolean = False): TLabel;
    function NewEdit(AParent: TWinControl; AWidth: Integer): TEdit;
    function NewButton(AParent: TWinControl; const ACaption: string;
      AWidth: Integer; AClick: TNotifyEvent): TButton;
    procedure PlaceAfter(AControl, APrev: TControl; AGap: Integer);
    procedure PlaceLabelFor(ALabel: TLabel; AControl: TControl);
    procedure PanesResize(Sender: TObject);
    procedure SplitterMoved(Sender: TObject);
    procedure SetMode(AMode: TTransferMode);
    procedure UpdateModeUi;
    procedure UpdateSnapshotForMode;
    procedure SetBusy(Value: Boolean);
    procedure SetStatus(const AText: string; IsError: Boolean = False);
    procedure LoadConfigIntoUi;
    procedure SaveUiToConfig;
    function CurrentSettings(out Settings: TConnectionSettings;
      out ErrorText: string): Boolean;
    function CurrentRequest(Kind: TJobKind; out Request: TTransferRequest;
      out ErrorText: string): Boolean;
    function SelectedLocalPaths: TNameArray;
    function SelectedRemoteNames: TNameArray;
    procedure StartJob(Kind: TJobKind);

    procedure TestClick(Sender: TObject);
    procedure UploadModeClick(Sender: TObject);
    procedure DownloadModeClick(Sender: TObject);
    procedure ServerTypeChange(Sender: TObject);
    procedure MenuButtonClick(Sender: TObject);
    procedure MenuHelpClick(Sender: TObject);
    procedure MenuKeysClick(Sender: TObject);
    procedure MenuAboutClick(Sender: TObject);
    procedure RemoteViewChange(Sender: TObject);
    procedure UpdateKeyCaption;
    procedure UpdateControlState;
    function CurrentSdFile: string;
    procedure BuildContextMenus;
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SdMenuPopup(Sender: TObject);
    procedure LocalMenuPopup(Sender: TObject);
    procedure SdRenameClick(Sender: TObject);
    procedure SdDeleteClick(Sender: TObject);
    procedure LocalRenameClick(Sender: TObject);
    procedure LocalDeleteClick(Sender: TObject);
    procedure LoadViewIfNeeded;
    function ConnectionComplete: Boolean;
    procedure Disconnect;
    procedure ConnectFieldChange(Sender: TObject);
    function UsingBp: Boolean;
    procedure LocalChanged(Sender: TObject);
    procedure LocalLog(const AText: string);
    procedure RemoteRefresh(Sender: TObject);
    procedure LocalDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure LocalDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure RemoteDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure RemoteDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ThreadLog(const AText: string);
    procedure ThreadFinished(Sender: TObject);
    procedure JobFinished(Sender: TObject);
    procedure AppendLogLine(const AText: string);
    procedure ShowError(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    { For screenshots and checks: open "help", "about" or "keys" on start. }
    procedure OpenNamedWindow(const AName: string);
    procedure OpenFromCommandLine(Data: PtrInt);
  end;

var
  MainForm: TMainForm;

implementation

uses
  uTransferEngine, uDialogs, uProcessUtil;

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := AppName;
  ClientWidth := 1220;
  ClientHeight := 780;
  Constraints.MinWidth := 1000;
  Constraints.MinHeight := 600;
  Position := poScreenCenter;
  OnCloseQuery := @FormCloseQuery;
  { The program is used entirely with the mouse: no keyboard shortcuts. }
  BuildUi;
  LoadAppConfig(FConfig);
  LoadConfigIntoUi;
  SetMode(FConfig.Mode);
  FLocalPane.LoadDirectory(FConfig.LocalDir);
  FConnected := False;
  UpdateControlState;
  FStatus.Caption := 'Choose the server type, enter the host, user and password, then press Connect.';
  if ParamStr(1) = '--open' then
    Application.QueueAsyncCall(@OpenFromCommandLine, 0);
end;

procedure TMainForm.OpenFromCommandLine(Data: PtrInt);
begin
  OpenNamedWindow(ParamStr(2));
end;

{ ---------------------------------------------------------------------------
  Layout helpers.

  Every control is positioned with LCL anchors relative to its neighbour
  instead of fixed pixel coordinates, so rows stay aligned whatever font size
  or GTK theme the desktop uses.
  --------------------------------------------------------------------------- }

function TMainForm.NewLabel(AParent: TWinControl; const ACaption: string;
  ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Layout := tlCenter;
  if ABold then
    Result.Font.Style := [fsBold];
end;

function TMainForm.NewEdit(AParent: TWinControl; AWidth: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.Width := AWidth;
end;

function TMainForm.NewButton(AParent: TWinControl; const ACaption: string;
  AWidth: Integer; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

procedure TMainForm.PlaceAfter(AControl, APrev: TControl; AGap: Integer);
begin
  { Put AControl to the right of APrev, vertically centred on it. }
  AControl.AnchorSideLeft.Control := APrev;
  AControl.AnchorSideLeft.Side := asrRight;
  AControl.AnchorSideTop.Control := APrev;
  AControl.AnchorSideTop.Side := asrCenter;
  AControl.BorderSpacing.Left := AGap;
  AControl.Anchors := [akLeft, akTop];
end;

procedure TMainForm.PlaceLabelFor(ALabel: TLabel; AControl: TControl);
begin
  { Right-align a caption against the left edge of the field it describes. }
  ALabel.AnchorSideRight.Control := AControl;
  ALabel.AnchorSideRight.Side := asrLeft;
  ALabel.AnchorSideTop.Control := AControl;
  ALabel.AnchorSideTop.Side := asrCenter;
  ALabel.BorderSpacing.Right := 6;
  ALabel.Anchors := [akRight, akTop];
end;

procedure TMainForm.BuildUi;
begin
  { alTop/alBottom siblings are stacked by their Top value, so give each band
    an explicit, increasing Top before aligning it. }
  BuildConnectionGroup;
  BuildModeBar;
  BuildBottomPanel;
  BuildPanes;
end;

procedure TMainForm.BuildConnectionGroup;
var
  I: Integer;
  Item: TMenuItem;

  { One field with its caption above it.  The caption sits at the top of the
    box; the field hangs from the caption, so every field in the row lines up.
    APrev = nil puts the field at the left edge. }
  procedure AddField(AField: TControl; const ACaption: string; APrev: TControl;
    AGap: Integer);
  var
    Lbl: TLabel;
  begin
    Lbl := NewLabel(FConnGroup, ACaption);
    Lbl.AnchorSideTop.Control := FConnGroup;
    Lbl.AnchorSideLeft.Control := AField;
    Lbl.AnchorSideLeft.Side := asrLeft;
    Lbl.Anchors := [akLeft, akTop];
    if APrev = nil then
    begin
      AField.AnchorSideLeft.Control := FConnGroup;
      AField.BorderSpacing.Left := 8;
    end
    else
    begin
      AField.AnchorSideLeft.Control := APrev;
      AField.AnchorSideLeft.Side := asrRight;
      AField.BorderSpacing.Left := AGap;
    end;
    AField.AnchorSideTop.Control := Lbl;
    AField.AnchorSideTop.Side := asrBottom;
    AField.BorderSpacing.Top := 2;
    AField.BorderSpacing.Bottom := 4;
    AField.Anchors := [akLeft, akTop];
  end;

begin
  FConnGroup := TGroupBox.Create(Self);
  FConnGroup.Parent := Self;
  FConnGroup.Top := 0;
  FConnGroup.Align := alTop;
  FConnGroup.AutoSize := True;
  FConnGroup.BorderSpacing.Around := 6;
  FConnGroup.Caption := ' SSH connection to the SD Core server ';
  FConnGroup.ChildSizing.TopBottomSpacing := 2;

  { One row: Server, Host, User, Password, Connect, state, menu.  Widths
    are chosen so the row still fits at the window's minimum width. }
  FServerType := TComboBox.Create(Self);
  FServerType.Parent := FConnGroup;
  FServerType.Style := csDropDownList;
  FServerType.Width := 210;
  for I := 0 to High(ServerTypes) do
    FServerType.Items.Add(ServerTypes[I].Name);
  FServerType.Hint := 'Which SD Core edition the server runs.  This decides the ssh ' +
    'port: 22 for SD Core, 4251 for SD Core Solo.';
  FServerType.ShowHint := True;
  FServerType.OnChange := @ServerTypeChange;
  AddField(FServerType, 'Server', nil, 0);

  FHostEdit := NewEdit(FConnGroup, 180);
  AddField(FHostEdit, 'Host', FServerType, 10);

  FUserEdit := NewEdit(FConnGroup, 130);
  AddField(FUserEdit, 'User', FHostEdit, 10);

  FPasswordEdit := NewEdit(FConnGroup, 160);
  FPasswordEdit.EchoMode := emPassword;
  FPasswordEdit.TextHint := 'empty if you use a key';
  FPasswordEdit.Hint := 'Kept in memory only; never written to the settings file.';
  FPasswordEdit.ShowHint := True;
  AddField(FPasswordEdit, 'Password', FUserEdit, 10);

  FTest := NewButton(FConnGroup, 'Connect', 100, @TestClick);
  FTest.Font.Style := [fsBold];
  PlaceAfter(FTest, FPasswordEdit, 14);

  FConnectState := NewLabel(FConnGroup, 'Not connected', True);
  PlaceAfter(FConnectState, FTest, 12);

  { Menu button at the top right: Help, SSH key setup, About. }
  FMenuButton := TSpeedButton.Create(Self);
  FMenuButton.Parent := FConnGroup;
  FMenuButton.Caption := #$E2#$98#$B0;   { U+2630 "trigram for heaven", the usual menu glyph }
  FMenuButton.Font.Size := 14;
  FMenuButton.Width := 40;
  FMenuButton.Height := 34;
  FMenuButton.Flat := True;
  FMenuButton.Hint := 'Menu: help, SSH key setup, about';
  FMenuButton.ShowHint := True;
  FMenuButton.AnchorSideRight.Control := FConnGroup;
  FMenuButton.AnchorSideRight.Side := asrRight;
  FMenuButton.AnchorSideTop.Control := FServerType;
  FMenuButton.AnchorSideTop.Side := asrCenter;
  FMenuButton.BorderSpacing.Right := 6;
  FMenuButton.Anchors := [akRight, akTop];
  FMenuButton.OnClick := @MenuButtonClick;

  FMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Help';
  Item.OnClick := @MenuHelpClick;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'SSH key setup...';
  Item.OnClick := @MenuKeysClick;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'About ' + AppName;
  Item.OnClick := @MenuAboutClick;
  FMenu.Items.Add(Item);

  FHostEdit.OnChange := @ConnectFieldChange;
  FUserEdit.OnChange := @ConnectFieldChange;
  FPasswordEdit.OnChange := @ConnectFieldChange;
end;

procedure TMainForm.BuildModeBar;
begin
  FModeBar := TPanel.Create(Self);
  FModeBar.Parent := Self;
  FModeBar.Top := 1000;
  FModeBar.Align := alTop;
  FModeBar.AutoSize := True;
  FModeBar.BevelOuter := bvNone;
  FModeBar.BorderSpacing.Left := 6;
  FModeBar.BorderSpacing.Right := 6;
  FModeBar.ChildSizing.TopBottomSpacing := 2;

  FModeUpload := TSpeedButton.Create(Self);
  FModeUpload.Parent := FModeBar;
  FModeUpload.Width := 170;
  FModeUpload.Height := 34;
  FModeUpload.Caption := 'Upload:  Local -> SD Core';
  FModeUpload.GroupIndex := 1;
  FModeUpload.AllowAllUp := False;
  FModeUpload.Down := True;
  FModeUpload.OnClick := @UploadModeClick;
  FModeUpload.AnchorSideLeft.Control := FModeBar;
  FModeUpload.AnchorSideTop.Control := FModeBar;
  FModeUpload.BorderSpacing.Top := 4;
  FModeUpload.BorderSpacing.Bottom := 4;
  FModeUpload.Anchors := [akLeft, akTop];

  FModeDownload := TSpeedButton.Create(Self);
  FModeDownload.Parent := FModeBar;
  FModeDownload.Width := 170;
  FModeDownload.Height := 34;
  FModeDownload.Caption := 'Download:  SD Core -> Local';
  FModeDownload.GroupIndex := 1;
  FModeDownload.AllowAllUp := False;
  FModeDownload.OnClick := @DownloadModeClick;
  PlaceAfter(FModeDownload, FModeUpload, 0);



  FOverwrite := TCheckBox.Create(Self);
  FOverwrite.Parent := FModeBar;
  FOverwrite.Caption := 'Overwrite existing files';
  { Files are transferred by dragging them between the panes; there is no
    separate transfer button. }
  PlaceAfter(FOverwrite, FModeDownload, 24);
end;

procedure TMainForm.BuildBottomPanel;
var
  LogTitle: TLabel;
begin
  { Status line: the very bottom of the window. }
  FStatusPanel := TPanel.Create(Self);
  FStatusPanel.Parent := Self;
  FStatusPanel.Top := 30000;
  FStatusPanel.Align := alBottom;
  FStatusPanel.Height := 26;
  FStatusPanel.BevelOuter := bvLowered;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := FStatusPanel;
  FStatus.Align := alClient;
  FStatus.AutoSize := False;
  FStatus.Layout := tlCenter;
  FStatus.BorderSpacing.Left := 8;
  FStatus.Caption := 'Ready';

  { Activity log above the status line. }
  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Top := 20000;
  FBottomPanel.Align := alBottom;
  FBottomPanel.Height := 170;
  FBottomPanel.BevelOuter := bvNone;
  FBottomPanel.BorderSpacing.Left := 6;
  FBottomPanel.BorderSpacing.Right := 6;
  FBottomPanel.BorderSpacing.Bottom := 4;

  LogTitle := NewLabel(FBottomPanel, 'Activity and SD Core server responses', True);
  LogTitle.Align := alTop;
  LogTitle.BorderSpacing.Bottom := 2;

  FLog := TMemo.Create(Self);
  FLog.Parent := FBottomPanel;
  FLog.Align := alClient;
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssAutoBoth;
  FLog.WordWrap := False;
  FLog.Font.Name := MonospaceFontName;
  FLog.Font.Size := 9;

  { Draggable divider between the file panes and the log. }
  FLogSplitter := TSplitter.Create(Self);
  FLogSplitter.Parent := Self;
  FLogSplitter.Top := 10000;
  FLogSplitter.Align := alBottom;
  FLogSplitter.Height := 6;
  FLogSplitter.ResizeAnchor := akBottom;
  FLogSplitter.MinSize := 80;
end;

procedure TMainForm.BuildPanes;
var
  EmptyEntries: TFileEntries;
begin
  FPanesPanel := TPanel.Create(Self);
  FPanesPanel.Parent := Self;
  FPanesPanel.Align := alClient;
  FPanesPanel.BevelOuter := bvNone;
  FPanesPanel.BorderSpacing.Left := 6;
  FPanesPanel.BorderSpacing.Right := 6;
  FPanesPanel.BorderSpacing.Top := 4;
  FPanesPanel.OnResize := @PanesResize;

  FLeftHost := TPanel.Create(Self);
  FLeftHost.Parent := FPanesPanel;
  FLeftHost.Left := 0;
  FLeftHost.Align := alLeft;
  FLeftHost.Width := 600;
  FLeftHost.BevelOuter := bvNone;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := FPanesPanel;
  FSplitter.Left := 700;
  FSplitter.Align := alLeft;
  FSplitter.Width := 8;
  FSplitter.MinSize := 300;
  FSplitter.OnMoved := @SplitterMoved;

  FRightHost := TPanel.Create(Self);
  FRightHost.Parent := FPanesPanel;
  FRightHost.Align := alClient;
  FRightHost.BevelOuter := bvNone;

  FSplitRatio := 0.5;

  FLocalPane := TLocalPane.Create(Self);
  FLocalPane.Parent := FLeftHost;
  FLocalPane.Align := alClient;
  FLocalPane.OnLog := @LocalLog;
  FLocalPane.OnChanged := @LocalChanged;

  FRemotePane := TRemotePane.Create(Self);
  FRemotePane.Parent := FRightHost;
  FRemotePane.Align := alClient;
  FRemotePane.OnRefresh := @RemoteRefresh;
  FRemotePane.OnViewChange := @RemoteViewChange;

  FLocalPane.ListView.OnDragOver := @LocalDragOver;
  FLocalPane.ListView.OnDragDrop := @LocalDragDrop;
  FRemotePane.ListView.OnDragOver := @RemoteDragOver;
  FRemotePane.ListView.OnDragDrop := @RemoteDragDrop;

  SetLength(EmptyEntries, 0);
  FRemotePane.SetEntries(EmptyEntries);
  BuildContextMenus;
end;

procedure TMainForm.PanesResize(Sender: TObject);
var
  Avail: Integer;
begin
  { Keep the user's left/right proportion when the window is resized. }
  Avail := FPanesPanel.ClientWidth - FSplitter.Width;
  if Avail > 0 then
    FLeftHost.Width := Round(Avail * FSplitRatio);
  FLocalPane.FitColumns;
  FRemotePane.FitColumns;
end;

procedure TMainForm.SplitterMoved(Sender: TObject);
var
  Avail: Integer;
begin
  Avail := FPanesPanel.ClientWidth - FSplitter.Width;
  if Avail > 0 then
    FSplitRatio := FLeftHost.Width / Avail;
  FLocalPane.FitColumns;
  FRemotePane.FitColumns;
end;


procedure TMainForm.SetMode(AMode: TTransferMode);
begin
  if FBusy then
    Exit;
  FMode := AMode;

  FLocalPane.Align := alNone;
  FRemotePane.Align := alNone;
  if AMode = tmUpload then
  begin
    if FLocalPane.Parent <> FLeftHost then
      FLocalPane.Parent := FLeftHost;
    if FRemotePane.Parent <> FRightHost then
      FRemotePane.Parent := FRightHost;
  end
  else
  begin
    if FRemotePane.Parent <> FLeftHost then
      FRemotePane.Parent := FLeftHost;
    if FLocalPane.Parent <> FRightHost then
      FLocalPane.Parent := FRightHost;
  end;
  FLocalPane.Align := alClient;
  FRemotePane.Align := alClient;
  FLocalPane.Visible := True;
  FRemotePane.Visible := True;

  FModeUpload.Down := AMode = tmUpload;
  FModeDownload.Down := AMode = tmDownload;
  if AMode = tmUpload then
  begin
    FRemotePane.SetXferName(SDUploadDirectory);
    FRemotePane.ShowBp := FUploadBp;
  end
  else
  begin
    FRemotePane.SetXferName(SDDownloadDirectory);
    FRemotePane.ShowBp := FDownloadBp;
  end;
  UpdateModeUi;
  UpdateSnapshotForMode;
  FPanesPanel.Realign;
  { The panes just changed sides (and widths); a list's own resize event is
    not always raised for that, so fit the columns here. }
  FLocalPane.FitColumns;
  FRemotePane.FitColumns;
end;

procedure TMainForm.UpdateModeUi;
begin
  if FMode = tmUpload then
  begin
    if FUploadBp then
    begin
      FRemotePane.SetTitle('SD Core server - bp (uploads go through xfer.in)',
        'records of your bp file');
      FLocalPane.SetDropHint('Drag selected local files onto the SD Core pane to upload them into bp.');
      FRemotePane.SetDropHint('Drop local files here; SD Core copies them into bp when the transfer ends.');
      SetStatus('Upload into bp. Drag local files onto the bp list; they travel through xfer.in.', False);
    end
    else
    begin
      FRemotePane.SetDirectoryName(SDUploadDirectory, True);
      FLocalPane.SetDropHint('Drag selected local files onto the SD Core pane to upload.');
      FRemotePane.SetDropHint('Drop local files here to upload into xfer.in.');
      SetStatus('Upload mode. Drag local files onto the SD Core pane to upload them into xfer.in.', False);
    end;
  end
  else
  begin
    if FDownloadBp then
    begin
      FRemotePane.SetTitle('SD Core server - bp (downloads go through xfer.out)',
        'records of your bp file');
      FLocalPane.SetDropHint('Drop bp records here to download them into this folder.');
      FRemotePane.SetDropHint('Select bp records, then drag them to the local pane.');
      SetStatus('Download from bp. Drag programs from the bp list to the local pane.', False);
    end
    else
    begin
      FRemotePane.SetTitle('SD Core server - xfer.out (downloads)',
        'files waiting in xfer.out');
      FLocalPane.SetDropHint('Drop SD Core files here to download them into this folder.');
      FRemotePane.SetDropHint('Select files waiting in xfer.out, then drag them to the local pane.');
      SetStatus('Download mode. Drag files from xfer.out to the local pane.', False);
    end;
  end;
end;
procedure TMainForm.UpdateSnapshotForMode;
var
  EmptyEntries: TFileEntries;
begin
  SetLength(EmptyEntries, 0);
  if UsingBp then
  begin
    if FBpLoaded then
      FRemotePane.SetEntries(FBpEntries)
    else
      FRemotePane.SetEntries(EmptyEntries);
  end
  else if FMode = tmUpload then
  begin
    if FUploadLoaded then
      FRemotePane.SetEntries(FUploadEntries)
    else
      FRemotePane.SetEntries(EmptyEntries);
  end
  else
  begin
    if FDownloadLoaded then
      FRemotePane.SetEntries(FDownloadEntries)
    else
      FRemotePane.SetEntries(EmptyEntries);
  end;
end;

function TMainForm.UsingBp: Boolean;
begin
  if FMode = tmUpload then
    Result := FUploadBp
  else
    Result := FDownloadBp;
end;

procedure TMainForm.RemoteViewChange(Sender: TObject);
begin
  if FBusy then
    Exit;
  if FMode = tmUpload then
    FUploadBp := FRemotePane.ShowBp
  else
    FDownloadBp := FRemotePane.ShowBp;
  SetMode(FMode);
  LoadViewIfNeeded;
end;

procedure TMainForm.LoadViewIfNeeded;
begin
  { Once connected, a view shown for the first time lists itself.  Before
    Connect nothing here can run. }
  if FBusy or not FConnected then
    Exit;
  if UsingBp then
  begin
    if not FBpLoaded then
      StartJob(jkPreview);
  end
  else if FMode = tmUpload then
  begin
    if not FUploadLoaded then
      StartJob(jkPreview);
  end
  else if not FDownloadLoaded then
    StartJob(jkPreview);
end;
procedure TMainForm.SetBusy(Value: Boolean);
begin
  FBusy := Value;
  if Value then
    Screen.Cursor := crHourGlass
  else
    Screen.Cursor := crDefault;
  UpdateControlState;
end;

function TMainForm.ConnectionComplete: Boolean;
begin
  { The password may stay empty: people who sign in with a key have none. }
  Result := (FServerType.ItemIndex >= 0) and (Trim(FHostEdit.Text) <> '') and
    (Trim(FUserEdit.Text) <> '');
end;

procedure TMainForm.UpdateControlState;
var
  Fields, Work: Boolean;
begin
  { Until Connect has checked the login, only the connection fields, the menu
    and the log are usable.  While connected the fields are locked, because
    every listing and transfer signs in again with them. }
  Fields := (not FBusy) and (not FConnected);
  Work := (not FBusy) and FConnected;

  FServerType.Enabled := Fields;
  FHostEdit.Enabled := Fields;
  FUserEdit.Enabled := Fields;
  FPasswordEdit.Enabled := Fields;
  FMenuButton.Enabled := not FBusy;

  if FConnected then
    FTest.Caption := 'Disconnect'
  else
    FTest.Caption := 'Connect';
  FTest.Enabled := (not FBusy) and (FConnected or ConnectionComplete);

  FModeUpload.Enabled := Work;
  FModeDownload.Enabled := Work;
  FOverwrite.Enabled := Work;
  FLocalPane.Enabled := Work;
  FRemotePane.Enabled := Work;

  if FBusy then
    FConnectState.Caption := 'Working...'
  else if FConnected then
    FConnectState.Caption := 'Connected'
  else
    FConnectState.Caption := 'Not connected';
end;

procedure TMainForm.ConnectFieldChange(Sender: TObject);
begin
  UpdateControlState;
end;

procedure TMainForm.Disconnect;
var
  EmptyEntries: TFileEntries;
begin
  FConnected := False;
  { The lists belong to that login; do not show them to the next one. }
  FUploadLoaded := False;
  FDownloadLoaded := False;
  FBpLoaded := False;
  SetLength(EmptyEntries, 0);
  FUploadEntries := EmptyEntries;
  FDownloadEntries := EmptyEntries;
  FBpEntries := EmptyEntries;
  UpdateSnapshotForMode;
  UpdateControlState;
  AppendLogLine('--- Disconnected ---');
  SetStatus('Disconnected.  Change the connection details if needed, then press Connect.', False);
end;
procedure TMainForm.SetStatus(const AText: string; IsError: Boolean);
begin
  FStatus.Caption := AText;
  if IsError then
    FStatus.Font.Color := clRed
  else
    FStatus.Font.Color := clWindowText;
end;

procedure TMainForm.AppendLogLine(const AText: string);
begin
  if FLog.Lines.Count > 3000 then
    while FLog.Lines.Count > 2000 do
      FLog.Lines.Delete(0);
  FLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + AText);
  FLog.SelStart := Length(FLog.Text);
  FLog.SelLength := 0;
end;

procedure TMainForm.LoadConfigIntoUi;
begin
  FServerType.ItemIndex := FConfig.ServerType;
  FHostEdit.Text := FConfig.Connection.Host;
  FUserEdit.Text := FConfig.Connection.UserName;
  if Trim(FUserEdit.Text) = '' then
    FUserEdit.Text := GetEnvironmentVariable('USER');
  FPasswordEdit.Text := '';
  FKeyFile := FConfig.Connection.KeyFile;
  FPassphrase := '';
  FUploadBp := FConfig.UploadToBp;
  FDownloadBp := FConfig.DownloadFromBp;
  UpdateKeyCaption;
  FOverwrite.Checked := FConfig.Overwrite;
  FConnectState.Caption := 'Not connected';
end;

procedure TMainForm.SaveUiToConfig;
begin
  FConfig.Connection.Host := Trim(FHostEdit.Text);
  FConfig.Connection.Port := ServerTypes[FServerType.ItemIndex].Port;
  FConfig.Connection.UserName := Trim(FUserEdit.Text);
  FConfig.Connection.KeyFile := FKeyFile;
  FConfig.ServerType := FServerType.ItemIndex;
  FConfig.UploadToBp := FUploadBp;
  FConfig.DownloadFromBp := FDownloadBp;
  FConfig.Mode := FMode;
  FConfig.LocalDir := FLocalPane.CurrentPath;
  FConfig.Overwrite := FOverwrite.Checked;
  try
    SaveAppConfig(FConfig);
  except
    on E: Exception do
      AppendLogLine('Could not save settings: ' + E.Message);
  end;
end;

function TMainForm.CurrentSettings(out Settings: TConnectionSettings;
  out ErrorText: string): Boolean;
begin
  Result := False;
  ErrorText := '';
  Settings.Host := Trim(FHostEdit.Text);
  if FServerType.ItemIndex < 0 then
  begin
    ErrorText := 'Choose the server type.';
    Exit;
  end;
  Settings.Port := ServerTypes[FServerType.ItemIndex].Port;
  Settings.AltPort := ServerTypes[FServerType.ItemIndex].AltPort;
  Settings.UserName := Trim(FUserEdit.Text);
  Settings.Password := FPasswordEdit.Text;
  Settings.KeyFile := ExpandHome(FKeyFile);
  Settings.Passphrase := FPassphrase;
  if not IsValidSshTarget(Settings.Host, Settings.UserName, ErrorText) then
    Exit;
  if Settings.KeyFile <> '' then
  begin
    Settings.KeyFile := ExpandFileName(Settings.KeyFile);
    if not FileExists(Settings.KeyFile) then
    begin
      ErrorText := 'The private key file does not exist: ' + Settings.KeyFile +
        '.  Choose another in Menu > SSH key setup.';
      Exit;
    end;
  end;
  Result := True;
end;

function TMainForm.CurrentRequest(Kind: TJobKind; out Request: TTransferRequest;
  out ErrorText: string): Boolean;
var
  Ids: TNameArray;
  I: Integer;
  Reason: string;
begin
  Result := False;
  ErrorText := '';
  Request := Default(TTransferRequest);
  Request.Mode := FMode;
  Request.Overwrite := FOverwrite.Checked;
  Request.LocalDir := FLocalPane.CurrentPath;
  Request.UseBp := UsingBp;
  Request.SdFile := CurrentSdFile;

  if Kind = jkRename then
  begin
    SetLength(Request.RemoteNames, 1);
    Request.RemoteNames[0] := FRenameFrom;
    Request.NewName := FRenameTo;
  end
  else if Kind = jkDelete then
    Request.RemoteNames := FDeleteNames;

  if Kind = jkDownload then
  begin
    { Files are picked in the SD list.  From bp, "send bp <ids>" copies the
      picked records out through xfer.out, so each id is one word of that
      command; from xfer.out the files are already there. }
    Ids := SelectedRemoteNames;
    if Length(Ids) = 0 then
    begin
      ErrorText := 'Select one or more SD Core files to download.';
      Exit;
    end;
    for I := 0 to High(Ids) do
    begin
      if Request.UseBp and (Pos(' ', Ids[I]) > 0) then
      begin
        ErrorText := 'The bp record "' + Ids[I] + '" has a space in its name, so ' +
          'the send command cannot name it.  Rename it in SD Core to download it.';
        Exit;
      end;
      if not IsValidSdName(Ids[I], Reason) then
      begin
        ErrorText := 'The SD Core file "' + Ids[I] + '" cannot be transferred: ' + Reason;
        Exit;
      end;
    end;
    if Request.UseBp then
    begin
      Request.SourceFile := SDProgramFile;
      Request.SourceIds := JoinNames(Ids, ' ');
    end
    else
      Request.SourceFile := SDDownloadDirectory;
  end;

  if Kind = jkUpload then
  begin
    Request.Mode := tmUpload;
    Request.LocalPaths := SelectedLocalPaths;
    if Length(Request.LocalPaths) = 0 then
    begin
      ErrorText := 'Select one or more local files to upload.';
      Exit;
    end;
  end
  else if Kind = jkDownload then
  begin
    Request.Mode := tmDownload;
    Request.RemoteNames := SelectedRemoteNames;
    if Length(Request.RemoteNames) = 0 then
    begin
      ErrorText := 'Select one or more SD Core files to download.';
      Exit;
    end;
  end;
  Result := True;
end;

function TMainForm.SelectedLocalPaths: TNameArray;
begin
  Result := FLocalPane.SelectedPaths;
end;

function TMainForm.SelectedRemoteNames: TNameArray;
begin
  Result := FRemotePane.SelectedNames;
end;

procedure TMainForm.StartJob(Kind: TJobKind);
var
  Settings: TConnectionSettings;
  Request: TTransferRequest;
  ErrorText, JobName: string;
begin
  if FBusy then
    Exit;
  if (Kind <> jkTest) and not FConnected then
  begin
    SetStatus('Press Connect first.', True);
    Exit;
  end;
  if not CurrentSettings(Settings, ErrorText) then
  begin
    SetStatus(ErrorText, True);
    ShowError(ErrorText);
    Exit;
  end;
  if not CurrentRequest(Kind, Request, ErrorText) then
  begin
    SetStatus(ErrorText, True);
    ShowError(ErrorText);
    Exit;
  end;
  FCurrentKind := Kind;
  FCurrentMode := FMode;
  FCurrentUseBp := Request.UseBp;
  SaveUiToConfig;
  case Kind of
    jkTest: JobName := 'Connect';
    jkPreview:
      JobName := 'List ' + Request.SdFile;
    jkUpload: JobName := 'Upload files';
    jkRename: JobName := 'Rename in ' + Request.SdFile;
    jkDelete: JobName := 'Delete from ' + Request.SdFile;
    jkDownload: JobName := 'Download files';
  end;
  SetBusy(True);
  SetStatus(JobName + '...', False);
  if Kind = jkTest then
    FConnectState.Caption := 'Connecting...';
  AppendLogLine('--- ' + JobName + ' ---');
  try
    FWorker := TTransferThread.Create(Settings, Kind, Request);
    FWorker.OnLog := @ThreadLog;
    FWorker.OnFinished := @ThreadFinished;
    FWorker.Start;
  except
    on E: Exception do
    begin
      FWorker := nil;
      SetBusy(False);
      ErrorText := E.Message;
      SetStatus(ErrorText, True);
      AppendLogLine('ERROR: ' + ErrorText);
      ShowError(ErrorText);
    end;
  end;
end;

procedure TMainForm.TestClick(Sender: TObject);
begin
  if FBusy then
    Exit;
  if FConnected then
    Disconnect
  else
    StartJob(jkTest);
end;
procedure TMainForm.UploadModeClick(Sender: TObject);
begin
  SetMode(tmUpload);
  LoadViewIfNeeded;
end;

procedure TMainForm.DownloadModeClick(Sender: TObject);
begin
  SetMode(tmDownload);
  LoadViewIfNeeded;
end;

procedure TMainForm.ServerTypeChange(Sender: TObject);
begin
  if not FBusy then
    SetStatus('Server type: ' + FServerType.Text + '.', False);
  UpdateControlState;
end;

procedure TMainForm.UpdateKeyCaption;
begin
  if FKeyFile = '' then
    FConnGroup.Caption := ' SSH connection to the SD Core server '
  else
    FConnGroup.Caption := ' SSH connection to the SD Core server  -  key: ' + FKeyFile + ' ';
end;

procedure TMainForm.MenuButtonClick(Sender: TObject);
var
  P: TPoint;
begin
  P := FMenuButton.ClientToScreen(Point(0, FMenuButton.Height));
  FMenu.PopUp(P.X, P.Y);
end;

procedure TMainForm.MenuHelpClick(Sender: TObject);
begin
  ShowHelpWindow(Self);
end;

procedure TMainForm.MenuKeysClick(Sender: TObject);
var
  Dlg: TKeySetupForm;
begin
  if FBusy then
    Exit;
  if FConnected then
  begin
    MessageDlg('SSH key setup', 'Disconnect first: the key is part of the ' +
      'connection details.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Dlg := TKeySetupForm.CreateSetup(Self, FKeyFile, FPassphrase);
  try
    if Dlg.ShowModal = mrOK then
    begin
      FKeyFile := Dlg.KeyFile;
      FPassphrase := Dlg.Passphrase;
      UpdateKeyCaption;
      SaveUiToConfig;
      if FKeyFile = '' then
        SetStatus('Using your usual ssh keys.', False)
      else
        SetStatus('Using the key ' + FKeyFile + '.', False);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.MenuAboutClick(Sender: TObject);
begin
  ShowAboutWindow(Self);
end;

{ ---------------------------------------------------------------------------
  Right-click menus: Rename and Delete in both panes (menu only, no keys).
  --------------------------------------------------------------------------- }

function TMainForm.CurrentSdFile: string;
begin
  if UsingBp then
    Result := SDProgramFile
  else if FMode = tmUpload then
    Result := SDUploadDirectory
  else
    Result := SDDownloadDirectory;
end;

procedure TMainForm.BuildContextMenus;

  function AddItem(AMenu: TPopupMenu; const ACaption: string;
    AClick: TNotifyEvent): TMenuItem;
  begin
    { Menu only: no keyboard shortcuts for rename or delete. }
    Result := TMenuItem.Create(AMenu);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    AMenu.Items.Add(Result);
  end;

begin
  FSdMenu := TPopupMenu.Create(Self);
  FSdMenu.OnPopup := @SdMenuPopup;
  AddItem(FSdMenu, 'Rename...', @SdRenameClick);
  AddItem(FSdMenu, 'Delete...', @SdDeleteClick);
  FRemotePane.ListView.PopupMenu := FSdMenu;
  FRemotePane.ListView.OnMouseDown := @ListMouseDown;

  FLocalMenu := TPopupMenu.Create(Self);
  FLocalMenu.OnPopup := @LocalMenuPopup;
  AddItem(FLocalMenu, 'Rename...', @LocalRenameClick);
  AddItem(FLocalMenu, 'Move to ' + TrashName + '...', @LocalDeleteClick);
  FLocalPane.ListView.PopupMenu := FLocalMenu;
  FLocalPane.ListView.OnMouseDown := @ListMouseDown;
end;

procedure TMainForm.ListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  List: TListView;
  Item: TListItem;
begin
  { A right-click on a row that is not selected selects just that row, so the
    menu acts on what was clicked, as in a file manager. }
  if Button <> mbRight then
    Exit;
  List := Sender as TListView;
  Item := List.GetItemAt(X, Y);
  if (Item <> nil) and not Item.Selected then
  begin
    List.ClearSelection;
    Item.Selected := True;
    List.ItemFocused := Item;
  end;
end;

procedure TMainForm.SdMenuPopup(Sender: TObject);
var
  N: Integer;
begin
  N := Length(FRemotePane.SelectedNames);
  FSdMenu.Items[0].Enabled := FConnected and not FBusy and (N = 1);
  FSdMenu.Items[1].Enabled := FConnected and not FBusy and (N >= 1);
end;

procedure TMainForm.LocalMenuPopup(Sender: TObject);
var
  N: Integer;
begin
  N := Length(FLocalPane.SelectedAllPaths);
  FLocalMenu.Items[0].Enabled := FConnected and not FBusy and (N = 1);
  FLocalMenu.Items[1].Enabled := FConnected and not FBusy and (N >= 1);
end;

procedure TMainForm.SdRenameClick(Sender: TObject);
var
  Names: TNameArray;
  NewName, Reason: string;
  I: Integer;
begin
  if FBusy or not FConnected then
    Exit;
  Names := FRemotePane.SelectedNames;
  if Length(Names) <> 1 then
  begin
    SetStatus('Select one file to rename.', True);
    Exit;
  end;
  NewName := Names[0];
  if not InputQuery('Rename in ' + CurrentSdFile, 'New name for ' + Names[0] + ':',
    NewName) then
    Exit;
  NewName := Trim(NewName);
  if (NewName = '') or (NewName = Names[0]) then
    Exit;
  if not IsValidSdName(NewName, Reason) then
  begin
    ShowError('"' + NewName + '" cannot be used: ' + Reason);
    Exit;
  end;
  for I := 0 to High(FRemotePane.Entries) do
    if FRemotePane.Entries[I].Name = NewName then
    begin
      ShowError(CurrentSdFile + ' already has ' + NewName + '.');
      Exit;
    end;
  FRenameFrom := Names[0];
  FRenameTo := NewName;
  StartJob(jkRename);
end;

procedure TMainForm.SdDeleteClick(Sender: TObject);
var
  Names: TNameArray;
  Question: string;
begin
  if FBusy or not FConnected then
    Exit;
  Names := FRemotePane.SelectedNames;
  if Length(Names) = 0 then
    Exit;
  if UsingBp then
    Question := Format('Permanently delete %d program(s) from bp?', [Length(Names)])
  else
    Question := Format('Permanently delete %d file(s) from %s?',
      [Length(Names), CurrentSdFile]);
  Question := Question + LineEnding + LineEnding + '    ' +
    JoinNames(Names, LineEnding + '    ') + LineEnding + LineEnding +
    'This cannot be undone.';
  if MessageDlg('Delete from ' + CurrentSdFile, Question, mtWarning,
    [mbYes, mbNo], 0, mbNo) <> mrYes then
    Exit;
  FDeleteNames := Names;
  StartJob(jkDelete);
end;

procedure TMainForm.LocalRenameClick(Sender: TObject);
var
  Paths: TNameArray;
  OldPath, NewName, NewPath: string;
begin
  if FBusy or not FConnected then
    Exit;
  Paths := FLocalPane.SelectedAllPaths;
  if Length(Paths) <> 1 then
  begin
    SetStatus('Select one file or folder to rename.', True);
    Exit;
  end;
  OldPath := Paths[0];
  NewName := ExtractFileName(OldPath);
  if not InputQuery('Rename', 'New name for ' + ExtractFileName(OldPath) + ':',
    NewName) then
    Exit;
  NewName := Trim(NewName);
  if (NewName = '') or (NewName = ExtractFileName(OldPath)) then
    Exit;
  if (Pos('/', NewName) > 0) or (Pos(PathDelim, NewName) > 0) or
     (NewName = '.') or (NewName = '..') then
  begin
    ShowError('A name cannot contain "/" or "' + PathDelim + '" or be "." or "..".');
    Exit;
  end;
  NewPath := IncludeTrailingPathDelimiter(ExtractFileDir(OldPath)) + NewName;
  if FileExists(NewPath) or DirectoryExists(NewPath) then
  begin
    ShowError(NewName + ' already exists in this folder.');
    Exit;
  end;
  if RenameFile(OldPath, NewPath) then
  begin
    AppendLogLine('Renamed ' + OldPath + ' to ' + NewName + '.');
    SetStatus('Renamed to ' + NewName + '.', False);
  end
  else
    ShowError('Could not rename ' + OldPath + '.');
  FLocalPane.Reload;
end;

procedure TMainForm.LocalDeleteClick(Sender: TObject);
var
  Paths: TNameArray;
  ErrorText: string;
begin
  if FBusy or not FConnected then
    Exit;
  Paths := FLocalPane.SelectedAllPaths;
  if Length(Paths) = 0 then
    Exit;
  { Local files go to the desktop's Trash (Recycle Bin on Windows), where they
    can be restored; they are never erased outright. }
  if MessageDlg('Move to ' + TrashName, Format('Move %d item(s) to the %s?',
    [Length(Paths), TrashName]) + LineEnding + LineEnding + '    ' +
    JoinNames(Paths, LineEnding + '    ') + LineEnding + LineEnding +
    'You can restore them from the ' + TrashName + '.', mtConfirmation,
    [mbYes, mbNo], 0, mbNo) <> mrYes then
    Exit;
  if MoveToTrash(Paths, ErrorText) then
  begin
    AppendLogLine(Format('Moved %d item(s) to the %s: %s', [Length(Paths),
      TrashName, JoinNames(Paths)]));
    SetStatus(Format('Moved %d item(s) to the %s.', [Length(Paths), TrashName]), False);
  end
  else
    ShowError('Could not move everything to the ' + TrashName + '.' + LineEnding +
      LineEnding + ErrorText);
  FLocalPane.Reload;
end;

procedure TMainForm.OpenNamedWindow(const AName: string);
begin
  if AName = 'help' then
    MenuHelpClick(nil)
  else if AName = 'about' then
    MenuAboutClick(nil)
  else if AName = 'keys' then
    MenuKeysClick(nil);
end;
procedure TMainForm.LocalChanged(Sender: TObject);
begin
  if not FBusy then
    SetStatus('Local folder: ' + FLocalPane.CurrentPath, False);
end;

procedure TMainForm.LocalLog(const AText: string);
begin
  AppendLogLine(AText);
end;

procedure TMainForm.RemoteRefresh(Sender: TObject);
begin
  StartJob(jkPreview);
end;

procedure TMainForm.LocalDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  Accept := (not FBusy) and (FMode = tmDownload) and
    (Source = FRemotePane.ListView) and (Length(FRemotePane.SelectedNames) > 0);
end;

procedure TMainForm.LocalDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if (not FBusy) and (FMode = tmDownload) and (Source = FRemotePane.ListView) then
    StartJob(jkDownload);
end;

procedure TMainForm.RemoteDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  Accept := (not FBusy) and (FMode = tmUpload) and
    (Source = FLocalPane.ListView) and (Length(FLocalPane.SelectedPaths) > 0);
end;

procedure TMainForm.RemoteDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if (not FBusy) and (FMode = tmUpload) and (Source = FLocalPane.ListView) then
    StartJob(jkUpload);
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FBusy then
  begin
    CanClose := False;
    ShowMessage('A transfer is still running. Wait for it to finish before closing.');
    Exit;
  end;
  SaveUiToConfig;
  CanClose := True;
end;

procedure TMainForm.ThreadLog(const AText: string);
begin
  AppendLogLine(AText);
end;

procedure TMainForm.ThreadFinished(Sender: TObject);
begin
  if FWorker = nil then
    Exit;
  JobFinished(Sender);
end;

procedure TMainForm.JobFinished(Sender: TObject);
var
  Kind: TJobKind;
  Mode: TTransferMode;
  OK: Boolean;
  ErrorText, MessageText, Summary: string;
  Entries: TFileEntries;
begin
  if FWorker = nil then
    Exit;
  Kind := FCurrentKind;
  Mode := FCurrentMode;
  OK := FWorker.ResultOK;
  ErrorText := FWorker.ResultError;
  MessageText := FWorker.ResultMessage;
  Summary := FWorker.ResultSummary;
  Entries := FWorker.ResultEntries;
  FWorker := nil;

  FBusy := False;
  SetBusy(False);

  if OK then
  begin
    if MessageText = '' then
      MessageText := 'Done.';
    SetStatus(MessageText, False);
    AppendLogLine(MessageText);
    if Trim(Summary) <> '' then
    begin
      AppendLogLine('SD Core summary:');
      AppendLogLine(Summary);
    end;
    if Kind = jkTest then
    begin
      FConnected := True;
      UpdateControlState;
      SetStatus('Connected as ' + Trim(FUserEdit.Text) + ' to ' + Trim(FHostEdit.Text) +
        '.  Each listing and transfer signs in for its own short SD Core session.', False);
      LoadViewIfNeeded;
      Exit;
    end;

    { A download writes into the local folder: show the new files. }
    if Kind = jkDownload then
      FLocalPane.LoadDirectory(FLocalPane.CurrentPath);

    if FCurrentUseBp then
    begin
      if Kind in [jkPreview, jkUpload, jkRename, jkDelete] then
      begin
        FBpEntries := Entries;
        FBpLoaded := True;
      end;
      if Kind = jkDownload then
      begin
        FDownloadEntries := Entries;  { the engine lists xfer.out after a download }
        FDownloadLoaded := True;
      end;
      if (Kind = jkUpload) then
        FUploadLoaded := False;     { and so did xfer.in }
      UpdateSnapshotForMode;
    end
    else if (Kind in [jkPreview, jkUpload, jkRename, jkDelete]) and (Mode = tmUpload) then
    begin
      FUploadEntries := Entries;
      FUploadLoaded := True;
      if FMode = tmUpload then
        FRemotePane.SetEntries(FUploadEntries);
    end
    else if (Kind in [jkPreview, jkDownload, jkRename, jkDelete]) and (Mode = tmDownload) then
    begin
      FDownloadEntries := Entries;
      FDownloadLoaded := True;
      if FMode = tmDownload then
        FRemotePane.SetEntries(FDownloadEntries);
    end;
  end
  else
  begin
    if ErrorText = '' then
      ErrorText := 'The transfer did not complete.';
    SetStatus(ErrorText, True);
    AppendLogLine('ERROR: ' + ErrorText);
    if Kind = jkTest then
      FConnectState.Caption := 'Not connected';
    ShowError(ErrorText);
  end;
end;

procedure TMainForm.ShowError(const AText: string);
begin
  MessageDlg('SD Core Transfer Utility', AText, mtError, [mbOK], 0);
end;

constructor TTransferThread.Create(const Settings: TConnectionSettings;
  Kind: TJobKind; const Request: TTransferRequest);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FSettings := Settings;
  FKind := Kind;
  FRequest := Request;
  ResultOK := False;
end;

procedure TTransferThread.EngineLog(const Text: string);
begin
  FPendingLog := Text;
  Synchronize(@SyncLog);
end;

function TTransferThread.EngineConfirm(const Title, Question: string): Boolean;
begin
  FAskTitle := Title;
  FAskText := Question;
  FAskAnswer := False;
  Synchronize(@SyncConfirm);
  Result := FAskAnswer;
end;

procedure TTransferThread.SyncConfirm;
begin
  Screen.Cursor := crDefault;
  FAskAnswer := MessageDlg(FAskTitle, FAskText, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  Screen.Cursor := crHourGlass;
end;

procedure TTransferThread.SyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(FPendingLog);
end;

procedure TTransferThread.SyncFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(Self);
end;

procedure TTransferThread.Execute;
var
  Engine: TTransferEngine;
  Entries: TFileEntries;
  ErrorText, Summary: string;
begin
  ResultOK := False;
  ResultError := '';
  ResultMessage := '';
  ResultSummary := '';
  SetLength(ResultEntries, 0);
  SetLength(Entries, 0);
  Summary := '';
  ErrorText := '';

  Engine := nil;
  try
    try
      Engine := TTransferEngine.Create(FSettings, @EngineLog, @EngineConfirm);
      case FKind of
        jkTest:
          ResultOK := Engine.TestLogin(ErrorText);
        jkPreview:
          { Every SD view is listed at the SD prompt; no transfer slot. }
          ResultOK := Engine.ListFile(FRequest.SdFile, Entries, ErrorText);
        jkRename:
          ResultOK := Engine.RenameRecord(FRequest.SdFile, FRequest.RemoteNames[0],
            FRequest.NewName, Entries, ErrorText);
        jkDelete:
          ResultOK := Engine.DeleteRecords(FRequest.SdFile, FRequest.RemoteNames,
            Entries, ErrorText);
        jkUpload:
          ResultOK := Engine.Upload(FRequest.LocalPaths, FRequest.Overwrite,
            FRequest.UseBp, Entries, Summary, ErrorText);
        jkDownload:
          ResultOK := Engine.Download(FRequest.SourceFile, FRequest.SourceIds,
            FRequest.RemoteNames, FRequest.LocalDir, FRequest.Overwrite,
            Entries, Summary, ErrorText);
      end;
    except
      on E: Exception do
      begin
        ResultOK := False;
        ErrorText := E.Message;
      end;
    end;
  finally
    Engine.Free;
    FSettings.Password := '';
    FSettings.Passphrase := '';
  end;

  ResultError := ErrorText;
  ResultSummary := Summary;
  ResultEntries := Entries;
  if ResultOK then
  begin
    case FKind of
      jkTest: ResultMessage := 'Login test succeeded.';
      jkPreview: ResultMessage := FRequest.SdFile + ' listed.';
      jkRename: ResultMessage := FRequest.RemoteNames[0] + ' renamed to ' +
        FRequest.NewName + ' in ' + FRequest.SdFile + '.';
      jkDelete: ResultMessage := Format('%d file(s) deleted from %s.',
        [Length(FRequest.RemoteNames), FRequest.SdFile]);
      jkUpload: ResultMessage := 'Upload complete.';
      jkDownload: ResultMessage := 'Download complete.';
    end;
  end
  else
  begin
    if ResultError = '' then
      ResultError := 'The operation did not complete.';
    ResultMessage := 'Operation failed.';
  end;

  if Assigned(FOnFinished) then
    Synchronize(@SyncFinished);
end;

end.
