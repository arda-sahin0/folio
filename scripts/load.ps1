$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# --- load .env into this session --------------------------------------------
Get-Content .env | Where-Object { $_ -match '^\s*[^#\s].*=' } | ForEach-Object {
    $name, $value = $_.Split('=', 2)
    Set-Item -Path "env:$($name.Trim())" -Value $value.Trim()
}
$user = $env:POSTGRES_USER
$db   = $env:POSTGRES_DB

# --- refuse to run if the database isn't up ---------------------------------
$status = docker inspect -f '{{.State.Health.Status}}' folio-db 2>$null
if ($status -ne 'healthy') {
    throw "folio-db is not healthy (status: '$status'). Run 'docker compose up -d' first."
}

# --- run every loader in filename order --------------------------------------
$files = Get-ChildItem loaders\*.sql | Sort-Object Name
if ($files.Count -eq 0) { throw "No .sql files found in loaders\" }

foreach ($f in $files) {
    Write-Host "  -> $($f.Name)" -ForegroundColor DarkGray
    docker compose exec -T db psql -v ON_ERROR_STOP=1 -q -U $user -d $db -f "/loaders/$($f.Name)"
    if ($LASTEXITCODE -ne 0) { throw "Loader failed: $($f.Name)" }
}

Write-Host "Loaded $($files.Count) file(s)." -ForegroundColor Green