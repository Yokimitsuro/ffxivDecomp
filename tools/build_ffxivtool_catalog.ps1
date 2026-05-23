# Build the FFXIVTool table catalog for the FFXIV 1.23b client exports.
#
# Reads:   data/client_exports/ffxivtool/decode_csv/*.csv
# Writes:  docs/data/ffxivtool_table_catalog.csv
#
# Catalog row schema:
#   filename, base_name, row_count, col_count, body_nonempty_cols,
#   category, subcategory, server_relevance, has_text, notes
#
# Row counting:
#   FFXIVTool CSV layout = row0=column-index header, row1=type header,
#                          row2..N = data rows
#   row_count is DATA rows only (file lines - 2).
#
# Categorization is by filename prefix / known names.

param(
  [string]$Root = "E:\meteor-reborn-research"
)

$ErrorActionPreference = "Stop"

$Source = Join-Path $Root "data\client_exports\ffxivtool\decode_csv"
$OutCsv = Join-Path $Root "docs\data\ffxivtool_table_catalog.csv"

if (-not (Test-Path $Source)) { throw "Source not found: $Source" }

function Get-Category([string]$name) {
  $n = $name.ToLowerInvariant()
  # Order matters: more specific first.
  if ($n -like 'xtx_*' -or $n -eq 'worldmaster.csv') { return 'text_localization' }
  if ($n -like 'populace*')                          { return 'npc_populace' }
  if ($n -like 'aetheryte*')                         { return 'aetheryte' }
  if ($n -like '2dmap*' -or $n -like 'mapnavi*' -or $n -like 'mapobj*') { return 'map' }
  if ($n -like 'zone*' -or $n -eq '_zoneparam.csv' -or $n -like 'dft*' -or $n -eq 'regionparam.csv' -or $n -eq 'zonegroupparam.csv') { return 'zone' }
  if ($n -like 'quest*' -or $n -eq '_quest.csv' -or $n -eq 'questcategory.csv') { return 'quest' }
  if ($n -like 'shop*' -or $n -eq 'gcsealshopitem.csv' -or $n -eq 'marketitem.csv' -or $n -eq 'blackmarket.csv') { return 'shop' }
  if ($n -eq 'command.csv' -or $n -eq 'gamecommand.csv' -or $n -eq 'gamecommandbasic.csv' -or $n -eq 'debugcommand.csv' -or $n -eq 'emote.csv' -or $n -eq 'debug.csv') { return 'command' }
  if ($n -eq 'item.csv' -or $n -eq 'itemdata.csv' -or $n -eq '_item.csv' -or $n -eq 'itemcolor.csv' -or $n -like 'itemgc*' -or $n -like 'itemhamlet*' -or $n -eq 'negotiationitem.csv' -or $n -eq 'objectitemstorage.csv' -or $n -eq 'weapon.csv' -or $n -eq 'armor.csv' -or $n -eq 'accessory.csv' -or $n -eq 'equipment.csv' -or $n -eq 'equipset.csv' -or $n -eq 'materia.csv' -or $n -eq 'materiabook.csv') { return 'item' }
  if ($n -like 'actorclass*')                        { return 'actor_class' }
  if ($n -like 'instanceraid*' -or $n -like 'raid*')  { return 'instance_content' }
  if ($n -like 'achievement*')                       { return 'achievement' }
  if ($n -like 'request*')                           { return 'request_leve' }
  if ($n -like 'passivegl*' -or $n -like 'privategl*' -or $n -like 'guildleve*') { return 'guildleve' }
  if ($n -like 'objectevent*' -or $n -like 'objectbed*' -or $n -like 'object*' -or $n -like 'gimmick*' -or $n -like 'elevator*' -or $n -like 'beacon*' -or $n -like 'occupancy*' -or $n -like 'bookshelf*') { return 'event_object' }
  if ($n -eq 'recipe.csv' -or $n -eq 'craftjudge.csv' -or $n -eq 'harvestjudge.csv') { return 'craft_harvest' }
  if ($n -eq 'facility.csv' -or $n -like 'chocobo*') { return 'facility' }
  if ($n -eq 'status.csv' -or $n -eq 'tribe.csv' -or $n -eq 'gcrank.csv' -or $n -eq 'memberrank.csv' -or $n -eq 'exp_bpcost.csv' -or $n -eq 'cutreplay.csv') { return 'player_meta' }
  if ($n -eq 'ordinaryretainer.csv')                 { return 'retainer' }
  if ($n -like 'pg*')                                { return 'passive_guildleve' }
  if ($n -like 'hamletdefscore*')                    { return 'hamlet' }
  if ($n -like 'noc*')                               { return 'gear_neck' }
  if ($n -like 'wld*')                               { return 'gear_world' }
  if ($n -like 'etc*')                               { return 'gear_etc' }
  if ($n -like 'spl*')                               { return 'gear_spellcraft' }
  if ($n -like 'com*')                               { return 'gear_common' }
  if ($n -like 'gcu*' -or $n -like 'gcl*' -or $n -like 'gcg*') { return 'gear_grandcompany' }
  if ($n -like 'mnk*')                               { return 'gear_class_mnk' }
  if ($n -like 'drg*')                               { return 'gear_class_drg' }
  if ($n -like 'whm*')                               { return 'gear_class_whm' }
  if ($n -like 'blm*')                               { return 'gear_class_blm' }
  if ($n -like 'pld*')                               { return 'gear_class_pld' }
  if ($n -like 'brd*')                               { return 'gear_class_brd' }
  if ($n -like 'war*')                               { return 'gear_class_war' }
  if ($n -like 'hrv*')                               { return 'gear_class_hrv' }
  if ($n -like 'lnc*')                               { return 'gear_class_lnc' }
  if ($n -like 'acn*')                               { return 'gear_class_acn' }
  if ($n -like 'thm*')                               { return 'gear_class_thm' }
  if ($n -like 'cul*')                               { return 'gear_class_cul' }
  if ($n -like 'fsh*')                               { return 'gear_class_fsh' }
  if ($n -like 'arc*')                               { return 'gear_class_arc' }
  if ($n -like 'wvr*')                               { return 'gear_class_wvr' }
  if ($n -like 'cnj*')                               { return 'gear_class_cnj' }
  if ($n -like 'wdk*')                               { return 'gear_class_wdk' }
  if ($n -like 'pgl*')                               { return 'gear_class_pgl' }
  if ($n -like 'alc*')                               { return 'gear_class_alc' }
  if ($n -like 'gld*')                               { return 'gear_class_gld' }
  if ($n -like 'exc*')                               { return 'gear_class_exc' }
  if ($n -like 'gla*')                               { return 'gear_class_gla' }
  if ($n -like 'min*')                               { return 'gear_class_min' }
  if ($n -like 'man*' -or $n -like 'sum*' -or $n -like 'trl*' -or $n -like 'key*' -or $n -like 'boot*' -or $n -like 'bsm*' -or $n -like 'tan*') { return 'gear_other' }
  if ($n -like 'var_*')                              { return 'gear_variants' }
  if ($n -like 'test*')                              { return 'system' }
  if ($n -eq '_group.csv' -or $n -eq '_layout.csv' -or $n -eq '_movie.csv' -or $n -eq '_region.csv' -or $n -eq '_staffroll.csv' -or $n -eq '_worldmasterlogcategory.csv' -or $n -eq '_text_error_type.csv' -or $n -eq '_text_error_type(2).csv' -or $n -eq '_boot_error_type.csv' -or $n -eq 'var.csv') { return 'system' }
  return 'other'
}

function Get-ServerRelevance([string]$category, [string]$name) {
  switch -Regex ($category) {
    '^command$'           { return 'critical' }
    '^item$'              { return 'critical' }
    '^zone$'              { return 'critical' }
    '^map$'               { return 'critical' }
    '^aetheryte$'         { return 'critical' }
    '^actor_class$'       { return 'critical' }
    '^quest$'             { return 'critical' }
    '^npc_populace$'      { return 'critical' }
    '^shop$'              { return 'critical' }
    '^instance_content$'  { return 'critical' }
    '^request_leve$'      { return 'critical' }
    '^guildleve$'         { return 'critical' }
    '^passive_guildleve$' { return 'critical' }
    '^event_object$'      { return 'critical' }
    '^craft_harvest$'     { return 'critical' }
    '^facility$'          { return 'critical' }
    '^player_meta$'       { return 'critical' }
    '^retainer$'          { return 'critical' }
    '^hamlet$'            { return 'critical' }
    '^achievement$'       { return 'useful' }
    '^gear_variants$'     { return 'cosmetic' }
    '^gear_'              { return 'useful' }
    '^text_localization$' { return 'useful' }
    '^system$'            { return 'later' }
    default               { return 'unknown' }
  }
}

$catalog = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem -Path $Source -File -Filter '*.csv' | Sort-Object Name

foreach ($f in $files) {
  $lineCount = 0
  $colCount  = 0
  $bodyNonemptyCols = 0
  $hasText = $false

  # Stream the file: cheap line count + parse first 3 lines for header + 1 body row sample
  $sr = New-Object System.IO.StreamReader($f.FullName)
  try {
    $header0 = $sr.ReadLine()   # column index row
    $header1 = $sr.ReadLine()   # type row
    $bodySample = $sr.ReadLine() # first data row
    if ($null -ne $header0) {
      $colCount = ([regex]::Matches($header0, ',')).Count + 1
    }
    if ($null -ne $header1) {
      if ($header1 -match 'str') { $hasText = $true }
    }
    if ($null -ne $bodySample) {
      $cells = $bodySample.Split(',')
      $bodyNonemptyCols = ($cells | Where-Object { $_ -ne '' }).Count
    }
    $lineCount = 3 # already read 3
    while ($null -ne $sr.ReadLine()) { $lineCount++ }
  } finally { $sr.Dispose() }

  $headerRows = 2
  $dataRows = [Math]::Max(0, $lineCount - $headerRows)

  $cat = Get-Category $f.Name
  $rel = Get-ServerRelevance $cat $f.Name

  $catalog.Add([PSCustomObject]@{
    filename            = $f.Name
    base_name           = $f.BaseName
    row_count           = $dataRows
    col_count           = $colCount
    body_nonempty_cols  = $bodyNonemptyCols
    category            = $cat
    server_relevance    = $rel
    has_text            = $hasText
    size_bytes          = $f.Length
  })
}

$catalog | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
Write-Output "Wrote $($catalog.Count) rows to $OutCsv"

# Print a brief summary by category + relevance
$catalog | Group-Object category | Sort-Object Count -Descending | ForEach-Object {
  Write-Output ("  category {0,-20} files={1}" -f $_.Name, $_.Count)
}
Write-Output ""
$catalog | Group-Object server_relevance | Sort-Object Count -Descending | ForEach-Object {
  Write-Output ("  relevance {0,-12} files={1}" -f $_.Name, $_.Count)
}
