unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, mqtt_synapse, ssl_openssl_lib;

type

  { TForm1 }

  TForm1 = class(TForm)
    BtnConnect: TButton;
    BtnOn: TButton;
    BtnOff: TButton;
    LabelSensor: TLabel;
    MemoLog: TMemo;
    TimerPoll: TTimer;
    procedure BtnConnectClick(Sender: TObject);
    procedure BtnOffClick(Sender: TObject);
    procedure BtnOnClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure TimerPollTimer(Sender: TObject);
  private
    MQTT: TMQTTSynapse;
    procedure Log(const AMsg: string);
  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

procedure TForm1.Log(const AMsg: string);
begin
  MemoLog.Lines.Add('[' + FormatDateTime('hh:nn:ss', Now) + '] ' + AMsg);
end;

procedure TForm1.BtnConnectClick(Sender: TObject);
begin
  // Altes Objekt freigeben falls vorhanden
  if MQTT <> nil then
  begin
    TimerPoll.Enabled := False;
    MQTT.Free;
    MQTT := nil;
    BtnConnect.Caption := 'Verbinden';
    BtnConnect.Enabled := True;
    BtnOn.Enabled  := False;
    BtnOff.Enabled := False;
    Log('Getrennt.');
    Exit;
  end;

  MQTT := TMQTTSynapse.Create;
  Log('Verbinde zu HiveMQ Cloud (Port 8883, TLS)...');
  Log('OpenSSL geladen: ' + BoolToStr(IsSSLloaded, True));
  Application.ProcessMessages;  // UI aktualisieren

  if MQTT.Connect(
    '85484da2efb94762bdf2d25a3c8df9a0.s1.eu.hivemq.cloud',
    '8883',
    'lazarususer',
    'Laz12345'
  ) then
  begin
    Log('✓ Verbunden! CONNACK erhalten.');
    MQTT.Subscribe('esp32/sensor');
    Log('Abonniert: esp32/sensor');

    TimerPoll.Enabled  := True;
    BtnConnect.Caption := 'Trennen';
    BtnOn.Enabled      := True;
    BtnOff.Enabled     := True;
  end
  else
  begin
    Log('*** FEHLER: Verbindung fehlgeschlagen! ***');
    Log('  OpenSSL geladen : ' + BoolToStr(IsSSLloaded, True));
    Log('  Socket-Code     : ' + IntToStr(MQTT.GetLastError));
    Log('  Socket-Meldung  : ' + MQTT.GetLastErrorDesc);
    Log('  CONNACK-Code    : ' + IntToStr(MQTT.GetConnackCode));
    Log('  CONNACK-Info    : ' + MQTT.GetConnackDesc);
    Log('---');
    case MQTT.GetLastError of
      0:    Log('  >> TCP+TLS OK aber MQTT abgelehnt -> EMQX Authentication pruefen!');
      10060: Log('  >> TIMEOUT -> Firewall oder falsche IP-Adresse');
      10061: Log('  >> PORT VERWEIGERT -> Port 8883 nicht erreichbar');
      10054: Log('  >> VERBINDUNG ABGEBROCHEN -> TLS-Fehler, DLL-Version pruefen');
    else
      Log('  >> Unbekannter Fehler');
    end;
    MQTT.Free;
    MQTT := nil;
  end;
end;

procedure TForm1.BtnOffClick(Sender: TObject);
begin
  if MQTT <> nil then
  begin
    MQTT.Publish('esp32/befehl', 'OFF');
    Log('→ Gesendet: esp32/befehl = OFF');
  end;
end;

procedure TForm1.BtnOnClick(Sender: TObject);
begin
  if MQTT <> nil then
  begin
    MQTT.Publish('esp32/befehl', 'ON');
    Log('→ Gesendet: esp32/befehl = ON');
  end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  TimerPoll.Enabled := False;
  if MQTT <> nil then
  begin
    MQTT.Disconnect;
    MQTT.Free;
  end;
end;

procedure TForm1.TimerPollTimer(Sender: TObject);
var
  Topic, Payload: string;
begin
  if MQTT = nil then Exit;

  // Verbindung prüfen
  if not MQTT.Connected then
  begin
    Log('✗ Verbindung verloren!');
    TimerPoll.Enabled  := False;
    BtnConnect.Caption := 'Verbinden';
    BtnOn.Enabled      := False;
    BtnOff.Enabled     := False;
    FreeAndNil(MQTT);
    Exit;
  end;

  // Nachrichten empfangen
  if MQTT.ReceiveMessage(Topic, Payload) then
  begin
    Log('← [' + Topic + '] ' + Payload);
    if Topic = 'esp32/sensor' then
      LabelSensor.Caption := 'Sensorwert: ' + Payload;
  end;
end;

end.
