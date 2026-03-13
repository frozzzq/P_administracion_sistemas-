# ============================================================
# windows-serviciosHTTP.ps1
# Menu principal - Windows Server 2022 Core
# Uso: powershell -ExecutionPolicy RemoteSigned -File .\windows-serviciosHTTP.ps1
# ============================================================
#Requires -RunAsAdministrator

# Cargar funciones desde el mismo directorio
$rutaFunciones = "$PSScriptRoot\windows-funciones_http.ps1"
if (-not (Test-Path $rutaFunciones)) {
    Write-Host "  [x] Archivo no encontrado: $rutaFunciones" -ForegroundColor Red
    Write-Host "  [i] Asegurate de que 'windows-funciones_http.ps1' este en la misma carpeta." -ForegroundColor White
    exit 1
}
. $rutaFunciones

# =============== MENU PRINCIPAL ===============
function menuPrincipal {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ================================================" -ForegroundColor Cyan
        Write-Host "           GESTION DE SERVIDORES HTTP              " -ForegroundColor White
        Write-Host "  ================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    1. Instalar / Reconfigurar servidor HTTP" -ForegroundColor White
        Write-Host "    2. Ver estado de servidores"              -ForegroundColor White
        Write-Host "    3. Revisar respuesta HTTP"                -ForegroundColor White
        Write-Host "    4. Salir"                                 -ForegroundColor White
        Write-Host ""
        Write-Host "  ------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        $op = Read-Host "  Selecciona una opcion"
        switch ($op) {
            "1" {
                InstalarHTTP
                Write-Host ""
                Read-Host "  Enter para continuar"
            }
            "2" {
                VerificarHTTP
                Read-Host "  Enter para continuar"
            }
            "3" {
                RevisarHTTP
                Write-Host ""
                Read-Host "  Enter para continuar"
            }
            "4" {
                Write-Host ""
                Write-Host "  Saliendo..." -ForegroundColor Cyan
                return
            }
            default {
                Write-Host "  [!] Opcion no valida." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

menuPrincipal