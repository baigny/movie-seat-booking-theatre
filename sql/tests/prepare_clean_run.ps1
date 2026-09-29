$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$schemaName = 'movie_verify_' + [Guid]::NewGuid().ToString('N')
$outputPath = Join-Path $PSScriptRoot 'clean_run.generated.sql'
$parts = @("-- Generated verification copy. New schema: $schemaName")
$sources = @('sql/p1.sql', 'sql/p2.sql', 'sql/tests/p2_filters.sql',
    'sql/tests/p1_constraints.sql', 'sql/tests/p1_lifecycle.sql')
foreach ($source in $sources) {
    $sqlText = [IO.File]::ReadAllText((Join-Path $repoRoot $source))
    $sqlText = $sqlText.Replace('movie_seat_booking', $schemaName)
    if ($source -eq 'sql/p1.sql') {
        $sqlText = $sqlText.Replace('CREATE DATABASE IF NOT EXISTS', 'CREATE DATABASE')
    }
    $parts += "-- Begin $source"
    $parts += $sqlText
}
$parts += 'SELECT DATABASE() AS verification_schema;'
$parts += @'
SELECT 'theatres' AS table_name, COUNT(*) AS row_count FROM theatres
UNION ALL SELECT 'screens', COUNT(*) FROM screens
UNION ALL SELECT 'movies', COUNT(*) FROM movies
UNION ALL SELECT 'seats', COUNT(*) FROM seats
UNION ALL SELECT 'shows', COUNT(*) FROM shows
UNION ALL SELECT 'users', COUNT(*) FROM users
UNION ALL SELECT 'bookings', COUNT(*) FROM bookings
UNION ALL SELECT 'show_seats', COUNT(*) FROM show_seats
UNION ALL SELECT 'booking_seats', COUNT(*) FROM booking_seats
UNION ALL SELECT 'payment_events', COUNT(*) FROM payment_events;
SELECT TABLE_NAME, ENGINE FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
USE movie_seat_booking;
'@
[IO.File]::WriteAllText($outputPath, ($parts -join "`r`n"))
Write-Output "Prepared schema: $schemaName"
Write-Output "SOURCE $($outputPath.Replace('\', '/'));"
Write-Output 'Run once. Keep the output; do not rerun this generated file.'
