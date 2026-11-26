unit uRemotePane;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ComCtrls, ExtCtrls,
  Buttons, uModels;

type
  TRemotePane = class(TPanel)
  private
    FTitle: TLabel;
    FPathLabel: TLabel;
    FHint: TLabel;
    FRefresh: TButton;
    FViewXfer: TSpeedButton;
    FViewBp: TSpeedButton;
    FOnViewChange: TNotifyEvent;
    FList: TListView;
    FEntries: TFileEntries;
    FOnRefresh: TNotifyEvent;
    procedure BuildUi;
    procedure RefreshClick(Sender: TObject);
    procedure ListResize(Sender: TObject);
    procedure ViewClick(Sender: TObject);
    function GetShowBp: Boolean;
    procedure SetShowBp(Value: Boolean);
    procedure SortEntries;
    procedure FillList;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetDirectoryName(const DirectoryName: string; UploadMode: Boolean);
    procedure SetEntries(const Entries: TFileEntries);
    procedure SetDropHint(const AHint: string);
    function SelectedNames: TNameArray;
    { Give the Name column whatever the fixed columns leave. }
    procedure FitColumns;
    property ListView: TListView read FList;
    property Entries: TFileEntries read FEntries;
    procedure SetTitle(const ATitle, APathNote: string);
    procedure SetXferName(const AName: string);
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
    { True when the pane shows bp instead of the transfer directory. }
    property ShowBp: Boolean read GetShowBp write SetShowBp;
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
  end;

implementation

constructor TRemotePane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildUi;
end;

procedure TRemotePane.BuildUi;
var
  Row: TPanel;
begin
  BevelOuter := bvNone;

  FTitle := TLabel.Create(Self);
  FTitle.Parent := Self;
  FTitle.Top := 0;
  FTitle.Align := alTop;
  FTitle.AutoSize := True;
  FTitle.Caption := 'SD server - xfer.in';
  FTitle.Font.Style := [fsBold];
  FTitle.BorderSpacing.Bottom := 4;

  { Path row mirrors the local pane's so both lists start at the same height. }
  Row := TPanel.Create(Self);
  Row.Parent := Self;
  Row.Top := 100;
  Row.Align := alTop;
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  Row.BorderSpacing.Bottom := 4;

  { Which SD folder the pane works with: the transfer directory itself, or bp
    (files still travel through xfer.in / xfer.out). }
  FViewXfer := TSpeedButton.Create(Self);
  FViewXfer.Parent := Row;
  FViewXfer.Left := 0;
  FViewXfer.Align := alLeft;
  FViewXfer.Width := 80;
  FViewXfer.Caption := SDUploadDirectory;
  FViewXfer.GroupIndex := 7;
  FViewXfer.AllowAllUp := False;
  FViewXfer.Down := True;
  FViewXfer.Hint := 'Work with the SD transfer folder itself';
  FViewXfer.ShowHint := True;
  FViewXfer.OnClick := @ViewClick;

  FViewBp := TSpeedButton.Create(Self);
  FViewBp.Parent := Row;
  FViewBp.Left := 100;
  FViewBp.Align := alLeft;
  FViewBp.Width := 80;
  FViewBp.Caption := SDProgramFile;
  FViewBp.GroupIndex := 7;
  FViewBp.AllowAllUp := False;
  FViewBp.Hint := 'Work with your bp program file; files pass through the transfer folder';
  FViewBp.ShowHint := True;
  FViewBp.OnClick := @ViewClick;

  FRefresh := TButton.Create(Self);
  FRefresh.Parent := Row;
  FRefresh.Align := alRight;
  FRefresh.Width := 80;
  FRefresh.Caption := 'Refresh';
  FRefresh.Hint := 'List the SD folder again';
  FRefresh.ShowHint := True;
  FRefresh.OnClick := @RefreshClick;

  FPathLabel := TLabel.Create(Self);
  FPathLabel.Parent := Row;
  FPathLabel.Align := alClient;
  FPathLabel.AutoSize := False;
  FPathLabel.Layout := tlCenter;
  FPathLabel.BorderSpacing.Left := 10;
  FPathLabel.Caption := '/  (one directory only)';
  FPathLabel.Font.Color := clGrayText;

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alBottom;
  FHint.AutoSize := True;
  FHint.BorderSpacing.Top := 3;
  FHint.Caption := 'Drag files here to upload; the SD pane is read-only otherwise.';
  FHint.Font.Color := clGrayText;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.MultiSelect := True;
  FList.HideSelection := False;
  FList.DragMode := dmAutomatic;
  FList.ShowHint := True;
  FList.Hint := 'The SD server exposes only xfer.in (uploads) or xfer.out (downloads).';
  FList.OnResize := @ListResize;
  FList.Columns.Add;
  FList.Columns[0].Caption := 'Name';
  FList.Columns[0].Width := 260;
  FList.Columns.Add;
  FList.Columns[1].Caption := 'Size';
  FList.Columns[1].Width := 80;
  FList.Columns[1].Alignment := taRightJustify;
  FList.Columns.Add;
  FList.Columns[2].Caption := 'Modified';
  FList.Columns[2].Width := 140;
end;

procedure TRemotePane.ListResize(Sender: TObject);
begin
  FitColumns;
end;

procedure TRemotePane.FitColumns;
var
  W: Integer;
begin
  { Width, not ClientWidth: right after the panes swap sides GTK may not
    have updated the client area yet.  20 leaves room for a scrollbar. }
  W := FList.Width - 20 - FList.Columns[1].Width - FList.Columns[2].Width - 4;
  if W < 140 then
    W := 140;
  FList.Columns[0].Width := W;
end;

procedure TRemotePane.SortEntries;
var
  I, J: Integer;
  Tmp: TFileEntry;
begin
  for I := 1 to High(FEntries) do
  begin
    Tmp := FEntries[I];
    J := I - 1;
    while (J >= 0) and (CompareText(FEntries[J].Name, Tmp.Name) > 0) do
    begin
      FEntries[J + 1] := FEntries[J];
      Dec(J);
    end;
    FEntries[J + 1] := Tmp;
  end;
end;

procedure TRemotePane.FillList;
var
  I: Integer;
  Item: TListItem;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for I := 0 to High(FEntries) do
    begin
      Item := FList.Items.Add;
      Item.Caption := FEntries[I].Name;
      Item.SubItems.Add(FormatByteCount(FEntries[I].Size));
      Item.SubItems.Add(FormatFileTime(FEntries[I].Modified));
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TRemotePane.SetEntries(const Entries: TFileEntries);
var
  I: Integer;
begin
  SetLength(FEntries, Length(Entries));
  for I := 0 to High(Entries) do
    FEntries[I] := Entries[I];
  SortEntries;
  FillList;
end;

procedure TRemotePane.SetDirectoryName(const DirectoryName: string;
  UploadMode: Boolean);
begin
  if UploadMode then
    FTitle.Caption := 'SD server - ' + DirectoryName + ' (uploads)'
  else
    FTitle.Caption := 'SD server - ' + DirectoryName + ' (downloads)';
  FPathLabel.Caption := '/   (the only SD folder exposed during a transfer)';
end;

procedure TRemotePane.SetTitle(const ATitle, APathNote: string);
begin
  FTitle.Caption := ATitle;
  FPathLabel.Caption := APathNote;
end;

procedure TRemotePane.SetXferName(const AName: string);
begin
  FViewXfer.Caption := AName;
end;

function TRemotePane.GetShowBp: Boolean;
begin
  Result := FViewBp.Down;
end;

procedure TRemotePane.SetShowBp(Value: Boolean);
begin
  FViewBp.Down := Value;
  FViewXfer.Down := not Value;
end;

procedure TRemotePane.ViewClick(Sender: TObject);
begin
  if Assigned(FOnViewChange) then
    FOnViewChange(Self);
end;

procedure TRemotePane.SetDropHint(const AHint: string);
begin
  FHint.Caption := AHint;
  FList.Hint := AHint;
end;

function TRemotePane.SelectedNames: TNameArray;
var
  I, Count: Integer;
begin
  Result := nil;
  Count := 0;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
    begin
      SetLength(Result, Count + 1);
      Result[Count] := FList.Items[I].Caption;
      Inc(Count);
    end;
end;

procedure TRemotePane.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
    FOnRefresh(Self);
end;

end.
