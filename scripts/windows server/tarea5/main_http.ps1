# =============================================================================
# main.ps1 — Script principal de aprovisionamiento web
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : Windows Server
# Uso      : .\main.ps1 [-Instalar|-Verificar|-Revisar|-Help]
# =============================================================================

# Cargar librerias (equivalente a . ./lib/utils.sh en sh)
. "$PSScriptRoot\lib\utilidades.ps1"
. "$PSScriptRoot\lib\http_funcion.ps1"

# -----------------------------------------------------------------------------
# MENU PRINCIPAL
# -----------------------------------------------------------------------------
function MenuPrincipal {
    while ($true) {
        Clear-Host
        Print-Title "Aprovisionamiento Web Automatizado"
        Print-Menu " [1] Instalar servidor HTTP"
        Print-Menu " [2] Ver estado de servidores"
        Print-Menu " [3] Revisar respuesta HTTP"
        Print-Menu " [0] Salir"
        $opcion = Read-Host "`nSelecciona una opcion"

        switch ($opcion) {
            "1" { Menu-Instalacion }
            "2" { Verificar-HTTP; Pausar }
            "3" { Revisar-HTTP; Pausar }
            "0" { Print-Ok "Saliendo..."; exit 0 }
            default { Print-Warning "Opcion invalida." }
        }
    }
}

# -----------------------------------------------------------------------------
# SUBMENU INSTALACION
# -----------------------------------------------------------------------------
function Menu-Instalacion {
    Clear-Host
    Print-Title "Instalar Servidor HTTP"
    Print-Menu "  [1] Apache"
    Print-Menu "  [2] Nginx"
    Print-Menu "  [3] Tomcat"
    Print-Menu "  [0] Volver"
    $opcion = Read-Host "`nSelecciona un servidor"

    switch ($opcion) {
        "1" { Setup-Apache; Pausar }
        "2" { Setup-Nginx; Pausar }
        "3" { Setup-Tomcat; Pausar }
        "0" { return }
        default { Print-Warning "Opcion invalida."; Pausar }
    }
}

# -----------------------------------------------------------------------------
# AYUDA
# -----------------------------------------------------------------------------
function Mostrar-Ayuda {
    Write-Host ""
    Write-Host "USO:" -ForegroundColor Cyan
    Print-Menu "  .\main.ps1                Menu interactivo"
    Print-Menu "  .\main.ps1 -Instalar      Instalar servidor HTTP"
    Print-Menu "  .\main.ps1 -Verificar     Ver estado de servidores"
    Print-Menu "  .\main.ps1 -Revisar       Revisar respuesta HTTP"
    Print-Menu "  .\main.ps1 -Help          Mostrar esta ayuda"
    Write-Host ""
}

# -----------------------------------------------------------------------------
# INICIO — soporta parametros o menu interactivo
# Equivalente al bloque case "$1" en shell
# -----------------------------------------------------------------------------
param(
    [switch]$Instalar,
    [switch]$Verificar,
    [switch]$Revisar,
    [switch]$Help
)

Verificar-Administrador

if ($Help)      { Mostrar-Ayuda }
elseif ($Instalar)  { Menu-Instalacion }
elseif ($Verificar) { Verificar-HTTP; Pausar }
elseif ($Revisar)   { Revisar-HTTP; Pausar }
else                { Menu-Principal }