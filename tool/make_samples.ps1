#requires -Version 5.1
# Genera en samples/ (ignorada por git) los medios de prueba del reproductor:
#   sample.mkv   ~30 s, video de prueba, audio AC3 (spa) y DTS (eng), subtítulos ASS con estilos
#   external.srt subtítulo externo para cargar por URL
# Hace falta ffmpeg en el PATH. Se ejecuta desde cualquier carpeta.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$samples = Join-Path $root 'samples'
New-Item -ItemType Directory -Force -Path $samples | Out-Null

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error 'No se encontro ffmpeg en el PATH.'
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$seconds = 30

# --- Subtítulos ASS con estilos: color, posición y alineación ---------------
# Colores en formato &HAABBGGRR. Arriba: amarillo, alineación 8. Rojo: \pos fija.
$ass = New-Object System.Collections.Generic.List[string]
$ass.Add('[Script Info]')
$ass.Add('ScriptType: v4.00+')
$ass.Add('PlayResX: 1280')
$ass.Add('PlayResY: 720')
$ass.Add('')
$ass.Add('[V4+ Styles]')
$ass.Add('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding')
$ass.Add('Style: Default,Arial,44,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,20,20,40,1')
$ass.Add('Style: Arriba,Arial,48,&H0000FFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,8,20,20,40,1')
$ass.Add('Style: Rojo,Arial,52,&H000000FF,&H000000FF,&H00FFFFFF,&H80000000,-1,-1,0,0,100,100,0,0,1,3,0,5,20,20,20,1')
$ass.Add('')
$ass.Add('[Events]')
$ass.Add('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text')
for ($t = 0; $t -lt ($seconds - 2); $t += 6) {
    $a = [TimeSpan]::FromSeconds($t + 1).ToString('h\:mm\:ss') + '.00'
    $b = [TimeSpan]::FromSeconds($t + 4).ToString('h\:mm\:ss') + '.00'
    $c = [TimeSpan]::FromSeconds($t + 4).ToString('h\:mm\:ss') + '.00'
    $d = [TimeSpan]::FromSeconds($t + 7).ToString('h\:mm\:ss') + '.00'
    $ass.Add("Dialogue: 0,$a,$b,Default,,0,0,0,,ASS abajo (estilo Default) - t=$t s")
    $ass.Add("Dialogue: 0,$a,$b,Arriba,,0,0,0,,ASS arriba en amarillo (estilo Arriba)")
    $ass.Add("Dialogue: 1,$c,$d,Rojo,,0,0,0,,{\pos(900,200)}ASS rojo en cursiva y posicion fija")
}
$assPath = Join-Path $samples 'estilos.ass'
[System.IO.File]::WriteAllText($assPath, ($ass -join "`n") + "`n", $utf8NoBom)

# --- Subtítulo externo .srt --------------------------------------------------
$srt = New-Object System.Collections.Generic.List[string]
$n = 1
for ($t = 0; $t -lt ($seconds - 2); $t += 5) {
    $a = [TimeSpan]::FromSeconds($t + 1).ToString('hh\:mm\:ss') + ',000'
    $b = [TimeSpan]::FromSeconds($t + 4).ToString('hh\:mm\:ss') + ',000'
    $srt.Add("$n")
    $srt.Add("$a --> $b")
    $srt.Add("SRT externo numero $n")
    $srt.Add('')
    $n++
}
$srtPath = Join-Path $samples 'external.srt'
[System.IO.File]::WriteAllText($srtPath, ($srt -join "`n") + "`n", $utf8NoBom)

# --- MKV: video de prueba + AC3 + DTS + ASS ----------------------------------
$out = Join-Path $samples 'sample.mkv'
& ffmpeg -y -hide_banner -loglevel warning `
    -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=$seconds" `
    -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=$seconds" `
    -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=$seconds" `
    -i $assPath `
    -map 0:v -map 1:a -map 2:a -map 3:s `
    -c:v libx264 -preset veryfast -pix_fmt yuv420p `
    -c:a:0 ac3 -b:a:0 192k -c:a:1 dca -strict -2 -b:a:1 768k `
    -c:s ass `
    -metadata:s:a:0 language=spa -metadata:s:a:0 'title=Castellano AC3 (tono grave)' `
    -metadata:s:a:1 language=eng -metadata:s:a:1 'title=Original DTS (tono agudo)' `
    -metadata:s:s:0 language=spa -metadata:s:s:0 'title=ASS con estilos' `
    -disposition:a:0 default -disposition:a:1 0 `
    $out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Listo: $out"
Write-Host "Listo: $srtPath"
Write-Host 'Para servirlos por HTTP: python -m http.server 8000 --directory samples'
