# Speaks every job in a jobs.tsv (voice <TAB> rate <TAB> out.wav <TAB> ssml) with Windows SAPI.
# Output: 16 kHz mono 16-bit WAV per job. Usage: powershell.exe -File synth.ps1 C:\path\jobs.tsv
param([string]$Jobs)
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$n = 0
foreach ($row in [System.IO.File]::ReadAllLines($Jobs, [System.Text.Encoding]::UTF8)) {
    if ($row.Trim().Length -eq 0) { continue }
    $p = $row.Split("`t", 4)
    $s.SelectVoice($p[0])
    $s.Rate = [int]$p[1]
    $s.SetOutputToWaveFile($p[2], $fmt)
    $s.SpeakSsml($p[3])
    $s.SetOutputToNull()
    $n++
}
$s.Dispose()
Write-Output "spoke $n lines"
