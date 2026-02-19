# --- FUNCIONES DE APOYO (REUTILIZABLES) ---

function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            return $ip
        }
        Write-Host "Formato IPv4 inválido. Reintente." -ForegroundColor Red
    } while ($true)
}

function GestionarIpFija {
    Write-Host "`n[Verificando Configuración de Red]" -ForegroundColor Cyan
    # Buscamos la interfaz activa que no sea Loopback
    $interfaz = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1
    
    if ($interfaz.Dhcp -eq "Enabled") {
        Write-Host "ADVERTENCIA: El servidor tiene DHCP habilitado. Se requiere IP fija para DNS." -ForegroundColor Yellow
        $nuevaIp = validacionIp "Ingrese la IP estática para este servidor: "
        $mascara = Read-Host "Ingrese la máscara (ej. 24 para 255.255.255.0): "
        $gw = validacionIp "Ingrese el Gateway (Puerta de enlace): "
        
        Write-Host "Configurando IP estática..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $interfaz.InterfaceAlias -IPAddress $nuevaIp -PrefixLength $mascara -DefaultGateway $gw
        Write-Host "IP configurada con éxito." -ForegroundColor Green
    } else {
        $actual = (Get-NetIPAddress -InterfaceIndex $interfaz.InterfaceIndex -AddressFamily IPv4).IPAddress
        Write-Host "El servidor ya tiene una IP fija configurada: $actual" -ForegroundColor Green
    }
}

# --- FUNCIONES PRINCIPALES ---

# 1. SIEMPRE LAS FUNCIONES DE APOYO AL PRINCIPIO
function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            return $ip
        }
        Write-Host "Formato IPv4 invalido. Reintente." -ForegroundColor Red
    } while ($true)
}

# 2. FUNCIONES DE SERVICIO
function ConfigurarDns {
    Write-Host "`n=== CONFIGURACION DE ZONA Y REGISTROS ===" -ForegroundColor Blue
    
    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    # Corregido: Espacio antes del ':' para evitar el error de variable
    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

    # Corregido: Delimitamos con {} para evitar errores de parseo
    $ipDestino = validacionIp "Ingrese la IP a la que apuntara ${hostname}.${dominio} : "

    try {
        if (-not (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
            Write-Host "Zona $dominio creada." -ForegroundColor Green
        }
        
        Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino -AllowUpdateAny
        Write-Host "Registro configurado con exito." -ForegroundColor Green
    } catch {
        Write-Host "Error en la configuracion: $($_.Exception.Message)" -ForegroundColor Red
    }
} # Asegúrate de que esta llave de cierre exista

# 3. CUERPO PRINCIPAL DEL SCRIPT
do {
    Write-Host "`n--- MENU DNS ---" -ForegroundColor Yellow
    Write-Host "[1] Verificar Instalacion"
    Write-Host "[4] Configurar DNS"
    Write-Host "Escriba 'salir' para finalizar."

    $opc = Read-Host "`nIngrese una opcion"

    switch($opc) {
        "1" { 
            if ((Get-WindowsFeature DNS).Installed) { Write-Host "Instalado" } else { Write-Host "No instalado" }
        }
        "4" { ConfigurarDns }
    }
} while ($opc -ne "salir")

# --- MENU PRINCIPAL ---
do {
    Write-Host "`n======================================================================" -ForegroundColor Yellow
    Write-Host "                           SERVIDOR DNS                               "
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "[1] - VERIFICAR INSTALACION DNS"
    Write-Host "[2] - INSTALAR SERVICIO DNS"
    Write-Host "[3] - REMOVER SERVICIO DNS"
    Write-Host "[4] - CONFIGURAR ZONA Y REGISTROS (reprobados.com)"
    Write-Host "[5] - MONITOREO Y PRUEBAS"
    Write-Host "[6] - SALIR"

    $opc = Read-Host "`nIngrese una opción"

    switch($opc) {
        "1" { 
            $v = Get-WindowsFeature DNS
            if ($v.Installed) { Write-Host "DNS Instalado" -ForegroundColor Green } else { Write-Host "No instalado" -ForegroundColor Red }
        }
        "2" { Install-WindowsFeature DNS -IncludeManagementTools }
        "3" { Uninstall-WindowsFeature DNS -Remove }
        "4" { ConfigurarDns }
        "5" { MonitoreoDns }
        "6" { $opc = "salir" }
    }
} while ($opc -ne "salir")