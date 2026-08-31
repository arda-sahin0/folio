# Destroys the database and rebuilds it from scratch by applying every migration in order.

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# --- load .env into this session --------------------------------------------
Get-Content .env | Where-Object { $_ -match '^\s*[^#\s].*=' } | ForEach-Object {
    $name, $value = $_.Split('=', 2)
    Set-Item -Path "env:$($name.Trim())" -Value $value.Trim()
}
$user = $env:POSTGRES_USER
$db   = $env:POSTGRES_DB

# --- tear down and restart ---------------------------------------------------
Write-Host "Tearing down..." -ForegroundColor Cyan
docker compose down -v

Write-Host "Starting Postgres..." -ForegroundColor Cyan
docker compose up -d

# --- wait for the healthcheck ------------------------------------------------
Write-Host "Waiting for health..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds(60)
do {
    Start-Sleep -Seconds 1
    $status = docker inspect -f '{{.State.Health.Status}}' folio-db 2>$null
} while ($status -ne 'healthy' -and (Get-Date) -lt $deadline)
if ($status -ne 'healthy') { throw "Database never became healthy (last status: $status)." }

# --- apply migrations in filename order --------------------------------------
Get-ChildItem migrations\*.sql | Sort-Object Name | ForEach-Object {
    Write-Host "  -> $($_.Name)" -ForegroundColor DarkGray

    docker compose exec -T db psql -v ON_ERROR_STOP=1 -q -U $user -d $db -f "/migrations/$($_.Name)"
    if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($_.Name)" }

    docker compose exec -T db psql -q -U $user -d $db `
        -c "INSERT INTO schema_migrations (filename) VALUES ('$($_.Name)') ON CONFLICT DO NOTHING;"
    if ($LASTEXITCODE -ne 0) { throw "Could not record migration: $($_.Name)" }
}

Write-Host "Ready. $db rebuilt from $(( Get-ChildItem migrations\*.sql).Count) migrations." -ForegroundColor Green