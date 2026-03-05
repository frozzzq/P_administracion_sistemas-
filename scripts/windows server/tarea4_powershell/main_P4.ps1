. "$PSScriptRoot\lib\funcion_ssh.ps1"
. "$PSScriptRoot\lib\funciones_dhcp.ps1"
. "$PSScriptRoot\lib\funcion_dns.ps1"
. "$PSScriptRoot\lib\funcion_ftp.ps1"

function menu {
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "          ADMINISTRACION DE WINDOWS SERVER                         " -ForegroundColor Blue
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "1. Gestionar SSH"  -ForegroundColor Yellow
    Write-Host "2. Gestionar DHCP" -ForegroundColor Yellow
    Write-Host "3. Gestionar DNS"  -ForegroundColor Yellow
    Write-Host "4. Gestionar FTP"  -ForegroundColor Yellow
    Write-Host "5. Salir"          -ForegroundColor Yellow
}

do {
    menu
    $opcion = Read-Host "Elige una opcion"
    switch ($opcion) {
        "1" { menuSsh }
        "2" { menuDhcp }
        "3" { menuDns }
        "4" { menuFtp }
        "5" { Write-Host "Saliendo..." -ForegroundColor Cyan }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
    if ($opcion -ne "4") {
        $continuar = Read-Host "Volver al menu? (si/no)"
    }
} while ($opcion -ne "4" -and $continuar -eq "si")