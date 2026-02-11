# --- 1. INSTALACIÓN IDEMPOTENTE ---
Write-Host "Verificando el rol DHCP..." -ForegroundColor Cyan
$dhcpFeature = Get-WindowsFeature DHCP
if (-not $dhcpFeature.Installed) {
    Write-Host "Instalando DHCP Server y herramientas de administración..." -ForegroundColor Yellow
    Install-WindowsFeature DHCP -IncludeManagementTools
} else {
    Write-Host "El rol DHCP ya está instalado." -ForegroundColor Green
}

# --- 2. ORQUESTACIÓN DE CONFIGURACIÓN DINÁMICA ---
Write-Host "`n--- Configuración de Nuevo Ámbito ---" -ForegroundColor Cyan

# Validación básica de IP (Bucle hasta que sea válida)
do {
    $scopeId = Read-Host "ID de Red (ej: 192.168.100.0)"
    $validIP = $scopeId -as [ipaddress]
} while ($null -eq $validIP)

$scopeName = Read-Host "Nombre descriptivo del Ámbito"
$startIP   = Read-Host "Rango Inicial (ej: 192.168.100.50)"
$endIP     = Read-Host "Rango Final (ej: 192.168.100.150)"
$gateway   = Read-Host "Puerta de enlace (Router)"
$dns       = Read-Host "Servidor DNS"

# Creación del Ámbito
Write-Host "Configurando ámbito en el servidor..." -ForegroundColor Yellow
Add-DhcpServerv4Scope -Name $scopeName -StartRange $startIP -EndRange $endIP -SubnetMask 255.255.255.0 -State Active

# Configuración de Opciones (Router y DNS)
Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway -DnsServer $dns

# --- 3. MÓDULO DE MONITOREO Y VALIDACIÓN ---
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "       ESTADO DEL SERVICIO DHCP           " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Estado del servicio
Get-Service DHCPServer | Select-Object Name, Status, StartType

# Listar concesiones activas
Write-Host "`nConcesiones (Leases) activas actualmente:" -ForegroundColor Yellow
Get-DhcpServerv4Lease -ScopeId $scopeId | Select-Object IPAddress, HostName, ClientId, LeaseExpiryTime | Format-Table -AutoSize