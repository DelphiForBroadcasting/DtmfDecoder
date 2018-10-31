program Project1;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Diagnostics,
  audio.wave.reader in '..\..\Include\wavefile-delphi\Source\audio.wave.reader.pas',
  DtmfDecoder in '..\..\Source\DtmfDecoder.pas';

var
  i                       : integer;
  lWaveFile               : TWaveReader;
  lSourceFile             : string;
  lDtmfDecoder            : TDtmfDecoder<SmallInt>;
  lBuffer                 : TArray<Byte>;
  lNumberOfSamples        : Cardinal;
  lAnalyzeBuffer          : TArray<SmallInt>;
  lDtmfTones              : TArray<Char>;
  lDtmfKey                : Char;
begin
  try
    ReportMemoryLeaksOnShutdown := true;

    if not FindCmdLineSwitch('i', lSourceFile, True) then
    begin
      writeln(format('Usage: %s -i [WAV FILE]', [System.IOUtils.TPath.GetFileName(ParamStr(0))]));
      exit;
    end;
    lSourceFile := TPath.GetFullPath(TPath.Combine(System.IOUtils.TPath.GetDirectoryName(ParamStr(0)), lSourceFile));

    lWaveFile := TWaveReader.Create(lSourceFile);
    try
      WriteLn(Format('* Read %s: ', [lSourceFile]));
      WriteLn(Format('   Data size: %d', [lWaveFile.DataChunk.Size div lWaveFile.DataChunk.NumberOfChannel]));
      WriteLn(Format('   Channels count: %d', [lWaveFile.DataChunk.NumberOfChannel]));
      WriteLn(Format('   BitsPerSample: %d', [lWaveFile.FMTChunk.BitsPerSample]));

      // copy to temporary buffer
      SetLength(lBuffer, lWaveFile.DataChunk.Size div lWaveFile.DataChunk.NumberOfChannel);
      Move(lWaveFile.DataChunk.ChannelData[0]^, lBuffer[0], lWaveFile.DataChunk.Size div lWaveFile.DataChunk.NumberOfChannel);

      lNumberOfSamples := lWaveFile.DataChunk.Size div lWaveFile.DataChunk.NumberOfChannel div (lWaveFile.FMTChunk.BitsPerSample div 8);
      SetLength(lAnalyzeBuffer, lNumberOfSamples);
       for i := 0 to lNumberOfSamples - 1 do
        lAnalyzeBuffer[i] := PSmallInt(@lBuffer[(I*2)])^;


      // method 1
      lDtmfTones := TDtmfDecoder<SmallInt>.DetectDTMF(lAnalyzeBuffer, lWaveFile.FMTChunk.SampleRate);
      for lDtmfKey in lDtmfTones do
        WriteLn(Format('DTMF KEY: %s', [lDtmfKey]));

      //method 2
      lDtmfDecoder := TDtmfDecoder<SmallInt>.Create(lWaveFile.FMTChunk.SampleRate);
      try
        lDtmfDecoder.Thresold := 33.0;
        lDtmfDecoder.OnDtmfCode := procedure(Sender: TObject; DtmfCode: Char; Duration: Integer)
        begin
          WriteLn(Format('DTMF KEY: %s, Duration: %d', [DtmfCode, Duration]));
        end;
        lDtmfDecoder.Analyze(lAnalyzeBuffer, 0, Length(lAnalyzeBuffer));
      finally
        FreeAndNil(lDtmfDecoder);
      end;

    finally
      FreeAndNil(lWaveFile);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

  WriteLn;
  Write('Press Enter to exit...');
  Readln;
end.
