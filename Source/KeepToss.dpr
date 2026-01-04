program KeepToss;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.MMSystem,
  Objects in '..\Libraries\fv-delphi-modern\src\Objects.pas',
  Video in '..\Libraries\fv-delphi-modern\src\Video.pas',
  Drivers in '..\Libraries\fv-delphi-modern\src\Drivers.pas',
  FVInterfaces in '..\Libraries\fv-delphi-modern\src\FVInterfaces.pas',
  FVSerialization in '..\Libraries\fv-delphi-modern\src\FVSerialization.pas',
  Views in '..\Libraries\fv-delphi-modern\src\Views.pas',
  Menus in '..\Libraries\fv-delphi-modern\src\Menus.pas',
  HistList in '..\Libraries\fv-delphi-modern\src\histlist.pas',
  fvconsts in '..\Libraries\fv-delphi-modern\src\fvconsts.pas',
  App in '..\Libraries\fv-delphi-modern\src\app.pas',
  FVCommon in '..\Libraries\fv-delphi-modern\src\FVCommon.pas',
  Validate in '..\Libraries\fv-delphi-modern\src\Validate.pas',
  Dialogs in '..\Libraries\fv-delphi-modern\src\Dialogs.pas',
  MsgBox in '..\Libraries\fv-delphi-modern\src\MsgBox.pas';

const
  { Application commands }
  cmSelectSource = 1000;
  cmSelectTarget = 1001;
  cmCopy         = 1002;
  cmMove         = 1003;
  cmDelete       = 1004;
  cmToggleAuto   = 1005;

type
  { Operation type for undo }
  TOperationType = (opNone, opCopy, opMove, opDelete);

  { Sample file information }
  TSampleInfo = record
    FileName: string;
    FileSize: Int64;
  end;

  { Custom list viewer for sample files }
  TSampleListView = class(TListViewer)
    FFolder: string;
    FSamples: array of TSampleInfo;
    FCount: Integer;
    FIsSource: Boolean;  { True if this is the source list (for mouse actions) }
    constructor Create(var Bounds: TRect; AVScrollBar: TScrollBar; AIsSource: Boolean); reintroduce; virtual;
    destructor Destroy; override;
    function GetPalette: PPalette; override;
    function GetText(Item: Integer; MaxLen: Integer): string; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure LoadFolder(const AFolder: string);
    procedure RemoveItem(Index: Integer);
    function GetFullPath(Index: Integer): string;
    function GetFileName(Index: Integer): string;
  end;

  { Header view showing folder paths }
  TPathHeader = class(TView)
    FSourcePath: ^string;
    FTargetPath: ^string;
    constructor Create(var Bounds: TRect; ASourcePath, ATargetPath: Pointer); reintroduce; virtual;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { Custom status line with autoplay indicator }
  TKeepTossStatusLine = class(TStatusLine)
    FAutoPlay: PBoolean;
    function Hint(AHelpCtx: Word): ShortString; override;
  end;

  { Main application }
  TKeepTossApp = class(TApplication)
    SourceFolder: string;
    TargetFolder: string;
    AutoPlay: Boolean;
    IsPlaying: Boolean;
    PathHeader: TPathHeader;
    SourceList: TSampleListView;
    TargetList: TSampleListView;
    SourceScrollBar: TScrollBar;
    TargetScrollBar: TScrollBar;
    LastOp: TOperationType;
    LastSrcFile: string;
    LastDestFile: string;
    LastIndex: Integer;
    LastFocused: Integer;
    constructor Create; override;
    destructor Destroy; override;
    procedure InitMenuBar; override;
    procedure InitStatusLine; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure Idle; override;
    procedure SelectSourceFolder;
    procedure SelectTargetFolder;
    procedure CreateListViews;
    procedure RefreshLists;
    procedure DoSwapFolders;
    procedure DoPlay;
    procedure DoStop;
    procedure DoCopy;
    procedure DoMove;
    procedure DoDelete(Confirm: Boolean);
    procedure DoUndo;
    procedure ToggleAutoPlay;
    procedure AdvanceNext;
  end;

var
  KeepTossApp: TKeepTossApp;

{ -------------------------------------------------------------------------- }
{ Helper Functions }
{ -------------------------------------------------------------------------- }

function FolderInputBox(const Title, ALabel: string; var S: string): Word;
var
  R: TRect;
  Dialog: TDialog;
  InputLine: TInputLine;
  ShortS: ShortString;
begin
  R.Assign(0, 0, 60, 8);
  R.Move((Desktop.Size.X - R.B.X) div 2, (Desktop.Size.Y - R.B.Y) div 2);
  Dialog := TDialog.Create(R, Title);
  with Dialog do
  begin
    R.Assign(4 + Length(ALabel), 2, Size.X - 3, 3);
    InputLine := TInputLine.Create(R, 255);
    Insert(InputLine);
    R.Assign(2, 2, 3 + Length(ALabel), 3);
    Insert(TLabel.Create(R, ALabel, InputLine));
    { OK button - default and placed first }
    R.Assign(Size.X - 24, Size.Y - 4, Size.X - 14, Size.Y - 2);
    Insert(TButton.Create(R, 'O~K~', cmOk, bfDefault));
    { Cancel button }
    Inc(R.A.X, 12);
    Inc(R.B.X, 12);
    Insert(TButton.Create(R, 'Cancel', cmCancel, bfNormal));
  end;
  ShortS := ShortString(S);
  InputLine.SetData(ShortS);
  Result := Desktop.ExecView(Dialog);
  if Result = cmOk then
  begin
    InputLine.GetData(ShortS);
    S := string(ShortS);
  end;
  FreeAndNil(Dialog);
end;

function GetUniqueDestPath(const DestFolder, FileName: string): string;
var
  BaseName, Ext: string;
  Counter: Integer;
begin
  Result := DestFolder + '\' + FileName;
  if not FileExists(Result) then Exit;

  { File exists - generate unique name with _1, _2, etc. suffix }
  Ext := ExtractFileExt(FileName);
  BaseName := ChangeFileExt(FileName, '');

  Counter := 1;
  repeat
    Result := DestFolder + '\' + BaseName + '_' + IntToStr(Counter) + Ext;
    Inc(Counter);
  until not FileExists(Result);
end;

function EnsureDirectoryExists(const Path: string): Boolean;
begin
  Result := False;
  if Trim(Path) = '' then Exit;
  try
    Result := DirectoryExists(Path) or ForceDirectories(Path);
  except
    Result := False;
  end;
end;

function IsValidPath(const Path: string): Boolean;
var
  ParentDir: string;
begin
  Result := False;
  if Trim(Path) = '' then Exit;
  try
    { Check if path already exists }
    if DirectoryExists(Path) then
    begin
      Result := True;
      Exit;
    end;
    { Check if parent directory exists (path could be created) }
    ParentDir := ExtractFileDir(ExcludeTrailingPathDelimiter(Path));
    if (ParentDir <> '') and DirectoryExists(ParentDir) then
    begin
      Result := True;
      Exit;
    end;
    { Check if it's a root path like C:\ }
    if (Length(Path) >= 2) and (Path[2] = ':') then
    begin
      ParentDir := Copy(Path, 1, 3); { e.g., "C:\" }
      Result := DirectoryExists(ParentDir);
    end;
  except
    Result := False;
  end;
end;

{ -------------------------------------------------------------------------- }
{ TSampleListView }
{ -------------------------------------------------------------------------- }

constructor TSampleListView.Create(var Bounds: TRect; AVScrollBar: TScrollBar; AIsSource: Boolean);
begin
  inherited Create(Bounds, 1, nil, AVScrollBar);
  FCount := 0;
  FIsSource := AIsSource;
  SetLength(FSamples, 0);
  { Only source list is selectable }
  if AIsSource then
    Options := Options or ofSelectable or ofFirstClick;
  GrowMode := gfGrowHiX + gfGrowHiY;
end;

destructor TSampleListView.Destroy;
begin
  SetLength(FSamples, 0);
  inherited Destroy;
end;

function TSampleListView.GetPalette: PPalette;
const
  { Palette indices into app palette (not direct colors!) }
  { Format: Active, Inactive, Focused, Selected, Divider }
  { Using: 2=black on gray, 21=yellow on cyan (focused), 5=black on green (selected) }
  P: ShortString = #2#2#21#5#2;
begin
  Result := @P;
end;

function TSampleListView.GetText(Item: Integer; MaxLen: Integer): string;
var
  SizeStr: string;
  NameWidth: Integer;
  DisplayName: string;
begin
  if (Item < 0) or (Item >= FCount) then
  begin
    Result := '';
    Exit;
  end;

  { Format file size }
  if FSamples[Item].FileSize >= 1048576 then
    SizeStr := Format('%.1f MB', [FSamples[Item].FileSize / 1048576.0])
  else if FSamples[Item].FileSize >= 1024 then
    SizeStr := Format('%d KB', [FSamples[Item].FileSize div 1024])
  else
    SizeStr := Format('%d B', [FSamples[Item].FileSize]);

  { Calculate available width for filename (reserve space for size + padding) }
  NameWidth := MaxLen - Length(SizeStr) - 4;
  if NameWidth < 10 then NameWidth := 10;

  { Truncate or pad filename }
  DisplayName := FSamples[Item].FileName;
  if Length(DisplayName) > NameWidth then
    DisplayName := Copy(DisplayName, 1, NameWidth - 3) + '...'
  else
    while Length(DisplayName) < NameWidth do
      DisplayName := DisplayName + ' ';

  Result := DisplayName + '  ' + SizeStr;
end;

procedure TSampleListView.LoadFolder(const AFolder: string);
var
  SR: System.SysUtils.TSearchRec;
  I, J: Integer;
  Temp: TSampleInfo;
begin
  FFolder := AFolder;
  SetLength(FSamples, 0);
  FCount := 0;

  if System.SysUtils.FindFirst(AFolder + '\*.wav', faAnyFile and not faDirectory, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
      begin
        SetLength(FSamples, FCount + 1);
        FSamples[FCount].FileName := SR.Name;
        FSamples[FCount].FileSize := SR.Size;
        Inc(FCount);
      end;
    until System.SysUtils.FindNext(SR) <> 0;
    System.SysUtils.FindClose(SR);

    { Sort alphabetically (simple bubble sort) }
    for I := 0 to FCount - 2 do
      for J := I + 1 to FCount - 1 do
        if CompareText(FSamples[I].FileName, FSamples[J].FileName) > 0 then
        begin
          Temp := FSamples[I];
          FSamples[I] := FSamples[J];
          FSamples[J] := Temp;
        end;
  end;

  SetRange(FCount);
  { Only focus first item in source list; target list has no selection }
  if FIsSource then
  begin
    if FCount > 0 then
      FocusItem(0);
  end
  else
    Focused := -1;  { No selection in target list }
  DrawView;
end;

procedure TSampleListView.RemoveItem(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index >= FCount) then Exit;

  for I := Index to FCount - 2 do
    FSamples[I] := FSamples[I + 1];

  Dec(FCount);
  SetLength(FSamples, FCount);
  SetRange(FCount);

  if Focused >= FCount then
    if FCount > 0 then
      FocusItem(FCount - 1)
    else
      Focused := 0;

  DrawView;
end;

function TSampleListView.GetFullPath(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FFolder + '\' + FSamples[Index].FileName
  else
    Result := '';
end;

function TSampleListView.GetFileName(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FSamples[Index].FileName
  else
    Result := '';
end;

procedure TSampleListView.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
begin
  { Handle double-click first (only on source list) }
  if (Event.What = evMouseDown) and Event.Double and FIsSource then
  begin
    MakeLocal(Event.Where, Mouse);
    if (Mouse.Y >= 0) and (Mouse.Y < Size.Y) then
    begin
      { Double-click = copy - reuse Event record like TFileList does }
      Event.What := evCommand;
      Event.Command := cmCopy;
      PutEvent(Event);
      ClearEvent(Event);
      Exit;
    end;
  end;

  { Let inherited handle selection }
  inherited HandleEvent(Event);
end;

{ -------------------------------------------------------------------------- }
{ TKeepTossStatusLine }
{ -------------------------------------------------------------------------- }

{ -------------------------------------------------------------------------- }
{ TPathHeader }
{ -------------------------------------------------------------------------- }

constructor TPathHeader.Create(var Bounds: TRect; ASourcePath, ATargetPath: Pointer);
begin
  inherited Create(Bounds);
  FSourcePath := ASourcePath;
  FTargetPath := ATargetPath;
  GrowMode := gfGrowHiX;
end;

procedure TPathHeader.Draw;
var
  B: TDrawBuffer;
  Color: Byte;
  S: ShortString;
  MidX, SourceWidth, TargetWidth: Integer;
begin
  Color := $1E; { Yellow on blue }
  MoveChar(B, ' ', Color, Size.X);

  MidX := Size.X div 2;
  SourceWidth := MidX;
  TargetWidth := Size.X - MidX;

  { Draw source path }
  if FSourcePath <> nil then
  begin
    S := ShortString('Source: ' + FSourcePath^);
    if Length(S) > SourceWidth then
      S := Copy(S, 1, SourceWidth - 3) + '...';
    MoveStr(B, S, Color);
  end;

  { Draw target path }
  if FTargetPath <> nil then
  begin
    S := ShortString('Target: ' + FTargetPath^);
    if Length(S) > TargetWidth then
      S := Copy(S, 1, TargetWidth - 3) + '...';
    MoveStr(B[MidX], S, Color);
  end;

  WriteLine(0, 0, Size.X, 1, B);
end;

procedure TPathHeader.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  MidX: Integer;
begin
  { Handle double-click BEFORE inherited to open folder selection }
  if (Event.What = evMouseDown) and Event.Double then
  begin
    MakeLocal(Event.Where, Mouse);
    MidX := Size.X div 2;
    Event.What := evCommand;
    if Mouse.X < MidX then
      Event.Command := cmSelectSource
    else
      Event.Command := cmSelectTarget;
    PutEvent(Event);
    ClearEvent(Event);
    Exit;
  end;

  inherited HandleEvent(Event);
end;

{ -------------------------------------------------------------------------- }
{ TKeepTossStatusLine }
{ -------------------------------------------------------------------------- }

function TKeepTossStatusLine.Hint(AHelpCtx: Word): ShortString;
begin
  if (FAutoPlay <> nil) and FAutoPlay^ then
    Result := 'AutoPlay: ON'
  else
    Result := 'AutoPlay: OFF';
end;

{ -------------------------------------------------------------------------- }
{ TKeepTossApp }
{ -------------------------------------------------------------------------- }

constructor TKeepTossApp.Create;
begin
  inherited Create;

  { Initialize state }
  AutoPlay := False;
  IsPlaying := False;
  LastOp := opNone;
  LastFocused := -1;
  PathHeader := nil;
  SourceList := nil;
  TargetList := nil;
  SourceScrollBar := nil;
  TargetScrollBar := nil;

  { Check command line arguments }
  if ParamCount >= 1 then
  begin
    SourceFolder := ParamStr(1);
    { Validate source folder exists }
    if not DirectoryExists(SourceFolder) then
    begin
      MessageBox('Source folder does not exist: ' + SourceFolder, nil, mfError + mfOKButton);
      SourceFolder := '';
    end;
  end;
  if ParamCount >= 2 then
  begin
    TargetFolder := Trim(ParamStr(2));
    { Validate target path is usable (don't create it yet) }
    if (TargetFolder <> '') and not IsValidPath(TargetFolder) then
    begin
      MessageBox('Invalid target path: ' + TargetFolder, nil, mfError + mfOKButton);
      TargetFolder := '';
    end;
  end;

  { Prompt for source folder if not provided or invalid }
  if SourceFolder = '' then
  begin
    SelectSourceFolder;
    if SourceFolder = '' then
      Exit; { User cancelled }
  end;

  { Prompt for target folder if not provided }
  if TargetFolder = '' then
  begin
    SelectTargetFolder;
    if TargetFolder = '' then
      Exit; { User cancelled }
  end;

  { Create dual list views }
  CreateListViews;

  { Load samples in both lists }
  RefreshLists;
end;

destructor TKeepTossApp.Destroy;
begin
  { Stop any playing sound }
  sndPlaySound(nil, 0);
  inherited Destroy;
end;

procedure TKeepTossApp.InitMenuBar;
var
  R: TRect;
begin
  GetExtent(R);
  R.B.Y := R.A.Y + 1;
  MenuBar := TMenuBar.Create(R, NewMenu(
    NewSubMenu('~F~ile', hcNoContext, NewMenu(
      NewItem('~S~ource Folder...', '', 0, cmSelectSource, hcNoContext,
      NewItem('~T~arget Folder...', '', 0, cmSelectTarget, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt-X', kbAltX, cmQuit, hcNoContext, nil))))),
    NewSubMenu('~A~ction', hcNoContext, NewMenu(
      NewItem('~C~opy', 'C', 0, cmCopy, hcNoContext,
      NewItem('~M~ove', 'M', 0, cmMove, hcNoContext,
      NewItem('~D~elete', 'X', 0, cmDelete, hcNoContext,
      NewItem('~U~ndo', 'Z', 0, cmUndo, hcNoContext, nil))))),
    NewSubMenu('~O~ptions', hcNoContext, NewMenu(
      NewItem('Toggle ~A~utoplay', 'A', 0, cmToggleAuto, hcNoContext, nil)),
    nil)))));
end;

procedure TKeepTossApp.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  StatusLine := TKeepTossStatusLine.Create(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~Space~ Play', 0, 0,
      NewStatusKey('~C~opy', 0, 0,
      NewStatusKey('~M~ove', 0, 0,
      NewStatusKey('~X~ Del', 0, 0,
      NewStatusKey('~N~/~P~ Nav', 0, 0,
      NewStatusKey('~S~wap', 0, 0,
      NewStatusKey('~R~efresh', 0, 0,
      NewStatusKey('~A~uto', 0, 0,
      NewStatusKey('~Alt-X~ Exit', kbAltX, cmQuit, nil))))))))), nil));
  TKeepTossStatusLine(StatusLine).FAutoPlay := @AutoPlay;
end;

procedure TKeepTossApp.HandleEvent(var Event: TEvent);
begin
  { Handle space BEFORE inherited - TListViewer consumes space for selection }
  if Event.What = evKeyDown then
  begin
    if Event.CharCode = ' ' then
    begin
      if IsPlaying then
        DoStop
      else
        DoPlay;
      ClearEvent(Event);
      Exit;
    end;
  end;

  inherited HandleEvent(Event);

  if Event.What = evKeyDown then
  begin
    case Event.CharCode of
      'c', 'C':
        begin
          DoCopy;
          ClearEvent(Event);
        end;
      'm', 'M':
        begin
          DoMove;
          ClearEvent(Event);
        end;
      'x':
        begin
          DoDelete(True);  { With confirmation }
          ClearEvent(Event);
        end;
      'X':
        begin
          DoDelete(False); { Shift+X = no confirmation }
          ClearEvent(Event);
        end;
      'z', 'Z':
        begin
          DoUndo;
          ClearEvent(Event);
        end;
      'a', 'A':
        begin
          ToggleAutoPlay;
          ClearEvent(Event);
        end;
      's', 'S':
        begin
          DoSwapFolders;
          ClearEvent(Event);
        end;
      'n', 'N':
        begin
          { Select next sample (same as arrow down) }
          if (SourceList <> nil) and (SourceList.Focused < SourceList.FCount - 1) then
            SourceList.FocusItem(SourceList.Focused + 1);
          ClearEvent(Event);
        end;
      'p', 'P':
        begin
          { Select previous sample (same as arrow up) }
          if (SourceList <> nil) and (SourceList.Focused > 0) then
            SourceList.FocusItem(SourceList.Focused - 1);
          ClearEvent(Event);
        end;
      'r', 'R':
        begin
          { Refresh both lists }
          RefreshLists;
          ClearEvent(Event);
        end;
    end;
  end
  else if Event.What = evCommand then
  begin
    case Event.Command of
      cmSelectSource:
        begin
          SelectSourceFolder;
          if SourceFolder <> '' then
          begin
            RefreshLists;
            if PathHeader <> nil then
              PathHeader.DrawView;
          end;
        end;
      cmSelectTarget:
        begin
          SelectTargetFolder;
          if TargetFolder <> '' then
          begin
            RefreshLists;
            if PathHeader <> nil then
              PathHeader.DrawView;
          end;
        end;
      cmCopy:
        DoCopy;
      cmMove:
        DoMove;
      cmDelete:
        DoDelete(True);
      cmUndo:
        DoUndo;
      cmToggleAuto:
        ToggleAutoPlay;
    else
      Exit;
    end;
    ClearEvent(Event);
  end;
end;

procedure TKeepTossApp.Idle;
begin
  inherited Idle;

  { Handle navigation - detect when focused item changes }
  if SourceList <> nil then
  begin
    if SourceList.Focused <> LastFocused then
    begin
      LastFocused := SourceList.Focused;
      if AutoPlay then
        DoPlay
      else
        DoStop; { Stop playback when navigating in manual mode }
    end;
  end;
end;

procedure TKeepTossApp.SelectSourceFolder;
var
  S: string;
begin
  { Use current source folder, or default to current directory }
  if SourceFolder <> '' then
    S := SourceFolder
  else
    S := GetCurrentDir;
  if FolderInputBox('Source Folder', 'Path:', S) = cmOk then
    SourceFolder := S;
  { On Cancel, keep the existing SourceFolder value }
end;

procedure TKeepTossApp.SelectTargetFolder;
var
  S: string;
begin
  { Use current target folder, or default to source folder }
  if TargetFolder <> '' then
    S := TargetFolder
  else
    S := SourceFolder;
  if FolderInputBox('Target Folder', 'Path:', S) = cmOk then
    TargetFolder := S;
  { On Cancel, keep the existing TargetFolder value }
end;

procedure TKeepTossApp.CreateListViews;
var
  R: TRect;
  MidX: Integer;
begin
  if Desktop = nil then Exit;

  Desktop.GetExtent(R);
  MidX := (R.A.X + R.B.X) div 2;

  { Header row showing folder paths }
  R.B.Y := R.A.Y + 1;
  PathHeader := TPathHeader.Create(R, @SourceFolder, @TargetFolder);
  Desktop.Insert(PathHeader);

  { Left side: Source list with scrollbar (below header) }
  Desktop.GetExtent(R);
  R.A.Y := R.A.Y + 1; { Start below header }
  R.A.X := MidX - 1;
  R.B.X := MidX;
  SourceScrollBar := TScrollBar.Create(R);

  Desktop.GetExtent(R);
  R.A.Y := R.A.Y + 1; { Start below header }
  R.B.X := MidX - 1;
  SourceList := TSampleListView.Create(R, SourceScrollBar, True);  { IsSource = True }
  Desktop.Insert(SourceList);
  Desktop.Insert(SourceScrollBar);  { Insert after list so it draws on top }

  { Right side: Target list with scrollbar (below header) }
  Desktop.GetExtent(R);
  R.A.Y := R.A.Y + 1; { Start below header }
  R.A.X := R.B.X - 1;
  TargetScrollBar := TScrollBar.Create(R);

  Desktop.GetExtent(R);
  R.A.Y := R.A.Y + 1; { Start below header }
  R.A.X := MidX;
  R.B.X := R.B.X - 1;
  TargetList := TSampleListView.Create(R, TargetScrollBar, False);  { IsSource = False }
  Desktop.Insert(TargetList);
  Desktop.Insert(TargetScrollBar);  { Insert after list so it draws on top }

  { Ensure scrollbars are visible }
  SourceScrollBar.Show;
  TargetScrollBar.Show;

  { Focus source list }
  SourceList.Select;
end;

procedure TKeepTossApp.RefreshLists;
begin
  if SourceList <> nil then
  begin
    SourceList.LoadFolder(SourceFolder);
    if SourceList.FCount = 0 then
      MessageBox('No WAV files found in source folder.', nil, mfInformation + mfOKButton);
  end;
  if TargetList <> nil then
  begin
    { Only load if directory exists - don't create it just for display }
    if DirectoryExists(TargetFolder) then
      TargetList.LoadFolder(TargetFolder)
    else
    begin
      TargetList.FCount := 0;
      SetLength(TargetList.FSamples, 0);
      TargetList.SetRange(0);
      TargetList.DrawView;
    end;
  end;
end;

procedure TKeepTossApp.DoSwapFolders;
var
  Temp: string;
begin
  Temp := SourceFolder;
  SourceFolder := TargetFolder;
  TargetFolder := Temp;
  RefreshLists;
  { Redraw header to show new paths }
  if PathHeader <> nil then
    PathHeader.DrawView;
  LastOp := opNone; { Clear undo after swap }
end;

procedure TKeepTossApp.DoPlay;
var
  Path: string;
begin
  if (SourceList = nil) or (SourceList.FCount = 0) then Exit;

  Path := SourceList.GetFullPath(SourceList.Focused);
  if Path = '' then Exit;

  { Stop any currently playing sound }
  sndPlaySound(nil, 0);

  { Play the new file asynchronously }
  IsPlaying := sndPlaySound(PChar(Path), SND_ASYNC or SND_NODEFAULT);
end;

procedure TKeepTossApp.DoStop;
begin
  sndPlaySound(nil, 0);
  IsPlaying := False;
end;

procedure TKeepTossApp.DoCopy;
var
  Src, Dest: string;
begin
  if SourceList = nil then Exit;
  if SourceList.FCount = 0 then
  begin
    MessageBox('No WAV files in source folder.', nil, mfInformation + mfOKButton);
    Exit;
  end;
  if TargetFolder = '' then
  begin
    MessageBox('No target folder selected.', nil, mfError + mfOKButton);
    Exit;
  end;
  if SameText(SourceFolder, TargetFolder) then
  begin
    MessageBox('Source and target folders are the same.', nil, mfWarning + mfOKButton);
    Exit;
  end;

  { Ensure target folder exists }
  if not EnsureDirectoryExists(TargetFolder) then
  begin
    MessageBox('Cannot access target folder.', nil, mfError + mfOKButton);
    Exit;
  end;

  Src := SourceList.GetFullPath(SourceList.Focused);
  Dest := GetUniqueDestPath(TargetFolder, SourceList.GetFileName(SourceList.Focused));

  if Winapi.Windows.CopyFile(PChar(Src), PChar(Dest), True) then
  begin
    LastOp := opCopy;
    LastSrcFile := Src;
    LastDestFile := Dest;
    LastIndex := SourceList.Focused;
    AdvanceNext;
    { Refresh target list to show new file }
    if TargetList <> nil then
      TargetList.LoadFolder(TargetFolder);
  end
  else
    MessageBox('Failed to copy file.', nil, mfError + mfOKButton);
end;

procedure TKeepTossApp.DoMove;
var
  Src, Dest: string;
  Idx: Integer;
begin
  if SourceList = nil then Exit;
  if SourceList.FCount = 0 then
  begin
    MessageBox('No WAV files in source folder.', nil, mfInformation + mfOKButton);
    Exit;
  end;
  if TargetFolder = '' then
  begin
    MessageBox('No target folder selected.', nil, mfError + mfOKButton);
    Exit;
  end;
  if SameText(SourceFolder, TargetFolder) then
  begin
    MessageBox('Source and target folders are the same.', nil, mfWarning + mfOKButton);
    Exit;
  end;

  { Ensure target folder exists }
  if not EnsureDirectoryExists(TargetFolder) then
  begin
    MessageBox('Cannot access target folder.', nil, mfError + mfOKButton);
    Exit;
  end;

  Idx := SourceList.Focused;
  Src := SourceList.GetFullPath(Idx);
  Dest := GetUniqueDestPath(TargetFolder, SourceList.GetFileName(Idx));

  if Winapi.Windows.MoveFileEx(PChar(Src), PChar(Dest), MOVEFILE_COPY_ALLOWED) then
  begin
    LastOp := opMove;
    LastSrcFile := Src;
    LastDestFile := Dest;
    LastIndex := Idx;
    DoStop; { Stop playing if this file was playing }
    SourceList.RemoveItem(Idx);
    { Update LastFocused and trigger autoplay }
    LastFocused := SourceList.Focused;
    if AutoPlay and (SourceList.FCount > 0) then
      DoPlay;
    { Refresh target list to show new file }
    if TargetList <> nil then
      TargetList.LoadFolder(TargetFolder);
  end
  else
    MessageBox('Failed to move file.', nil, mfError + mfOKButton);
end;

procedure TKeepTossApp.DoDelete(Confirm: Boolean);
var
  Src, Backup: string;
  Idx: Integer;
begin
  if SourceList = nil then Exit;
  if SourceList.FCount = 0 then
  begin
    MessageBox('No WAV files in source folder.', nil, mfInformation + mfOKButton);
    Exit;
  end;

  if Confirm then
  begin
    if MessageBox('Delete this file?', nil, mfConfirmation + mfYesNoCancel) <> cmYes then
      Exit;
  end;

  Idx := SourceList.Focused;
  Src := SourceList.GetFullPath(Idx);
  { Use unique temp filename to avoid collision with previous deletes }
  Backup := TPath.GetTempPath + 'KeepToss_' + IntToStr(GetTickCount) + '_' + SourceList.GetFileName(Idx);

  { Move to temp folder for undo capability }
  if Winapi.Windows.MoveFile(PChar(Src), PChar(Backup)) then
  begin
    LastOp := opDelete;
    LastSrcFile := Src;
    LastDestFile := Backup;
    LastIndex := Idx;
    DoStop; { Stop playing if this file was playing }
    SourceList.RemoveItem(Idx);
    { Update LastFocused and trigger autoplay }
    LastFocused := SourceList.Focused;
    if AutoPlay and (SourceList.FCount > 0) then
      DoPlay;
  end
  else
    MessageBox('Failed to delete file.', nil, mfError + mfOKButton);
end;

procedure TKeepTossApp.DoUndo;
begin
  case LastOp of
    opCopy:
      begin
        if System.SysUtils.DeleteFile(LastDestFile) then
        begin
          LastOp := opNone;
          { Refresh target list }
          if TargetList <> nil then
            TargetList.LoadFolder(TargetFolder);
          MessageBox('Copy undone.', nil, mfInformation + mfOKButton);
        end
        else
          MessageBox('Failed to undo copy.', nil, mfError + mfOKButton);
      end;
    opMove:
      begin
        if Winapi.Windows.MoveFile(PChar(LastDestFile), PChar(LastSrcFile)) then
        begin
          SourceList.LoadFolder(SourceFolder);
          if LastIndex < SourceList.FCount then
            SourceList.FocusItem(LastIndex);
          LastOp := opNone;
          { Refresh target list }
          if TargetList <> nil then
            TargetList.LoadFolder(TargetFolder);
          MessageBox('Move undone.', nil, mfInformation + mfOKButton);
        end
        else
          MessageBox('Failed to undo move.', nil, mfError + mfOKButton);
      end;
    opDelete:
      begin
        if Winapi.Windows.MoveFile(PChar(LastDestFile), PChar(LastSrcFile)) then
        begin
          SourceList.LoadFolder(SourceFolder);
          if LastIndex < SourceList.FCount then
            SourceList.FocusItem(LastIndex);
          LastOp := opNone;
          MessageBox('Delete undone.', nil, mfInformation + mfOKButton);
        end
        else
          MessageBox('Failed to undo delete.', nil, mfError + mfOKButton);
      end;
    opNone:
      MessageBox('Nothing to undo.', nil, mfInformation + mfOKButton);
  end;
end;

procedure TKeepTossApp.ToggleAutoPlay;
begin
  AutoPlay := not AutoPlay;
  if StatusLine <> nil then
    StatusLine.DrawView;
end;

procedure TKeepTossApp.AdvanceNext;
var
  CurIdx: Integer;
begin
  if SourceList = nil then Exit;

  CurIdx := SourceList.Focused;
  if CurIdx < SourceList.FCount - 1 then
  begin
    SourceList.FocusItem(CurIdx + 1);
    LastFocused := SourceList.Focused; { Update to prevent autoplay re-trigger }
    if AutoPlay then
      DoPlay;
  end;
end;

{ -------------------------------------------------------------------------- }
{ Main program }
{ -------------------------------------------------------------------------- }

begin
  try
    { Double-click delay in ticks (default 8 = ~440ms) }
    DoubleDelay := 8;

    KeepTossApp := TKeepTossApp.Create;
    if (KeepTossApp.SourceFolder <> '') and (KeepTossApp.TargetFolder <> '') then
      KeepTossApp.Run;
    FreeAndNil(KeepTossApp);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
