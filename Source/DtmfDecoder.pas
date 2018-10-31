unit DtmfDecoder;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.Generics.Collections,
  System.Math;

type
  TDtmfToneTable = class(TDictionary<TPair<Double,Double>, Char>)
  public const
    kLowFreqs   : array[0..3] of Double =  (697, 770, 852, 941);
    kHighFreqs  : array[0..3] of Double =  (1209, 1336,1477,1633);
    kDtmfCodes  : array[0..3] of array[0..3] of Char = (('1','2','3','A'), ('4','5','6','B'), ('7','8','9','C'), ('*','0','#','D'));
  public
    constructor Create();  overload;
    procedure Init();
    function Get(LowFreq: Double; HighFreq: Double): Char;
  end;

  TWindowFunction = (
    Blackman,
    BlackmanNuttall,
    BlackmanHarris,
    Hamming,
    FlatTop
  );

  TWindowFunctionTable = record
  private
    FType     : TWindowFunction;
    FTable    : TArray<Double>;
  public
    constructor Create(AWindowFunction: TWindowFunction; ANumberOfSamples: Longint);
    property _Type: TWindowFunction read FType;
    property Table: TArray<Double> read FTable;
  end;

  TDtmfDecoder<T> = class
  type
    TOnDtmfCode = reference to procedure(Sender: TObject; DtmfCode: Char; Duration: Integer);
  private
    FBitsPerSample              : Integer;
    FSampleRate                 : Double;
    FSamplesPerMilliseconds     : Integer;

    FWindowFrames               : TArray<SmallInt>;
    FWindowFunctionTable        : TWindowFunctionTable;

    FLastDtmfTone               : Char;
    FToneSamples                : Integer;

    FTimestamp                  : Int64;

    FOverlapFramesCount         : Integer;
    FWindowOverlapMilliseconds  : Integer;
    FWindowDurationMilliseconds : Integer;
    FNumberOfSamples            : Integer;

    FThresold                   : Double;
    FMinToneSamples             : Integer;
    FDtmfToneTable              : TDtmfToneTable;

    FOnDtmfCode                 : TOnDtmfCode;

    function goertzelFunction(aFreq: Double; aSampleRate: Double; const aSamples: TArray<Double>; aNumberOfSamples: Longint): Double;
    function getExistsFrequency(const aSamples: TArray<Double>; aNumberOfSamples: Longint; aSampleRate: Double; const aFreqs: array of Double; AThresold : Double = -59.0): Double;

    // property WindowFunction
    procedure SetWindowFunction(AWindowFunction: TWindowFunction);
    function GetWindowFunction(): TWindowFunction;

  public
    constructor Create(ASampleRate: Cardinal);  overload;
    destructor Destroy; override;
    class function DetectDTMF(const AData: TArray<T>; ASampleRate: Cardinal): TArray<Char>;

    function Analyze(ASamples: TArray<T>; AOffset: Integer; ANumberOfSamples: Longint): TArray<Char>; overload;

    property  OnDtmfCode: TOnDtmfCode read FOnDtmfCode write FOnDtmfCode;
    property WindowFunction: TWindowFunction read GetWindowFunction write SetWindowFunction;
    property Thresold: Double read FThresold write FThresold;

  end;


implementation

//
constructor TWindowFunctionTable.Create(AWindowFunction: TWindowFunction; ANumberOfSamples: Longint);
var
  i : Integer;
  lArcSin : Double;
begin
  if ((FType = AWindowFunction) and (Length(FTable) = ANumberOfSamples)) then
    exit;

  FType := AWindowFunction;
  SetLength(FTable, ANumberOfSamples);
  case AWindowFunction of
    Blackman:
    begin
      for i := 0 to ANumberOfSamples - 1 do
        FTable[i] := (0.42 - 0.5 * cos(2.0 * System.Pi * i / (ANumberOfSamples - 1)) + 0.08 * cos(4.0 * System.Pi * i / (ANumberOfSamples - 1))) {/ (System.Math.Power(2, FBitsPerSample * 8 - 1) - 1)};
    end;
    BlackmanNuttall:
    begin
      for i := 0 to ANumberOfSamples - 1 do
      begin
        lArcSin := 2.0 * System.Pi * i / (ANumberOfSamples - 1);
        FTable[i] := 0.3635819 - 0.4891775 * cos(lArcSin) + 0.1365995 * cos(2 * lArcSin) - 0.00106411 * cos(3 * lArcSin){ / (System.Math.Power(2, FBitsPerSample * 8 - 1) - 1)};
      end;
    end;
    BlackmanHarris:
    begin
      for i := 0 to ANumberOfSamples - 1 do
      begin
        lArcSin := 2.0 * System.Pi * i / (ANumberOfSamples - 1);
        FTable[i] := 0.35875 - 0.48829 * cos(lArcSin) + 0.14128 * cos(2 * lArcSin) - 0.01168 * cos(3 * lArcSin){ / (System.Math.Power(2, FBitsPerSample * 8 - 1) - 1)};
      end;
    end;
    Hamming:
    begin
    for i := 0 to ANumberOfSamples - 1 do
      FTable[i] := 0.53836 - 0.46164 * cos(2.0 * System.Pi * i / (ANumberOfSamples - 1)) {/ (System.Math.Power(2, FBitsPerSample * 8 - 1) - 1)};
    end;
    FlatTop:
    begin
      for i := 0 to ANumberOfSamples - 1 do
      begin
        lArcSin := 2.0 * System.Pi * i / (ANumberOfSamples - 1);
        FTable[i] := 1 - 1.93 * cos(lArcSin) + 1.29 * cos(2 * lArcSin) - 0.388 * cos(3 * lArcSin) * 0.028 * cos(4 * lArcSin){ / (System.Math.Power(2, FBitsPerSample * 8 - 1) - 1)};
      end;
    end;
  end;
end;

//
constructor TDtmfToneTable.Create();
begin
  inherited Create;
  Init();
end;

function TDtmfToneTable.Get(LowFreq: Double; HighFreq: Double): Char;
begin
  if Self.ContainsKey(TPair<Double, Double>.Create(LowFreq, HighFreq)) then
    result := Self.Items[TPair<Double, Double>.Create(LowFreq, HighFreq)]
  else result := #0;
end;

procedure TDtmfToneTable.Init();
var
  I, K : integer;
begin
  inherited Create;
  Self.Clear;
  for I := 0 to Length(kLowFreqs) - 1 do
  begin
    for K := 0 to Length(kHighFreqs) - 1 do
    begin
      Self.Add(TPair<Double, Double>.Create(kLowFreqs[i], kHighFreqs[k]),  kDtmfCodes[i][k]);
    end;
  end;
end;

//
constructor TDtmfDecoder<T>.Create(ASampleRate: Cardinal);
begin
  inherited Create;
  FThresold := 55.0;
  FTimestamp := 0;
  FToneSamples := 0;
  FBitsPerSample := SizeOf(T);
  FSampleRate := aSampleRate;
  FSamplesPerMilliseconds := Round(Self.FSampleRate / 1000);

  FWindowDurationMilliseconds := 50;
  FWindowOverlapMilliseconds := 10;
  if FWindowOverlapMilliseconds > FWindowDurationMilliseconds then
    FWindowOverlapMilliseconds := FWindowDurationMilliseconds;

  FNumberOfSamples := (FSamplesPerMilliseconds * FWindowDurationMilliseconds);
  FOverlapFramesCount := FSamplesPerMilliseconds * FWindowOverlapMilliseconds;

  // minimal tone time
  FMinToneSamples := FSamplesPerMilliseconds * 50;

  SetWindowFunction(TWindowFunction.Blackman);
  FDtmfToneTable := TDtmfToneTable.Create;

end;

destructor TDtmfDecoder<T>.Destroy;
begin
  FreeAndNil(FDtmfToneTable);
  inherited Destroy;
end;

procedure TDtmfDecoder<T>.SetWindowFunction(AWindowFunction: TWindowFunction);
begin
  Self.FWindowFunctionTable := TWindowFunctionTable.Create(AWindowFunction, Self.FNumberOfSamples);
end;

function TDtmfDecoder<T>.GetWindowFunction(): TWindowFunction;
begin
  result := Self.FWindowFunctionTable._Type;
end;

function TDtmfDecoder<T>.Analyze(ASamples: TArray<T>; AOffset: Integer; ANumberOfSamples: Longint): TArray<Char>;
var
  i                   : Integer;
  lOffset             : Integer;
  lWindowFramesOffset : Integer;
  lNumberOfSamples    : Integer;
  lLen                : Integer;
  LResultedFrames     : TArray<Double>;
  lLowFreq            : Double;
  lHighFreq           : Double;
begin
  SetLength(result, 0);
  lOffset := AOffset;
  lNumberOfSamples := ANumberOfSamples;
  while lNumberOfSamples > 0 do
  begin
    lLen := Min(ANumberOfSamples, FNumberOfSamples - Length(FWindowFrames));

    lWindowFramesOffset := Length(FWindowFrames);
    SetLength(FWindowFrames, lWindowFramesOffset + lLen);
    Move(ASamples[lOffset], FWindowFrames[lWindowFramesOffset], lLen * FBitsPerSample);

    lOffset := lOffset + lLen;
    lNumberOfSamples := lNumberOfSamples - lLen;

    if Length(FWindowFrames) >= FNumberOfSamples then
    begin
      SetLength(LResultedFrames, FNumberOfSamples);
      for I := 0 to FNumberOfSamples - 1 do
        lResultedFrames[i] := FWindowFunctionTable.Table[i] * FWindowFrames[i];

      lLowFreq := getExistsFrequency(lResultedFrames, FNumberOfSamples, FSampleRate, TDtmfToneTable.kLowFreqs, FThresold);
      lHighFreq := getExistsFrequency(lResultedFrames, FNumberOfSamples, FSampleRate, TDtmfToneTable.kHighFreqs, FThresold);

      FToneSamples := FToneSamples + FOverlapFramesCount;
      if (FDtmfToneTable.Get(lLowFreq, lHighFreq) <> FLastDtmfTone) then
      begin
        if (FLastDtmfTone <> #0) then
        begin
          if FToneSamples >= Self.FMinToneSamples then     
          begin     
            if assigned(Self.FOnDtmfCode) then
              Self.FOnDtmfCode(Self, FLastDtmfTone, Round(FToneSamples / FSamplesPerMilliseconds));
            SetLength(result, Length(result)+1);
            result[High(result)] := FLastDtmfTone;
          end;
        end;        
        FToneSamples := 0;
        FLastDtmfTone := FDtmfToneTable.Get(lLowFreq, lHighFreq);
      end;


      Delete(FWindowFrames, 0, FOverlapFramesCount);
    end;
    FTimestamp := FTimestamp + lLen;
  end;
end;

function TDtmfDecoder<T>.goertzelFunction(aFreq: Double; aSampleRate: Double; const aSamples: TArray<Double>; aNumberOfSamples: Longint): Double;
var
  i             : integer;
  lScalingFactor: Double;
  k             : Double;

  lOmega        : Double;
  lCosine       : Double;
  lSine         : Double;
  lQ0           : Double;
  lQ1           : Double;
  lQ2           : Double;
  lCoeff        : Double;
  lReal         : Double;
  lImag         : Double;
begin
  lScalingFactor := Length(aSamples) / 2;
  k := 0.5 + ((Length(aSamples) * aFreq) / aSampleRate);
  lOmega := (2.0 * System.Pi * k) / Length(aSamples);
  lSine := sin(lOmega);
  lCosine := cos(lOmega);
  lCoeff := 2.0 * lCosine;
  lQ0 := 0;
  lQ1 := 0;
  lQ2 := 0;
  for i := 0 to Length(aSamples) - 1 do
  begin
    lQ0:= lCoeff * lQ1 - lQ2 + aSamples[i];
    lQ2:= lQ1;
    lQ1:= lQ0;
  end;
  lReal := (lQ1 - lQ2 * lCosine) / lScalingFactor;
  lImag := (lQ2 * lSine) / lScalingFactor;
  result := System.sqrt(lReal*lReal + lImag*lImag);
end;


function TDtmfDecoder<T>.getExistsFrequency(const aSamples: TArray<Double>; aNumberOfSamples: Longint; aSampleRate: Double; const aFreqs: array of Double; AThresold : Double = -59.0): Double;
var
  lMax  : Double;
  lFreq : Double;
  lMag  : Double;
begin
  lMax :=  AThresold;
  result := 0;
  try
    for lFreq in aFreqs do
    begin
      lMag := 20 * log10(goertzelFunction(lFreq, aSampleRate, aSamples, aNumberOfSamples));
      if lMag > lMax then
      begin
        lMax := lMag;
        result := lFreq;
      end;
    end;
  except end;
end;

class function TDtmfDecoder<T>.DetectDTMF(const AData: TArray<T>; ASampleRate: Cardinal): TArray<Char>;
var
  lDtmfDecoder : TDtmfDecoder<T>;
  lDtmfTones   : TArray<Char>;
begin
  lDtmfDecoder := TDtmfDecoder<T>.Create(ASampleRate);
  try
    result := lDtmfDecoder.Analyze(AData, 0, Length(AData));
  finally
    FreeAndNil(lDtmfDecoder);
  end;
end;


end.
