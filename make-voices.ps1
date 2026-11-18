# Bangla Speak - records every phrase with Azure's Bangladeshi neural voices.
# Run it by double-clicking make-voices.bat. Safe to stop and restart: finished clips are skipped.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-Location $PSScriptRoot

$region = 'eastus'
$uri = "https://$region.tts.speech.microsoft.com/cognitiveservices/v1"
$voices = @{
  'f'  = @('bn-BD-NabanitaNeural', '');
  'f2' = @('bn-BD-NabanitaNeural', '+10%');
  'm'  = @('bn-BD-PradeepNeural',  '');
  'm2' = @('bn-BD-PradeepNeural',  '-10%')
}

Write-Host ''
Write-Host '  Bangla Speak voice recorder' -ForegroundColor Green
Write-Host '  Uses your FREE (F0) Azure Speech resource. Nothing is charged.'
Write-Host ''
$key = (Read-Host '  Paste your Azure Speech key and press Enter').Trim()
if (-not $key) { Write-Host '  No key entered.'; exit 1 }

$lines = Get-Content -Raw -Encoding UTF8 'voice-list.json' | ConvertFrom-Json
New-Item -ItemType Directory -Force 'audio' | Out-Null
$headers = @{
  'Ocp-Apim-Subscription-Key' = $key
  'X-Microsoft-OutputFormat'  = 'audio-24khz-48kbitrate-mono-mp3'
  'User-Agent'                = 'BanglaSpeak'
}

function Write-Manifest {
  $ids = Get-ChildItem 'audio' -Filter '*.mp3' | Where-Object { $_.Length -gt 1000 } | ForEach-Object { '"' + $_.BaseName + '"' }
  $js = 'window.BS_CLIPS=[' + ($ids -join ',') + '];'
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'audio\manifest.js'), $js, (New-Object Text.UTF8Encoding($false)))
}

$total = $lines.Count
$todo = @($lines | Where-Object { -not ((Test-Path "audio\$($_.id).mp3") -and ((Get-Item "audio\$($_.id).mp3").Length -gt 1000)) })
Write-Host ''
Write-Host "  $($total - $todo.Count) of $total clips already done. Recording the remaining $($todo.Count)."
Write-Host '  The free tier allows about 20 clips a minute, so this takes a while.'
Write-Host '  Keep the computer awake. You can close this window and restart any time.'
Write-Host ''

$n = 0; $failed = 0
foreach ($l in $todo) {
  $n++
  $out = Join-Path $PSScriptRoot "audio\$($l.id).mp3"
  $v = $voices[$l.v]
  $text = [Security.SecurityElement]::Escape($l.text)
  if ($v[1]) { $text = "<prosody pitch='$($v[1])'>$text</prosody>" }
  $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='bn-BD'><voice name='$($v[0])'>$text</voice></speak>"
  $body = [Text.Encoding]::UTF8.GetBytes($ssml)
  $tries = 0; $ok = $false
  while (-not $ok -and $tries -lt 6) {
    $tries++
    try {
      Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -ContentType 'application/ssml+xml' -Body $body -OutFile $out -UseBasicParsing
      if ((Get-Item $out).Length -gt 1000) { $ok = $true } else { throw 'empty audio' }
    } catch {
      if (Test-Path $out) { Remove-Item $out -Force }
      $code = $null
      try { $code = [int]$_.Exception.Response.StatusCode } catch {}
      if ($code -eq 401 -or $code -eq 403) {
        Write-Host ''
        Write-Host '  Azure rejected the key. Check that you copied KEY 1 and that the region is East US.' -ForegroundColor Red
        Read-Host '  Press Enter to close'; exit 1
      }
      Write-Host "  Azure is busy (code $code). Waiting a minute, then retrying..." -ForegroundColor Yellow
      Start-Sleep -Seconds 60
    }
  }
  if (-not $ok) { $failed++ }
  $left = [math]::Ceiling(($todo.Count - $n) * 3.2 / 60)
  Write-Host ("  [{0}/{1}] about {2} min left" -f $n, $todo.Count, $left)
  if ($n % 20 -eq 0) { Write-Manifest }
  Start-Sleep -Milliseconds 3100
}
Write-Manifest
Write-Host ''
if ($failed) {
  Write-Host "  Finished, but $failed clips failed. Run make-voices.bat again to retry just those." -ForegroundColor Yellow
} else {
  Write-Host '  All done! Every phrase now has a recorded voice.' -ForegroundColor Green
  Write-Host '  You can now regenerate your Azure key (Keys and Endpoint > Regenerate Key 1).'
}
Read-Host '  Press Enter to close'
