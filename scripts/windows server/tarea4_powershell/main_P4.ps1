
. "$PSScriptRoot\lib\funcion_ssh.ps1"
. "$PSScriptRoot\lib\funcion_dhcp.ps1"   
. "$PSScriptRoot\lib\funcion_dns.ps1"    

function menu {
    Write-Host "`n===================================================================" -ForegroundColor Cyan
    Write-Host "             ADMINISTRACIÓN DE WINDOWS SERVER                      " -ForegroundColor Blue
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "1. Gestionar SSH"       -ForegroundColor Yellow
    Write-Host "2. Gestionar DHCP"      -ForegroundColor Yellow
    Write-Host "3. Gestionar DNS"       -ForegroundColor Yellow
    Write-Host "4. Salir"               -ForegroundColor Yellow
}

do {
    menu
    $opcion = Read-Host "`nElige una opción"

    switch ($opcion) {
        "1" { menuSsh }
        "2" { Write-Host "Módulo DHCP pendiente de integración." -ForegroundColor Gray }
        "3" { Write-Host "Módulo DNS pendiente de integración."  -ForegroundColor Gray }
        "4" { Write-Host "Saliendo..." -ForegroundColor Cyan; break }
        default { Write-Host "Opción inválida." -ForegroundColor Red }
    }

    if ($opcion -ne "4") {
        $continuar = Read-Host "`n¿Volver al menú? (si/no)"
    }

} while ($opcion -ne "4" -and $continuar -eq "si")