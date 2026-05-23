# Render docs/data/ffxivtool_table_catalog.md from the CSV catalog.

param(
  [string]$Root = "E:\meteor-reborn-research"
)

$ErrorActionPreference = "Stop"

$InCsv  = Join-Path $Root "docs\data\ffxivtool_table_catalog.csv"
$OutMd  = Join-Path $Root "docs\data\ffxivtool_table_catalog.md"

$rows = Import-Csv $InCsv

# Per-category counts and totals
$catGroups = $rows | Group-Object category | Sort-Object Count -Descending
$relGroups = $rows | Group-Object server_relevance | Sort-Object @{e='Name'; Descending=$false}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# FFXIVTool Table Catalog")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Auto-generated from ``data/client_exports/ffxivtool/decode_csv/*.csv``.")
[void]$sb.AppendLine("Generator: ``tools/build_ffxivtool_catalog.ps1`` + ``tools/render_ffxivtool_catalog_md.ps1``.")
[void]$sb.AppendLine("Raw data: ``docs/data/ffxivtool_table_catalog.csv`` (machine-readable).")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Total tables:** $($rows.Count)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Server-relevance distribution")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Relevance  | Files |")
[void]$sb.AppendLine("|------------|-------|")
foreach ($g in $relGroups) {
  [void]$sb.AppendLine("| $($g.Name)  | $($g.Count) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Definitions:")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- **critical** -- server must import to drive core flows (zone entry, NPC spawn, item ops, commands, quests, shops, leves, etc.).")
[void]$sb.AppendLine("- **useful** -- server can use for gameplay correctness (gear stats, text, achievements). Often referenced by IDs from critical tables.")
[void]$sb.AppendLine("- **later** -- system / boot / debug tables. Not blocking for v0.")
[void]$sb.AppendLine("- **cosmetic** -- texture/variant tables. Pure client visuals.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Category distribution")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Category | Files | Relevance |")
[void]$sb.AppendLine("|----------|-------|-----------|")
foreach ($g in $catGroups) {
  $sample = $g.Group | Select-Object -First 1
  [void]$sb.AppendLine("| $($g.Name) | $($g.Count) | $($sample.server_relevance) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Critical tables (full listing)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("These tables drive core server behavior and should be imported first.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| File | Category | Rows | Cols | Has text |")
[void]$sb.AppendLine("|------|----------|-----:|-----:|:--------:|")
$critical = $rows | Where-Object { $_.server_relevance -eq 'critical' } | Sort-Object @{e='category'},@{e='filename'}
foreach ($r in $critical) {
  $hx = if ($r.has_text -eq 'True') { 'yes' } else { '' }
  [void]$sb.AppendLine("| ``$($r.filename)`` | $($r.category) | $($r.row_count) | $($r.col_count) | $hx |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Useful tables (grouped)")
[void]$sb.AppendLine("")
$usefulByCat = $rows | Where-Object { $_.server_relevance -eq 'useful' } | Group-Object category | Sort-Object Name
foreach ($g in $usefulByCat) {
  [void]$sb.AppendLine("### $($g.Name) ($($g.Count) files)")
  [void]$sb.AppendLine("")
  $top = $g.Group | Sort-Object { [int]$_.row_count } -Descending | Select-Object -First 8
  [void]$sb.AppendLine("| File | Rows | Cols |")
  [void]$sb.AppendLine("|------|-----:|-----:|")
  foreach ($r in $top) {
    [void]$sb.AppendLine("| ``$($r.filename)`` | $($r.row_count) | $($r.col_count) |")
  }
  if ($g.Count -gt 8) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("(+ $($g.Count - 8) more -- see ``ffxivtool_table_catalog.csv``)")
  }
  [void]$sb.AppendLine("")
}
[void]$sb.AppendLine("## Later / cosmetic tables")
[void]$sb.AppendLine("")
$later = $rows | Where-Object { $_.server_relevance -in @('later','cosmetic') } | Sort-Object @{e='server_relevance'},@{e='filename'}
[void]$sb.AppendLine("| File | Category | Relevance | Rows | Cols |")
[void]$sb.AppendLine("|------|----------|-----------|-----:|-----:|")
foreach ($r in $later) {
  [void]$sb.AppendLine("| ``$($r.filename)`` | $($r.category) | $($r.server_relevance) | $($r.row_count) | $($r.col_count) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## How to regenerate")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```powershell')
[void]$sb.AppendLine('& .\tools\build_ffxivtool_catalog.ps1')
[void]$sb.AppendLine('& .\tools\render_ffxivtool_catalog_md.ps1')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Both scripts are idempotent and rewrite the catalog files in place.")

Set-Content -Path $OutMd -Value $sb.ToString() -Encoding UTF8
Write-Output "Wrote $OutMd"
