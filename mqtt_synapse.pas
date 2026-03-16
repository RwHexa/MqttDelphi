unit mqtt_synapse;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, blcksock, synsock, ssl_openssl, ssl_openssl_lib;

type
  TMQTTSynapse = class
  private
    FSock           : TTCPBlockSocket;
    FLastConnackCode: Byte;
    function WriteString(const S: string): string;
    function EncodeLength(Len: Integer): string;
  public
    constructor Create;
    destructor Destroy; override;
    function Connect(Host, Port, User, Pass: string): Boolean;
    procedure Disconnect;
    procedure Publish(Topic, Payload: string);
    procedure Subscribe(Topic: string);
    function ReceiveMessage(var Topic, Payload: string): Boolean;
    function Connected: Boolean;
    function GetLastError: Integer;
    function GetLastErrorDesc: string;
    function GetConnackCode: Byte;
    function GetConnackDesc: string;
  end;

implementation

constructor TMQTTSynapse.Create;
begin
  FSock            := TTCPBlockSocket.Create;
  FLastConnackCode := 255;
end;

destructor TMQTTSynapse.Destroy;
begin
  if FSock.Socket <> INVALID_SOCKET then
    FSock.CloseSocket;
  FSock.Free;
  inherited;
end;

function TMQTTSynapse.GetLastError: Integer;
begin
  Result := FSock.LastError;
end;

function TMQTTSynapse.GetLastErrorDesc: string;
begin
  Result := FSock.LastErrorDesc;
end;

function TMQTTSynapse.GetConnackCode: Byte;
begin
  Result := FLastConnackCode;
end;

function TMQTTSynapse.GetConnackDesc: string;
begin
  case FLastConnackCode of
    0:   Result := 'Verbindung akzeptiert (OK)';
    1:   Result := 'Protokoll-Version abgelehnt';
    2:   Result := 'Client-ID abgelehnt';
    3:   Result := 'Server nicht verfuegbar';
    4:   Result := 'Falscher Benutzername oder Passwort!';
    5:   Result := 'Nicht autorisiert (ACL fehlt)';
    255: Result := 'Kein CONNACK empfangen (Timeout oder falsches Paket)';
  else
    Result := 'Unbekannter Code: ' + IntToStr(FLastConnackCode);
  end;
end;

function TMQTTSynapse.WriteString(const S: string): string;
begin
  Result := Chr(Length(S) div 256) + Chr(Length(S) mod 256) + S;
end;

function TMQTTSynapse.EncodeLength(Len: Integer): string;
var b: Byte;
begin
  Result := '';
  repeat
    b   := Len mod 128;
    Len := Len div 128;
    if Len > 0 then b := b or 128;
    Result := Result + Chr(b);
  until Len = 0;
end;

function TMQTTSynapse.Connect(Host, Port, User, Pass: string): Boolean;
var
  Data, VarHeader, Payload: string;
begin
  Result           := False;
  FLastConnackCode := 255;

  FSock.ConnectionTimeout := 10000;

  // Schritt 1: TCP-Verbindung
  FSock.Connect(Host, Port);
  if FSock.LastError <> 0 then Exit;

  // Schritt 2: TLS-Handshake (bei Port 8883)
  if Port = '8883' then
  begin
    // Prüfen ob OpenSSL DLL überhaupt geladen ist
    if not IsSSLloaded then
    begin
      // DLL manuell laden triggern
      InitSSLInterface;
    end;

    FSock.SSL.SSLType    := LT_all;
    FSock.SSL.VerifyCert := False;
    FSock.SSL.SNIHost    := Host;   // SNI: HiveMQ Cloud benötigt Hostname für Routing!
    FSock.SSLDoConnect;
    if FSock.LastError <> 0 then Exit;
  end;

  // Schritt 3: MQTT CONNECT senden
  VarHeader := WriteString('MQTT') + #4 + #$C2 + #0 + #60;
  Payload   := WriteString('LazarusMQTT_' + IntToStr(Random(9999)))
             + WriteString(User)
             + WriteString(Pass);
  Data      := #$10
             + EncodeLength(Length(VarHeader) + Length(Payload))
             + VarHeader + Payload;

  FSock.SendString(Data);
  if FSock.LastError <> 0 then Exit;

  // Schritt 4: CONNACK lesen ($20 $02 $00 $00)
  Data := FSock.RecvBufferStr(4, 8000);
  if FSock.LastError <> 0 then Exit;

  if (Length(Data) >= 4) and (Byte(Data[1]) = $20) then
  begin
    FLastConnackCode := Byte(Data[4]);
    Result := (FLastConnackCode = $00);
  end;
end;

procedure TMQTTSynapse.Disconnect;
begin
  FSock.SendString(#$E0 + #$00);
  FSock.CloseSocket;
end;

procedure TMQTTSynapse.Publish(Topic, Payload: string);
var Data: string;
begin
  Data := #$30
        + EncodeLength(Length(WriteString(Topic)) + Length(Payload))
        + WriteString(Topic) + Payload;
  FSock.SendString(Data);
end;

procedure TMQTTSynapse.Subscribe(Topic: string);
var Data, Pl: string;
begin
  Pl   := #0#1 + WriteString(Topic) + #0;
  Data := #$82 + EncodeLength(Length(Pl)) + Pl;
  FSock.SendString(Data);
  FSock.RecvBufferStr(5, 2000);
end;

function TMQTTSynapse.ReceiveMessage(var Topic, Payload: string): Boolean;
var
  HeaderByte, b: Byte;
  RLen, TLen, Mult: Integer;
begin
  Result := False;
  if FSock.WaitingData = 0 then Exit;

  HeaderByte := FSock.RecvByte(200);
  if FSock.LastError <> 0 then Exit;

  if (HeaderByte and $F0) = $30 then
  begin
    RLen := 0; Mult := 1;
    repeat
      b    := FSock.RecvByte(200);
      RLen := RLen + (b and 127) * Mult;
      Mult := Mult * 128;
    until (b and 128) = 0;
    TLen    := FSock.RecvByte(200) * 256 + FSock.RecvByte(200);
    Topic   := FSock.RecvBufferStr(TLen, 2000);
    Payload := FSock.RecvBufferStr(RLen - TLen - 2, 2000);
    Result  := (FSock.LastError = 0) and (Topic <> '');
  end
  else
  begin
    if FSock.WaitingData > 0 then
      FSock.RecvBufferStr(FSock.WaitingData, 100);
  end;
end;

function TMQTTSynapse.Connected: Boolean;
begin
  Result := FSock.CanWrite(10);
end;

end.
