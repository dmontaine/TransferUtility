unit uLocalPane;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ComCtrls, ExtCtrls, Dialogs,
  uModels;

type
  TLocalLogEvent = procedure(const Text: string) of object;

  TLocalPane = class(TPanel)
  private
    FPathEdit: TEdit;
    FPath: string;
    FList: TListView;
    FTitle: TLabel;
    FHint: TLabel;
    FBrowse: TButton;
    FUp: TButton;
    FRefresh: TButton;
    FButtonBar: TPanel;
    FEntries: TFileEntries;
    FOnLog: TLocalLogEvent;
    FOnChanged: TNotifyEvent;
    procedure BuildUi;
    procedure ListDoubleClick(Sender: TObject);
    procedure ListResize(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure SortEntries;
    procedure FillList;
    function EntryIndex(Item: TListItem): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadDirectory(const DirectoryName: string);
    function CurrentPath: string;
    function SelectedPaths: TNameArray;
    { Files AND folders selected, as full paths (for rename / delete). }
    function SelectedAllPaths: TNameArray;
    procedure Reload;
    procedure SetDropHint(const AHint: string);
    procedure SelectAllFiles;
    { Give the Name column whatever the fixed columns leave. }
    procedure FitColumns;
    property ListView: TListView read FList;
    property OnLog: TLocalLogEvent read FOnLog write FOnLog;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  FileUtil;

constructor TLocalPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildUi;
end;

procedure TLocalPane.BuildUi;
begin
  BevelOuter := bvNone;

  { alTop children stack by Top value: title, then the path row. }
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Self;
  FTitle.Top := 0;
  FTitle.Align := alTop;
  FTitle.AutoSize := True;
  FTitle.Caption := 'Local computer';
  FTitle.Font.Style := [fsBold];
  FTitle.BorderSpacing.Bottom := 4;

  FButtonBar := TPanel.Create(Self);
  FButtonBar.Parent := Self;
  FButtonBar.Top := 100;
  FButtonBar.Align := alTop;
  FButtonBar.AutoSize := True;
  FButtonBar.BevelOuter := bvNone;
  FButtonBar.BorderSpacing.Bottom := 4;

  { Buttons on the right of the path field, left to right: Up, Browse, Refresh. }
  FRefresh := TButton.Create(Self);
  FRefresh.Parent := FButtonBar;
  FRefresh.Left := 3000;
  FRefresh.Align := alRight;
  FRefresh.Width := 80;
  FRefresh.Caption := 'Refresh';
  FRefresh.BorderSpacing.Left := 4;
  FRefresh.OnClick := @RefreshClick;

  FBrowse := TButton.Create(Self);
  FBrowse.Parent := FButtonBar;
  FBrowse.Left := 2000;
  FBrowse.Align := alRight;
  FBrowse.Width := 80;
  FBrowse.Caption := 'Browse...';
  FBrowse.BorderSpacing.Left := 4;
  FBrowse.OnClick := @BrowseClick;

  FUp := TButton.Create(Self);
  FUp.Parent := FButtonBar;
  FUp.Left := 1000;
  FUp.Align := alRight;
  FUp.Width := 50;
  FUp.Caption := 'Up';
  FUp.BorderSpacing.Left := 4;
  FUp.OnClick := @UpClick;

  FPathEdit := TEdit.Create(Self);
  FPathEdit.Parent := FButtonBar;
  FPathEdit.Align := alClient;
  { Shows the folder; change it with double-click, Up or Browse. }
  FPathEdit.ReadOnly := True;
  FPathEdit.TabStop := False;

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alBottom;
  FHint.AutoSize := True;
  FHint.BorderSpacing.Top := 3;
  FHint.Caption := 'Drag selected files onto the SD Core pane to upload.';
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
  FList.Hint := 'Select files here, then drag them to the SD Core pane (Upload mode).';
  FList.OnDblClick := @ListDoubleClick;
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
  FList.Columns.Add;
  FList.Columns[3].Caption := 'Type';
  FList.Columns[3].Width := 64;
end;

procedure TLocalPane.ListResize(Sender: TObject);
begin
  FitColumns;
end;

procedure TLocalPane.FitColumns;
var
  W: Integer;
begin
  { The Name column takes whatever width the fixed columns leave. }
  { Width, not ClientWidth: right after the panes swap sides GTK may not
    have updated the client area yet.  20 leaves room for a scrollbar. }
  W := FList.Width - 20 - FList.Columns[1].Width - FList.Columns[2].Width -
    FList.Columns[3].Width - 4;
  if W < 140 then
    W := 140;
  FList.Columns[0].Width := W;
end;

function TLocalPane.EntryIndex(Item: TListItem): Integer;
begin
  Result := -1;
  if (Item <> nil) and (Item.Data <> nil) then
    Result := Integer(PtrUInt(Item.Data)) - 1;
end;

procedure TLocalPane.SortEntries;
var
  I, J: Integer;
  Tmp: TFileEntry;
  function Before(const A, B: TFileEntry): Boolean;
  begin
    if A.IsDir <> B.IsDir then
      Exit(A.IsDir);
    Result := CompareText(A.Name, B.Name) < 0;
  end;
begin
  for I := 1 to High(FEntries) do
  begin
    Tmp := FEntries[I];
    J := I - 1;
    while (J >= 0) and not Before(FEntries[J], Tmp) do
    begin
      FEntries[J + 1] := FEntries[J];
      Dec(J);
    end;
    FEntries[J + 1] := Tmp;
  end;
end;

procedure TLocalPane.FillList;
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
      Item.Data := Pointer(PtrInt(I + 1));
      if FEntries[I].IsDir then
      begin
        Item.SubItems.Add('<DIR>');
        Item.SubItems.Add(FormatFileTime(FEntries[I].Modified));
        Item.SubItems.Add('Folder');
      end
      else
      begin
        Item.SubItems.Add(FormatByteCount(FEntries[I].Size));
        Item.SubItems.Add(FormatFileTime(FEntries[I].Modified));
        Item.SubItems.Add('File');
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TLocalPane.LoadDirectory(const DirectoryName: string);
var
  Path: string;
  SR: TSearchRec;
  Count: Integer;
  Entry: TFileEntry;
begin
  if Trim(DirectoryName) = '' then
    Exit;
  Path := ExpandFileName(Trim(DirectoryName));
  if not DirectoryExists(Path) then
  begin
    if Assigned(FOnLog) then
      FOnLog('Local folder not found: ' + Path);
    Exit;
  end;
  Path := IncludeTrailingPathDelimiter(Path);
  FPath := Path;
  FPathEdit.Text := Path;
  SetLength(FEntries, 0);
  Count := 0;
  if FindFirst(Path + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        Entry.Name := SR.Name;
        Entry.Size := 0;
        Entry.Modified := 0;
        Entry.IsDir := True;
      end
      else
      begin
        Entry.Name := SR.Name;
        Entry.Size := SR.Size;
        Entry.Modified := FileDateToDateTime(SR.Time);
        Entry.IsDir := False;
      end;
      SetLength(FEntries, Count + 1);
      FEntries[Count] := Entry;
      Inc(Count);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  SortEntries;
  FillList;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TLocalPane.CurrentPath: string;
begin
  Result := FPath;
end;

procedure TLocalPane.SetDropHint(const AHint: string);
begin
  FHint.Caption := AHint;
  FList.Hint := AHint;
end;

function TLocalPane.SelectedPaths: TNameArray;
var
  I, Index: Integer;
  Count: Integer;
begin
  Result := nil;
  Count := 0;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
    begin
      Index := EntryIndex(FList.Items[I]);
      if (Index >= 0) and (Index <= High(FEntries)) and not FEntries[Index].IsDir then
      begin
        SetLength(Result, Count + 1);
        Result[Count] := IncludeTrailingPathDelimiter(FPath) + FEntries[Index].Name;
        Inc(Count);
      end;
    end;
end;

function TLocalPane.SelectedAllPaths: TNameArray;
var
  I, Index: Integer;
begin
  Result := nil;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
    begin
      Index := EntryIndex(FList.Items[I]);
      if (Index >= 0) and (Index <= High(FEntries)) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := IncludeTrailingPathDelimiter(FPath) + FEntries[Index].Name;
      end;
    end;
end;

procedure TLocalPane.Reload;
begin
  LoadDirectory(FPath);
end;

procedure TLocalPane.SelectAllFiles;
var
  I: Integer;
begin
  for I := 0 to FList.Items.Count - 1 do
    FList.Items[I].Selected := True;
end;

procedure TLocalPane.ListDoubleClick(Sender: TObject);
var
  Index: Integer;
begin
  if FList.Selected = nil then
    Exit;
  Index := EntryIndex(FList.Selected);
  if (Index < 0) or (Index > High(FEntries)) then
    Exit;
  if FEntries[Index].IsDir then
    LoadDirectory(IncludeTrailingPathDelimiter(FPath) + FEntries[Index].Name);
end;

procedure TLocalPane.BrowseClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(nil);
  try
    Dlg.Title := 'Choose a local folder';
    Dlg.InitialDir := FPath;
    if Dlg.Execute then
      LoadDirectory(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TLocalPane.UpClick(Sender: TObject);
var
  ParentDir: string;
begin
  ParentDir := ExtractFileDir(ExcludeTrailingPathDelimiter(FPath));
  if (ParentDir <> '') and (ParentDir <> ExcludeTrailingPathDelimiter(FPath)) then
    LoadDirectory(ParentDir);
end;

procedure TLocalPane.RefreshClick(Sender: TObject);
begin
  LoadDirectory(FPath);
end;

end.
