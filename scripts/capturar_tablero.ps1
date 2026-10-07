# Captura el tablero publico de Metabase como PNG con Edge headless (se ejecuta en Windows, fuera de Docker).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\capturar_tablero.ps1 <enlace-publico> <salida.png>
# El enlace publico lo imprime: docker exec lab8-lab python scripts/metabase_dashboard.py --publico
param([Parameter(Mandatory)] [string]$Url, [Parameter(Mandatory)] [string]$Salida)

$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$perfil = Join-Path $env:TEMP "lab8_edge_headless"
$Salida = [IO.Path]::GetFullPath((Join-Path (Get-Location) $Salida))
& $edge --headless=new --disable-gpu --hide-scrollbars "--user-data-dir=$perfil" `
    --window-size=1600,2700 --virtual-time-budget=45000 "--screenshot=$Salida" $Url 2>$null | Out-Null
Start-Sleep 2
Get-Item $Salida | Select-Object FullName, Length
