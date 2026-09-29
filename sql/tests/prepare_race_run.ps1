$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$schemaName = 'movie_race_' + [Guid]::NewGuid().ToString('N')
$schemaSql = [IO.File]::ReadAllText((Join-Path $repoRoot 'sql/p1.sql'))
$schemaSql = $schemaSql.Replace('movie_seat_booking', $schemaName)
$schemaSql = $schemaSql.Replace('CREATE DATABASE IF NOT EXISTS', 'CREATE DATABASE')
$setupTail = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'race_setup_tail.sql'))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'race_setup.generated.sql'),
    $schemaSql + "`r`n" + $setupTail)
foreach ($sessionName in @('a', 'b')) {
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "race_session_$sessionName.sql"))
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot "race_$sessionName.generated.sql"),
        "USE $schemaName;`r`n" + $template)
}
Write-Output "Prepared isolated race schema: $schemaName"
Write-Output 'Run race_setup.generated.sql once in A, then race_a.generated.sql.'
Write-Output 'Run race_b.generated.sql in B; while it waits, execute COMMIT in A.'
