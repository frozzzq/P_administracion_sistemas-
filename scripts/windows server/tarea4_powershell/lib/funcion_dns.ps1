function validacionIpDns {
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

function GestionarIpFija {
    Write-Host "`n[Verificando Configuracion de Red]" -ForegroundColor Cyan
    $interfaz = Get-NetIPInterface -AddressFamily IPv4 |
                Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
                Select-Object -First 1

    if ($interfaz.Dhcp -eq "Enabled") {
        Write-Host "ADVERTENCIA: El servidor tiene DHCP habilitado. Se requiere IP fija para DNS." -ForegroundColor Yellow
        $nuevaIp = validacionIpDns "Ingrese la IP estatica para este servidor"
        $mascara = Read-Host "Ingrese la mascara (ej. 24 para 255.255.255.0)"
        $gw      = validacionIpDns "Ingrese el Gateway (Puerta de enlace)"

        Write-Host "Configurando IP estatica..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $interfaz.InterfaceAlias -IPAddress $nuevaIp -PrefixLength $mascara -DefaultGateway $gw
        Write-Host "IP configurada con exito." -ForegroundColor Green
    } else {
        $actual = (Get-NetIPAddress -InterfaceIndex $interfaz.InterfaceIndex -AddressFamily IPv4).IPAddress
        Write-Host "El servidor ya tiene una IP fija configurada: $actual" -ForegroundColor Green
    }
}

function ConfigurarDns {
    Write-Host "`n=== CONFIGURACION DE ZONA Y REGISTROS ===" -ForegroundColor Blue

    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

    $ipDestino = validacionIpDns "Ingrese la IP a la que apuntara ${hostname}.${dominio}"

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
}

function borrarDominio {
    $borrar = Read-Host "Ingrese el dominio que desea borrar (ej: reprobados.com)"
    if (Get-DnsServerZone -Name $borrar -ErrorAction SilentlyContinue) {
        try {
            Remove-DnsServerZone -Name $borrar -Force
            Write-Host "El dominio $borrar ha sido borrado correctamente." -ForegroundColor Green
        } catch {
            Write-Host "Error al eliminar el dominio: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Error: el dominio $borrar no existe en el servidor." -ForegroundColor Red
    }
}

function MonitoreoDns {
    Write-Host "`n=== MODULO DE MONITOREO Y VALIDACION ===" -ForegroundColor Cyan

    $servicio = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($servicio.Status -eq "Running") {
        Write-Host "[OK] El servicio DNS esta operando correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio DNS no esta iniciado." -ForegroundColor Red
        return
    }

    $dominioTest = Read-Host "Ingrese el dominio a validar (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominioTest)) { $dominioTest = "reprobados.com" }

    $hostTest = Read-Host "Ingrese el host a validar (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostTest)) { $hostTest = "www" }

    $nombreCompleto = "${hostTest}.${dominioTest}"
    Write-Host "`nEjecutando nslookup para $nombreCompleto..." -ForegroundColor Yellow

    $lookup = Resolve-DnsName -Name $nombreCompleto -Server 127.0.0.1 -ErrorAction SilentlyContinue
    if ($lookup) {
        $ipDevuelta = $lookup.IPAddress
        Write-Host "[EXITO] nslookup resolvio $nombreCompleto en la IP: $ipDevuelta" -ForegroundColor Green

        Write-Host "Ejecutando ping para verificar respuesta..." -ForegroundColor Yellow
        $ping = Test-Connection -ComputerName $nombreCompleto -Count 1 -ErrorAction SilentlyContinue
        if ($ping) {
            $ipPing = $ping.IPV4Address.IPAddressToString
            Write-Host "[EXITO] Ping respondio desde $ipPing" -ForegroundColor Green
            if ($ipDevuelta -eq $ipPing) {
                Write-Host "EVIDENCIA: La IP devuelta coincide con la maquina referenciada ($ipDevuelta)." -ForegroundColor Cyan
            }
        } else {
            Write-Host "[AVISO] El nombre resuelve pero el host no responde al ping (verifique Firewall)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FALLO] No se pudo resolver el nombre $nombreCompleto en el DNS local." -ForegroundColor Red
    }
}

function menuDns {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "       GESTION DE SERVICIO DNS          " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Gestionar IP fija"        -ForegroundColor Yellow
    Write-Host "2. Configurar servicio DNS"  -ForegroundColor Yellow
    Write-Host "3. Borrar dominio"           -ForegroundColor Yellow
    Write-Host "4. Monitoreo DNS"            -ForegroundColor Yellow
    Write-Host "5. Volver al menu principal" -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { GestionarIpFija }
        "2" { ConfigurarDns }
        "3" { borrarDominio }
        "4" { MonitoreoDns }
        "5" { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}