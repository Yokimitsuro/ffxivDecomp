param(
  [string]$InputDir = "lua/bytecode",
  [string]$OutputDir = "lua/decompiled",
  [string]$UnluacJar = "tools/local/unluac.jar"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $UnluacJar)) {
  throw "unluac.jar not found: $UnluacJar"
}

if (-not (Test-Path $InputDir)) {
  throw "Input directory not found: $InputDir"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$patterns = @("*.luac", "*.lub")
foreach ($pattern in $patterns) {
  Get-ChildItem -Path $InputDir -Recurse -Filter $pattern | ForEach-Object {
    $relative = Resolve-Path -Relative $_.FullName
    $relative = $relative.Substring((Resolve-Path -Relative $InputDir).Length).TrimStart('\', '/')
    $outPath = Join-Path $OutputDir ($relative -replace '\\.(luac|lub)$', '.lua')
    New-Item -ItemType Directory -Force -Path (Split-Path $outPath -Parent) | Out-Null
    Write-Host "Decompiling $($_.FullName) -> $outPath"
    & java -jar $UnluacJar $_.FullName | Set-Content -Encoding UTF8 $outPath
  }
}
