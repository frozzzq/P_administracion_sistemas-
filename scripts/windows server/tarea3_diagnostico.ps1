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

function ConfigurarDns {
    # 1. Verificar IP Fija
    GestionarIpFija

    Write-Host "`n=== CONFIGURACIÓN DE ZONA Y REGISTROS ===" -ForegroundColor Blue
    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    # Idempotencia: Verificar si la zona ya existe
    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Write-Host "La zona '$dominio' ya existe. Saltando creación." -ForegroundColor Yellow
    } else {
        Write-Host "Creando zona primaria: $dominio..." -ForegroundColor Yellow
        Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
        Write-Host "Zona creada con éxito." -ForegroundColor Green
    }

    # Configuración de Registro A
    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }
    
    $ipDestino = validacionIp "Ingrese la IP a la que apuntará $hostname.$dominio: "

    # Idempotencia: Verificar si el registro ya existe
    $registroExistente = Get-DnsServerResourceRecord -ZoneName $dominio -Name $hostname -RRType A -ErrorAction SilentlyContinue
    if ($registroExistente) {
        Write-Host "El registro '$hostname' ya existe en '$dominio'. Actualizando IP..." -ForegroundColor Yellow
        # Eliminamos y creamos para actualizar (Idempotencia)
        Remove-DnsServerResourceRecord -ZoneName $dominio -Name $hostname -RRType A -Force
    }

    Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino
    Write-Host "Registro A configurado: $hostname.$dominio -> $ipDestino" -ForegroundColor Green
}

function MonitoreoDns {
    Write-Host "`n=== MONITOREO Y VALIDACIÓN DE RESOLUCIÓN ===" -ForegroundColor Blue
    
    # 1. Estado del servicio
    $servicio = Get-Service -Name DNS
    Write-Host "Estado del Servicio: " -NoNewline
    $color = if ($servicio.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host $servicio.Status -ForegroundColor $color

    if ($servicio.Status -eq "Running") {
        $dominioTest = "reprobados.com"
        $hostTest = "www.reprobados.com"

        Write-Host "`nEjecutando pruebas de resolución para $dominioTest..." -ForegroundColor Cyan
        
        # Prueba NSLOOKUP
        Write-Host "[Prueba nslookup]" -ForegroundColor Yellow
        nslookup $dominioTest 127.0.0.1
        
        # Prueba PING
        Write-Host "`n[Prueba ping]" -ForegroundColor Yellow
        if (Test-Connection -ComputerName $hostTest -Count 1 -Quiet) {
            Write-Host "¡ÉXITO! $hostTest responde correctamente." -ForegroundColor Green
        } else {
            Write-Host "FALLO: No se pudo hacer ping a $hostTest. Verifique el firewall." -ForegroundColor Red
        }
    }
}

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