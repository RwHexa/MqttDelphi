unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics,
  Dialogs, StdCtrls, ExtCtrls, ComCtrls, RolloControl, mqtt_synapse, ssl_openssl_lib;

type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    // Topbar
    PanelTop        : TPanel;
    // Scroll + Wrapper
    ScrollBox       : TScrollBox;
    PanelWrapper    : TPanel;
    LabelTitle      : TLabel;
    PanelConnState  : TPanel;
    LabelConnState  : TLabel;
    BtnConnect      : TButton;
    // Geräte-Panels
    PanelShelly     : TPanel;
    PanelRollo         : TPanel;
    PanelESP        : TPanel;
    // Shelly 1PM
    LabelShellyTitle : TLabel;
    LabelShellySub   : TLabel;
    LabelShellyState : TLabel;
    PanelShellyState : TPanel;
    LabelWattV, LabelVoltV, LabelAmpV, LabelSTempV : TLabel;
    LabelWattL, LabelVoltL, LabelAmpL, LabelSTempL : TLabel;
    BtnShellyEin, BtnShellyAus : TButton;
    LabelShellyTS    : TLabel;
    // Rollo-Demo
    LabelRolloTitle : TLabel;
    Rollo           : TRolloControl;
    TrackBarRollo   : TTrackBar;
    LabelRolloPos   : TLabel;
    // ESP32
    LabelESPTitle, LabelESPSub : TLabel;
    PanelESPState  : TPanel;
    LabelESPState  : TLabel;
    LabelESPTempV, LabelESPHumV               : TLabel;
    LabelESPTempL, LabelESPHumL               : TLabel;
    BtnESPEin, BtnESPAus : TButton;
    ImgLamp          : TImage;
    LabelESPTS       : TLabel;
    // Log
    PanelLog        : TPanel;
    MemoLog         : TMemo;
    BtnClearLog     : TButton;
    // Timer
    TimerPoll       : TTimer;
    TimerPing       : TTimer;
    // Navigation (unten)
    PanelNav        : TPanel;
    BtnNav1         : TButton;   // Übersicht
    BtnNav2         : TButton;   // Seite 2
    // Seite 2
    PanelPage2      : TPanel;
    // MQTT
    MQTT            : TMQTTSynapse;

    procedure BtnConnectClick(Sender: TObject);
    procedure BtnShellyEinClick(Sender: TObject);
    procedure BtnShellyAusClick(Sender: TObject);
    procedure BtnESPEinClick(Sender: TObject);
    procedure BtnESPAusClick(Sender: TObject);
    procedure TrackBarRolloChange(Sender: TObject);
    procedure BtnClearLogClick(Sender: TObject);
    procedure TimerPollTimer(Sender: TObject);
    procedure TimerPingTimer(Sender: TObject);

    procedure ShowPage(APage: Integer);
    procedure BtnNav1Click(Sender: TObject);
    procedure BtnNav2Click(Sender: TObject);
    procedure Log(const AMsg: string);
    procedure SetConnected(AOn: Boolean);
    procedure SetShellyRelay(AOn: Boolean);
    procedure ArrangeLayout;
    procedure HandleMessage(const ATopic, APayload: string);
    procedure HandleShelly(const APayload: string);
    procedure HandleESP(const ATopic, APayload: string);
    procedure PaintCardPanel(Sender: TObject);
    function  MakeLabel(AParent: TWinControl; const ACaption: string;
                        ALeft, ATop, AFontSize: Integer;
                        ABold: Boolean = False): TLabel;
    procedure MakeMetric(AParent: TWinControl; ATop: Integer;
                         const ACaption: string;
                         out LVal, LLbl: TLabel);
    function  JsonStr(const AJson, AKey: string): string;
    function  JsonFloat(const AJson, AKey: string): Double;
    function  JsonBool(const AJson, AKey: string): Boolean;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

const
  HIVEMQ_HOST = '85484da2efb94762bdf2d25a3c8df9a0.s1.eu.hivemq.cloud';
  HIVEMQ_PORT = '8883';
  HIVEMQ_USER = 'lazarususer';
  HIVEMQ_PASS = 'Laz12345';
  SHELLY_ID   = 'shelly1pmminig3-34b7dac507e0';
  ESP_TOPIC   = 'esp32/sensor';
  CARD_W      = 230;
  CARD_H      = 330;
  GAP         = 12;
  NAV_H       = 48;   // Höhe der Navigationsleiste

// ── JSON ──────────────────────────────────────────────────────

function TForm1.JsonStr(const AJson, AKey: string): string;
var P, PE: Integer;
begin
  Result := '';
  P := Pos('"' + AKey + '"', AJson);
  if P = 0 then Exit;
  P := P + Length(AKey) + 2;
  while (P <= Length(AJson)) and (AJson[P] in [' ',':']) do Inc(P);
  if P > Length(AJson) then Exit;
  if AJson[P] = '"' then
  begin
    Inc(P); PE := P;
    while (PE <= Length(AJson)) and (AJson[PE] <> '"') do Inc(PE);
    Result := Copy(AJson, P, PE - P);
  end
  else
  begin
    PE := P;
    while (PE <= Length(AJson)) and not (AJson[PE] in [',','}',']']) do Inc(PE);
    Result := Trim(Copy(AJson, P, PE - P));
  end;
end;

function TForm1.JsonFloat(const AJson, AKey: string): Double;
var S: string;
begin
  S := JsonStr(AJson, AKey);
  S := StringReplace(S, '.', DefaultFormatSettings.DecimalSeparator, []);
  Result := StrToFloatDef(S, 0.0);
end;

function TForm1.JsonBool(const AJson, AKey: string): Boolean;
begin
  Result := LowerCase(JsonStr(AJson, AKey)) = 'true';
end;

// ── Hilfs-Konstruktoren ───────────────────────────────────────

function TForm1.MakeLabel(AParent: TWinControl; const ACaption: string;
  ALeft, ATop, AFontSize: Integer; ABold: Boolean): TLabel;
begin
  Result            := TLabel.Create(Self);
  Result.Parent     := AParent;
  Result.Caption    := ACaption;
  Result.Left       := ALeft;
  Result.Top        := ATop;
  Result.Font.Size  := AFontSize;
  if ABold then Result.Font.Style := [fsBold];
end;

procedure TForm1.MakeMetric(AParent: TWinControl; ATop: Integer;
  const ACaption: string; out LVal, LLbl: TLabel);
begin
  LLbl := MakeLabel(AParent, ACaption, 10, ATop,      9);
  LLbl.Font.Color := clGray;
  LVal := MakeLabel(AParent, '--',     10, ATop + 16, 14, True);
end;

function MakePanel(AOwner: TComponent; AParent: TWinControl;
  ALeft, ATop, AW, AH: Integer; AColor: TColor): TPanel;
begin
  Result            := TPanel.Create(AOwner);
  Result.Parent     := AParent;
  Result.SetBounds(ALeft, ATop, AW, AH);
  Result.BevelOuter := bvNone;
  Result.Color      := AColor;
end;

function MakeButton(AOwner: TComponent; AParent: TWinControl;
  const ACaption: string; ALeft, ATop, AW, AH: Integer;
  AColor: TColor; AHandler: TNotifyEvent): TButton;
begin
  Result           := TButton.Create(AOwner);
  Result.Parent    := AParent;
  Result.Caption   := ACaption;
  Result.SetBounds(ALeft, ATop, AW, AH);
  Result.Font.Color := AColor;
  Result.OnClick   := AHandler;
end;

// ── Layout zentrieren ─────────────────────────────────────────

procedure TForm1.ArrangeLayout;
var
  TotalW, TotalH, SBW, SBH, WrapX, WrapY: Integer;
begin
  // Gesamtgröße des Inhalts
  TotalW := 3 * CARD_W + 2 * GAP;           // Breite: 3 Karten
  TotalH := CARD_H + GAP + 130;             // Höhe: Karten + Log

  // ScrollBox: füllt alles unter dem Header
  ScrollBox.SetBounds(
    0,
    PanelTop.Top + PanelTop.Height + 4,
    ClientWidth,
    ClientHeight - PanelTop.Top - PanelTop.Height - 4 - NAV_H
  );

  SBW := ScrollBox.ClientWidth;
  SBH := ScrollBox.ClientHeight;

  // PanelWrapper: mindestens so groß wie der Inhalt
  PanelWrapper.SetBounds(0, 0, Max(SBW, TotalW + 16), Max(SBH, TotalH + 16));

  // Inhalt horizontal + vertikal zentrieren im Wrapper
  WrapX := (PanelWrapper.Width  - TotalW) div 2;
  WrapY := (PanelWrapper.Height - TotalH) div 2;
  if WrapX < 8 then WrapX := 8;
  if WrapY < 8 then WrapY := 8;

  // Karten positionieren (relativ zum PanelWrapper)
  PanelShelly.SetBounds(WrapX,                     WrapY, CARD_W, CARD_H);
  PanelRollo.SetBounds (WrapX + CARD_W + GAP,      WrapY, CARD_W, CARD_H);
  PanelESP.SetBounds   (WrapX + 2*(CARD_W + GAP),  WrapY, CARD_W, CARD_H);
  PanelLog.SetBounds   (WrapX, WrapY + CARD_H + GAP, TotalW, 130);
end;

// ── FormCreate ────────────────────────────────────────────────

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption  := 'Rw Vers.:26/03.28';
  Color    := $00F0F0EC;
  Width    := 800;
  Height   := 580;
  Position := poScreenCenter;

  // ── Flackern beim Resize verhindern ──────────────────────────
  DoubleBuffered := True;

  // Topbar
  PanelTop       := MakePanel(Self, Self, 8, 8, ClientWidth - 16, 48, clWhite);
  PanelTop.Anchors := [akLeft, akTop, akRight];

  LabelTitle     := MakeLabel(PanelTop, 'SmartHome-Steuerung', 12, 14, 13, True);

  PanelConnState := MakePanel(Self, PanelTop, PanelTop.Width-280, 10, 150, 28, $00FFC0C0);
  PanelConnState.Anchors := [akTop, akRight];
  LabelConnState := MakeLabel(PanelConnState, '○ Getrennt', 8, 6, 10, True);
  LabelConnState.Font.Color := clMaroon;

  BtnConnect     := MakeButton(Self, PanelTop, 'Verbinden',
                      PanelTop.Width - 120, 10, 110, 28, clDefault, @BtnConnectClick);
  BtnConnect.Anchors := [akTop, akRight];

  // ── ScrollBox (füllt Bereich unter Header) ──────────────────
  ScrollBox                  := TScrollBox.Create(Self);
  ScrollBox.Parent           := Self;
  ScrollBox.BorderStyle      := bsNone;
  ScrollBox.Color            := $00F0F0EC;
  ScrollBox.HorzScrollBar.Tracking := True;
  ScrollBox.VertScrollBar.Tracking := True;
  ScrollBox.Anchors          := [akLeft, akTop, akRight, akBottom];
  ScrollBox.DoubleBuffered   := True;
  ScrollBox.SetBounds(0, PanelTop.Top + PanelTop.Height + 4,
                      ClientWidth, ClientHeight - PanelTop.Top - PanelTop.Height - 4);

  // PanelWrapper: der zentrierte Container innerhalb der ScrollBox
  PanelWrapper               := TPanel.Create(Self);
  PanelWrapper.Parent        := ScrollBox;
  PanelWrapper.BevelOuter    := bvNone;
  PanelWrapper.Color         := $00F0F0EC;
  PanelWrapper.DoubleBuffered := True;
  // Größe = 3 Karten + Log, wird in ArrangeLayout gesetzt

  // ── Shelly 1PM ───────────────────────────────────────────────
  PanelShelly    := MakePanel(Self, PanelWrapper, 0, 0, CARD_W, CARD_H, clWhite);
  PanelShelly.OnPaint := @PaintCardPanel;

  MakeLabel(PanelShelly, 'Shelly 1PM Mini',      10, 10, 11, True);
  MakeLabel(PanelShelly, 'Steckdose Wohnzimmer', 10, 28,  9).Font.Color := clGray;

  PanelShellyState := MakePanel(Self, PanelShelly, 148, 8, 72, 26, clSilver);
  LabelShellyState := MakeLabel(PanelShellyState, '--', 16, 5, 10, True);

  MakeMetric(PanelShelly,  52, 'Leistung',    LabelWattV,  LabelWattL);
  MakeMetric(PanelShelly,  92, 'Spannung',    LabelVoltV,  LabelVoltL);
  MakeMetric(PanelShelly, 132, 'Strom',       LabelAmpV,   LabelAmpL);
  MakeMetric(PanelShelly, 172, 'Temperatur',  LabelSTempV, LabelSTempL);

  LabelWattV.Caption  := '-- W';
  LabelVoltV.Caption  := '-- V';
  LabelAmpV.Caption   := '-- A';
  LabelSTempV.Caption := '-- °C';

  BtnShellyEin := MakeButton(Self, PanelShelly, 'EIN',
                    10, 220, 100, 38, clGreen, @BtnShellyEinClick);
  BtnShellyEin.Font.Size  := 11;
  BtnShellyEin.Font.Style := [fsBold];
  BtnShellyEin.Color      := $0000C000;
  BtnShellyAus := MakeButton(Self, PanelShelly, 'AUS',
                    118, 220, 100, 38, clWhite, @BtnShellyAusClick);
  BtnShellyAus.Font.Size  := 11;
  BtnShellyAus.Font.Style := [fsBold];
  BtnShellyAus.Color      := $000000CC;
  BtnShellyEin.Enabled := False;
  BtnShellyAus.Enabled := False;

  LabelShellyTS := MakeLabel(PanelShelly, '', 10, 270, 8);
  LabelShellyTS.Font.Color := clGray;

  // ── Shelly H&T ────────────────────────────────────────────────
  PanelRollo := MakePanel(Self, PanelWrapper, 0, 0, CARD_W, CARD_H, clWhite);
  PanelRollo.OnPaint := @PaintCardPanel;

  // Titel
  LabelRolloTitle := MakeLabel(PanelRollo, 'Rollo-Demo', 10, 10, 11, True);
  MakeLabel(PanelRollo, 'Handbedienung', 10, 28, 9).Font.Color := clGray;

  // TRolloControl - die visuelle Rollo-Komponente
  Rollo          := TRolloControl.Create(Self);
  Rollo.Parent   := PanelRollo;
  Rollo.SetBounds(25, 48, 180, 160);
  Rollo.Position := 50;

  // Positionsanzeige
  LabelRolloPos            := TLabel.Create(Self);
  LabelRolloPos.Parent     := PanelRollo;
  LabelRolloPos.Caption    := 'Position: 50 %';
  LabelRolloPos.Font.Style := [fsBold];
  LabelRolloPos.Font.Size  := 10;
  LabelRolloPos.Left       := 10;
  LabelRolloPos.Top        := 218;

  // TrackBar für Handbedienung
  TrackBarRollo             := TTrackBar.Create(Self);
  TrackBarRollo.Parent      := PanelRollo;
  TrackBarRollo.SetBounds(10, 240, CARD_W - 20, 36);
  TrackBarRollo.Min         := 0;
  TrackBarRollo.Max         := 100;
  TrackBarRollo.Position    := 50;
  TrackBarRollo.TickStyle   := tsNone;
  TrackBarRollo.OnChange    := @TrackBarRolloChange;

  // ── ESP32 ─────────────────────────────────────────────────────
  PanelESP := MakePanel(Self, PanelWrapper, 0, 0, CARD_W, CARD_H, clWhite);
  PanelESP.OnPaint := @PaintCardPanel;

  MakeLabel(PanelESP, 'ESP32 Sensor', 10, 10, 11, True);
  MakeLabel(PanelESP, 'LED Pin 32',   10, 28,  9).Font.Color := clGray;

  // LED-Status Panel (oben rechts)
  PanelESPState            := TPanel.Create(Self);
  PanelESPState.Parent     := PanelESP;
  PanelESPState.SetBounds(148, 8, 72, 26);
  PanelESPState.BevelOuter := bvNone;
  PanelESPState.Color      := clSilver;
  LabelESPState            := MakeLabel(PanelESPState, '--', 16, 5, 10, True);

  MakeMetric(PanelESP,  52, 'Temperatur',  LabelESPTempV, LabelESPTempL);
  MakeMetric(PanelESP,  92, 'Luftfeuchte', LabelESPHumV,  LabelESPHumL);
  LabelESPTempV.Caption := '-- °C';
  LabelESPHumV.Caption  := '-- %';

  BtnESPEin := MakeButton(Self, PanelESP, 'EIN',
                  10, 150, 100, 38, clGreen, @BtnESPEinClick);
  BtnESPEin.Font.Size  := 11;
  BtnESPEin.Font.Style := [fsBold];
  BtnESPEin.Color      := $0000C000;
  BtnESPAus := MakeButton(Self, PanelESP, 'AUS',
                  118, 150, 100, 38, clWhite, @BtnESPAusClick);
  BtnESPAus.Font.Size  := 11;
  BtnESPAus.Font.Style := [fsBold];
  BtnESPAus.Color      := $000000CC;
  BtnESPEin.Enabled := False;
  BtnESPAus.Enabled := False;

  // Lampen-Symbol unter den Buttons
  ImgLamp                   := TImage.Create(Self);
  ImgLamp.Parent            := PanelESP;
  ImgLamp.SetBounds(70, 192, 90, 90);
  ImgLamp.Stretch           := True;
  ImgLamp.Center            := True;
  ImgLamp.Transparent       := False;
  // Bild laden - lampauskl.png als Standard
  if FileExists(ExtractFilePath(ParamStr(0)) + 'lampauskl.png') then
    ImgLamp.Picture.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'lampauskl.png');

  LabelESPTS := MakeLabel(PanelESP, '', 10, 296, 8);
  LabelESPTS.Font.Color := clGray;

  // ── Log ───────────────────────────────────────────────────────
  PanelLog := MakePanel(Self, PanelWrapper, 0, 0, 718, 130, clWhite);

  MakeLabel(PanelLog, 'MQTT Log', 10, 8, 9, True).Font.Color := clGray;

  MemoLog           := TMemo.Create(Self);
  MemoLog.Parent    := PanelLog;
  MemoLog.SetBounds(10, 26, 618, 90);
  MemoLog.ReadOnly  := True;
  MemoLog.ScrollBars := ssVertical;
  MemoLog.Font.Size := 8;

  BtnClearLog := MakeButton(Self, PanelLog, 'Löschen',
                   636, 26, 72, 28, clDefault, @BtnClearLogClick);

  // ── Timer ─────────────────────────────────────────────────────
  TimerPoll          := TTimer.Create(Self);
  TimerPoll.Interval := 200;
  TimerPoll.Enabled  := False;
  TimerPoll.OnTimer  := @TimerPollTimer;

  TimerPing          := TTimer.Create(Self);
  TimerPing.Interval := 25000;
  TimerPing.Enabled  := False;
  TimerPing.OnTimer  := @TimerPingTimer;

  // ── Navigationsleiste (unten fixiert) ───────────────────────
  PanelNav               := TPanel.Create(Self);
  PanelNav.Parent        := Self;
  PanelNav.BevelOuter    := bvNone;
  PanelNav.Color         := $00333333;
  PanelNav.DoubleBuffered := True;
  PanelNav.Anchors       := [akLeft, akBottom, akRight];
  PanelNav.SetBounds(0, ClientHeight - NAV_H, ClientWidth, NAV_H);

  BtnNav1 := TButton.Create(Self);
  BtnNav1.Parent   := PanelNav;
  BtnNav1.Caption  := '🏠  Übersicht';
  BtnNav1.SetBounds((ClientWidth div 2) - 116, 8, 110, 32);
  BtnNav1.Font.Color := clBlack;
  BtnNav1.Font.Style := [fsBold];
  BtnNav1.Color      := $00E8C87E;   // gedämpftes Gelb = aktiv
  BtnNav1.OnClick    := @BtnNav1Click;

  BtnNav2 := TButton.Create(Self);
  BtnNav2.Parent   := PanelNav;
  BtnNav2.Caption  := '☰  Seite 2';
  BtnNav2.SetBounds((ClientWidth div 2) + 4, 8, 110, 32);
  BtnNav2.Font.Color := clWhite;
  BtnNav2.Font.Style := [fsBold];
  BtnNav2.Color      := $00555555;   // dunkelgrau = inaktiv
  BtnNav2.OnClick    := @BtnNav2Click;

  // ── Seite 2 (Platzhalter) ────────────────────────────────────
  PanelPage2               := TPanel.Create(Self);
  PanelPage2.Parent        := Self;
  PanelPage2.BevelOuter    := bvNone;
  PanelPage2.Color         := $00D5E8C8;   // helles Grün
  PanelPage2.DoubleBuffered := True;
  PanelPage2.Anchors       := [akLeft, akTop, akRight, akBottom];
  PanelPage2.SetBounds(0, PanelTop.Top + PanelTop.Height + 4,
                       ClientWidth,
                       ClientHeight - PanelTop.Top - PanelTop.Height - 4 - NAV_H);
  PanelPage2.Visible := False;

  // Label "Seite 2"
  with TLabel.Create(Self) do
  begin
    Parent     := PanelPage2;
    Caption    := 'Hier Seite 2';
    Font.Size  := 24;
    Font.Style := [fsBold];
    Font.Color := $00336633;
    Anchors    := [akLeft, akTop];
    Left       := 300;
    Top        := 180;
  end;

  SetConnected(False);
  ArrangeLayout;
  Log('Bereit – Verbinden klicken.');
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  PanelTop.Width      := ClientWidth - 16;
  BtnConnect.Left     := PanelTop.Width - 120;
  PanelConnState.Left := PanelTop.Width - 280;
  // Navigationsleiste immer unten über volle Breite
  PanelNav.SetBounds(0, ClientHeight - NAV_H, ClientWidth, NAV_H);
  BtnNav1.Left := (ClientWidth div 2) - 116;
  BtnNav2.Left := (ClientWidth div 2) + 4;
  // Seite 2 füllt den Bereich zwischen Header und NavBar
  PanelPage2.SetBounds(0, PanelTop.Top + PanelTop.Height + 4,
                       ClientWidth,
                       ClientHeight - PanelTop.Top - PanelTop.Height - 4 - NAV_H);
  ArrangeLayout;
end;

procedure TForm1.ShowPage(APage: Integer);
var MidX: Integer;
begin
  MidX := ClientWidth div 2;
  case APage of
    1: begin
         ScrollBox.Visible   := True;
         PanelPage2.Visible  := False;
         // Aktiv: gelb, fett, höher (oben bündig mit NavBar → visueller Tab-Effekt)
         BtnNav1.Color       := $00E8C87E;
         BtnNav1.Font.Color  := clBlack;
         BtnNav1.Font.Style  := [fsBold];
         BtnNav1.SetBounds(MidX - 116, 4, 110, 40);  // höher = aktiv
         // Inaktiv: dunkel, normal
         BtnNav2.Color       := $00555555;
         BtnNav2.Font.Color  := clSilver;
         BtnNav2.Font.Style  := [];
         BtnNav2.SetBounds(MidX + 4, 8, 110, 32);    // normal
       end;
    2: begin
         ScrollBox.Visible   := False;
         PanelPage2.Visible  := True;
         BtnNav1.Color       := $00555555;
         BtnNav1.Font.Color  := clSilver;
         BtnNav1.Font.Style  := [];
         BtnNav1.SetBounds(MidX - 116, 8, 110, 32);
         BtnNav2.Color       := $00E8C87E;
         BtnNav2.Font.Color  := clBlack;
         BtnNav2.Font.Style  := [fsBold];
         BtnNav2.SetBounds(MidX + 4, 4, 110, 40);
       end;
  end;
end;

procedure TForm1.BtnNav1Click(Sender: TObject);
begin
  ShowPage(1);
end;

procedure TForm1.BtnNav2Click(Sender: TObject);
begin
  ShowPage(2);
end;

procedure TForm1.PaintCardPanel(Sender: TObject);
var
  P : TPanel;
  C : TCanvas;
  W, H, I: Integer;
  ShadowAlpha: Byte;
begin
  P := Sender as TPanel;
  C := P.Canvas;
  W := P.ClientWidth;
  H := P.ClientHeight;

  // NUR Randpixel zeichnen - Kinder bleiben unberührt!
  // Kein FillRect, kein PaintTo → TrackBar bleibt sichtbar

  // ── Schatten: rechts + unten, 5 Schichten ──────────────────
  for I := 0 to 4 do
  begin
    ShadowAlpha := 160 + I * 18;  // 160, 178, 196, 214, 232
    C.Pen.Color := RGBToColor(ShadowAlpha, ShadowAlpha, ShadowAlpha);
    C.Pen.Width := 1;
    // rechte Kante
    C.MoveTo(W - 1 - I, I);
    C.LineTo(W - 1 - I, H - I);
    // untere Kante
    C.MoveTo(I, H - 1 - I);
    C.LineTo(W - I, H - 1 - I);
  end;

  // ── Lichtreflex oben + links ───────────────────────────────
  C.Pen.Width := 2;
  C.Pen.Color := clWhite;
  C.MoveTo(1, 1); C.LineTo(W - 6, 1);   // oben
  C.MoveTo(1, 1); C.LineTo(1, H - 6);   // links

  // ── Äußerer Rahmen ─────────────────────────────────────────
  C.Brush.Style := bsClear;
  C.Pen.Color   := $00C0C0C0;
  C.Pen.Width   := 1;
  C.Rectangle(0, 0, W, H);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  TimerPoll.Enabled := False;
  TimerPing.Enabled := False;
  if MQTT <> nil then begin MQTT.Disconnect; FreeAndNil(MQTT); end;
end;

// ── Verbindung ────────────────────────────────────────────────

procedure TForm1.SetConnected(AOn: Boolean);
begin
  BtnConnect.Caption   := IfThen(AOn, 'Trennen', 'Verbinden');
  BtnShellyEin.Enabled := AOn;
  BtnShellyAus.Enabled := AOn;
  BtnESPEin.Enabled    := AOn;
  BtnESPAus.Enabled    := AOn;
  if AOn then
  begin
    LabelConnState.Caption    := '● Verbunden';
    PanelConnState.Color      := $0090EE90;
    LabelConnState.Font.Color := $00005500;
  end
  else
  begin
    LabelConnState.Caption    := '○ Getrennt';
    PanelConnState.Color      := $00FFC0C0;
    LabelConnState.Font.Color := clMaroon;
    LabelWattV.Caption   := '-- W';
    LabelVoltV.Caption   := '-- V';
    LabelAmpV.Caption    := '-- A';
    LabelSTempV.Caption  := '-- °C';
    LabelESPTempV.Caption  := '-- °C';
    LabelESPHumV.Caption   := '-- %';
    LabelESPState.Caption  := '--';
    PanelESPState.Color    := clSilver;
    if FileExists(ExtractFilePath(ParamStr(0)) + 'lampauskl.png') then
      ImgLamp.Picture.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'lampauskl.png');
    LabelShellyState.Caption := '--';
    PanelShellyState.Color   := clSilver;
    LabelShellyTS.Caption    := '';
    LabelESPTS.Caption       := '';
  end;
end;

procedure TForm1.SetShellyRelay(AOn: Boolean);
begin
  if AOn then
  begin
    LabelShellyState.Caption    := 'EIN';
    PanelShellyState.Color      := $0090EE90;
    LabelShellyState.Font.Color := clGreen;
    BtnShellyEin.Enabled := False;
    BtnShellyAus.Enabled := True;
  end
  else
  begin
    LabelShellyState.Caption    := 'AUS';
    PanelShellyState.Color      := $00FFC0C0;
    LabelShellyState.Font.Color := clMaroon;
    BtnShellyEin.Enabled := True;
    BtnShellyAus.Enabled := False;
  end;
end;

// ── MQTT Nachrichten ──────────────────────────────────────────

procedure TForm1.HandleShelly(const APayload: string);
var P: Integer; SJ: string;
begin
  SetShellyRelay(JsonBool(APayload, 'output'));
  LabelWattV.Caption  := FormatFloat('0.0 W',   JsonFloat(APayload, 'apower'));
  LabelVoltV.Caption  := FormatFloat('0.0 V',   JsonFloat(APayload, 'voltage'));
  LabelAmpV.Caption   := FormatFloat('0.000 A', JsonFloat(APayload, 'current'));
  P := Pos('"temperature"', APayload);
  if P > 0 then
  begin
    SJ := Copy(APayload, P, 40);
    LabelSTempV.Caption := FormatFloat('0.0 °C', JsonFloat(SJ, 'tC'));
  end;
  LabelShellyTS.Caption := 'Update: ' + FormatDateTime('hh:nn:ss', Now);
end;

procedure TForm1.TrackBarRolloChange(Sender: TObject);
begin
  Rollo.Position       := TrackBarRollo.Position;
  LabelRolloPos.Caption := 'Position: ' + IntToStr(TrackBarRollo.Position) + ' %';
end;

procedure TForm1.HandleESP(const ATopic, APayload: string);
begin
  if ATopic = ESP_TOPIC + '/temperatur'  then LabelESPTempV.Caption := APayload + ' °C';
  if ATopic = ESP_TOPIC + '/luftfeuchte' then LabelESPHumV.Caption  := APayload + ' %';

  // LED-Status von ESP32 empfangen
  if ATopic = ESP_TOPIC + '/led' then
  begin
    if APayload = 'ON' then
    begin
      LabelESPState.Caption    := 'EIN';
      PanelESPState.Color      := $0090EE90;
      LabelESPState.Font.Color := clGreen;
      BtnESPEin.Enabled := False;
      BtnESPAus.Enabled := True;
      if FileExists(ExtractFilePath(ParamStr(0)) + 'lampeinkl.png') then
        ImgLamp.Picture.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'lampeinkl.png');
    end
    else
    begin
      LabelESPState.Caption    := 'AUS';
      PanelESPState.Color      := $00FFC0C0;
      LabelESPState.Font.Color := clMaroon;
      BtnESPEin.Enabled := True;
      BtnESPAus.Enabled := False;
      if FileExists(ExtractFilePath(ParamStr(0)) + 'lampauskl.png') then
        ImgLamp.Picture.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'lampauskl.png');
    end;
  end;

  // Online-Status
  if ATopic = ESP_TOPIC + '/status' then
    LabelESPState.Caption := IfThen(APayload = 'online', 'online', 'offline');

  LabelESPTS.Caption := 'Update: ' + FormatDateTime('hh:nn:ss', Now);
end;

procedure TForm1.HandleMessage(const ATopic, APayload: string);
var P: Integer; SJ: string;
begin
  if ATopic = SHELLY_ID + '/status/switch:0' then
    HandleShelly(APayload);

  if ATopic = SHELLY_ID + '/events/rpc' then
    if Pos('NotifyStatus', APayload) > 0 then
    begin
      P := Pos('switch:0', APayload);
      if P > 0 then
      begin
        SJ := Copy(APayload, P, 100);
        SetShellyRelay(JsonBool(SJ, 'output'));
        LabelWattV.Caption    := FormatFloat('0.0 W', JsonFloat(SJ, 'apower'));
        LabelShellyTS.Caption := 'Update: ' + FormatDateTime('hh:nn:ss', Now);
      end;
    end;

  if Pos(ESP_TOPIC, ATopic) = 1 then HandleESP(ATopic, APayload);
end;

// ── Verbindung ────────────────────────────────────────────────

procedure TForm1.BtnConnectClick(Sender: TObject);
begin
  if MQTT <> nil then
  begin
    TimerPoll.Enabled := False;
    TimerPing.Enabled := False;
    MQTT.Disconnect; FreeAndNil(MQTT);
    SetConnected(False);
    Log('Getrennt.');
    Exit;
  end;
  Log('Verbinde zu HiveMQ Cloud...');
  Application.ProcessMessages;
  MQTT := TMQTTSynapse.Create;
  if MQTT.Connect(HIVEMQ_HOST, HIVEMQ_PORT, HIVEMQ_USER, HIVEMQ_PASS) then
  begin
    Log('Verbunden!');
    MQTT.Subscribe(SHELLY_ID + '/status/switch:0');
    MQTT.Subscribe(SHELLY_ID + '/events/rpc');
    MQTT.Subscribe(ESP_TOPIC + '/temperatur');
    MQTT.Subscribe(ESP_TOPIC + '/luftfeuchte');
    MQTT.Subscribe(ESP_TOPIC + '/led');
    MQTT.Subscribe(ESP_TOPIC + '/status');
    SetConnected(True);
    TimerPoll.Enabled := True;
    TimerPing.Enabled := True;
    Log('Abonniert: Shelly 1PM + H&T + ESP32');
  end
  else
  begin
    Log('Fehler: ' + MQTT.GetConnackDesc);
    FreeAndNil(MQTT);
  end;
end;

// ── Buttons ───────────────────────────────────────────────────

procedure TForm1.BtnShellyEinClick(Sender: TObject);
begin
  if MQTT = nil then Exit;
  MQTT.Publish(SHELLY_ID + '/rpc',
    '{"id":1,"src":"lazarus","method":"Switch.Set","params":{"id":0,"on":true}}');
  Log('→ Shelly: EIN');
end;

procedure TForm1.BtnShellyAusClick(Sender: TObject);
begin
  if MQTT = nil then Exit;
  MQTT.Publish(SHELLY_ID + '/rpc',
    '{"id":1,"src":"lazarus","method":"Switch.Set","params":{"id":0,"on":false}}');
  Log('→ Shelly: AUS');
end;

procedure TForm1.BtnESPEinClick(Sender: TObject);
begin
  if MQTT = nil then Exit;
  MQTT.Publish('esp32/befehl', 'ON');
  Log('→ ESP32: EIN');
end;

procedure TForm1.BtnESPAusClick(Sender: TObject);
begin
  if MQTT = nil then Exit;
  MQTT.Publish('esp32/befehl', 'OFF');
  Log('→ ESP32: AUS');
end;

procedure TForm1.BtnClearLogClick(Sender: TObject);
begin
  MemoLog.Clear;
end;

// ── Timer ─────────────────────────────────────────────────────

procedure TForm1.TimerPollTimer(Sender: TObject);
var T, P: string;
begin
  T := ''; P := '';
  if MQTT = nil then Exit;
  if not MQTT.Connected then
  begin
    Log('Verbindung verloren!');
    TimerPoll.Enabled := False;
    TimerPing.Enabled := False;
    FreeAndNil(MQTT);
    SetConnected(False);
    Exit;
  end;
  while MQTT.ReceiveMessage(T, P) do
  begin
    Log('[' + T + '] ' + Copy(P, 1, 60) + '...');
    HandleMessage(T, P);
  end;
end;

procedure TForm1.TimerPingTimer(Sender: TObject);
begin
  if (MQTT <> nil) and MQTT.Connected then
    MQTT.Publish('lazarus/ping', 'alive');
end;

procedure TForm1.Log(const AMsg: string);
begin
  MemoLog.Lines.Add('[' + FormatDateTime('hh:nn:ss', Now) + '] ' + AMsg);
  MemoLog.SelStart := Length(MemoLog.Text);
end;

end.
