function validacionIpDhcp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            $octetos = $ip.Split('.')
            $errorCero = $false
            foreach ($octeto in $octetos) {
                if ($octeto.Length -gt 1 -and $octeto.StartsWith("0")) {
                    $errorCero = $true; break
                }
            }
            if ($errorCero) {
                Write-Host "Error: No ceros a la izquierda." -ForegroundColor Red
                continue
            }
            return $ip
        } else {
            Write-Host "Formato invalido. Reintente." -ForegroundColor Red
        }
    } while ($true)
}

function verificarInstalacion {
    Write-Host "Verificando la instalacion DHCP..." -ForegroundColor Yellow
    $feature = Get-WindowsFeature -Name DHCP
    if ($feature.Installed) {
        Write-Host "SERVICIO DHCP INSTALADO" -ForegroundColor Green
    } else {
        Write-Host "SERVICIO DHCP NO INSTALADO" -ForegroundColor Red
        Write-Host "sugerencia!... use la opcion de instalar el servicio" -ForegroundColor Yellow
    }
}

function instalacion {
    Write-Host "INICIANDO INSTALACION..." -ForegroundColor Cyan
    $check = Get-WindowsFeature -Name DHCP
    if ($check.Installed) {
        Write-Host "SERVICIO DHCP YA INSTALADO, no es necesario reinstalar." -ForegroundColor Green
    } else {
        try {
            $resul = Install-WindowsFeature -Name DHCP -IncludeManagementTools
            if ($resul.RestartNeeded -eq "Yes") {
                Write-Host "REINICIO REQUERIDO PARA COMPLETAR." -ForegroundColor Yellow
                $confirmar = Read-Host "desea reiniciar ahora? (si/no)"
                if ($confirmar -eq "si") { Restart-Computer }
            } else {
                Write-Host "SERVICIO DHCP INSTALADO CON EXITO!" -ForegroundColor Green
            }
        } catch {
            Write-Host "error al instalar: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function desinstalacion {
    Write-Host "INICIANDO DESINSTALACION..." -ForegroundColor DarkMagenta
    $check = Get-WindowsFeature -Name DHCP
    if ($check.Installed) {
        Write-Host "deteniendo proceso en memoria..." -ForegroundColor Yellow
        Stop-Service -Name DHCPServer -Force -ErrorAction SilentlyContinue
        $res = Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools
        if ($res.Success) {
            Write-Host "desinstalacion exitosa!" -ForegroundColor Green
            if ($res.RestartNeeded -eq "Yes") {
                Write-Host "advertencia: se necesita un reinicio" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "servicio no instalado, no se puede desinstalar" -ForegroundColor Red
    }
}

function configuracionDhcp {
    Import-Module DHCPServer -Force
    Write-Host "=== CONFIGURACION DEL SERVICIO DHCP ===" -ForegroundColor DarkBlue

    $nombreScope = Read-Host "Ingrese un nombre para el scope"
    $rangoI = validacionIpDhcp "IP Inicial del rango (IP del Servidor)"
    $prefijoI = $rangoI.Split('.')[0..2] -join '.'

 
    $dnsServidor = $rangoI
    Write-Host "DNS primario asignado automaticamente al servidor: $dnsServidor" -ForegroundColor Cyan

    Write-Host "Configurando IP fija en el servidor ($rangoI)..." -ForegroundColor Yellow
    try {
        Remove-NetIPAddress -InterfaceAlias "Ethernet 2" -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $rangoI -PrefixLength 24 -ErrorAction SilentlyContinue
        Set-DhcpServerv4Binding -BindingState $true -InterfaceAlias "Ethernet 2"
    } catch {
        Write-Host "Aviso: No se pudo cambiar la IP: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $rangoDhcpInicio = "$prefijoI.$([int]($rangoI.Split('.')[3]) + 1)"
    do {
        $rangoF = validacionIpDhcp "IP final del rango"
        $prefijoF = $rangoF.Split('.')[0..2] -join '.'
        if ([version]$rangoI -ge [version]$rangoF) {
            Write-Host "Error: IP inicial mayor a final" -ForegroundColor Red
        }
    } while ([version]$rangoI -ge [version]$rangoF -or $prefijoI -ne $prefijoF)

    $redId   = $prefijoI + ".0"
    $mascara = "255.255.255.0"


    $dnsSecundario = validacionIpDhcp "Servidor DNS secundario (Enter para saltar)" $true
    $gateway = Read-Host "Ingrese la IP del Gateway (Enter para saltar)"

    $tiempolease = Read-Host "Ingrese tiempo de concesion (ej: 08:00:00)"
    if ([string]::IsNullOrWhiteSpace($tiempolease)) { $tiempolease = "08:00:00" }

    Write-Host "Aplicando configuracion..." -ForegroundColor Cyan
    try {
        Add-DhcpServerv4Scope -Name $nombreScope -StartRange $rangoDhcpInicio -EndRange $rangoF -SubnetMask $mascara -LeaseDuration ([timespan]$tiempolease) -State "Active"

        if (-not [string]::IsNullOrWhiteSpace($dnsSecundario)) {
            Set-DhcpServerv4OptionValue -ScopeId $redId -DnsServer $dnsServidor, $dnsSecundario -Force
            Write-Host "DNS configurado: primario=$dnsServidor secundario=$dnsSecundario" -ForegroundColor Green
        } else {
            Set-DhcpServerv4OptionValue -ScopeId $redId -DnsServer $dnsServidor -Force
            Write-Host "DNS configurado: primario=$dnsServidor" -ForegroundColor Green
        }

        if (-not [string]::IsNullOrWhiteSpace($gateway)) {
            Set-DhcpServerv4OptionValue -ScopeId $redId -OptionId 3 -Value $gateway
            Write-Host "Gateway configurado: $gateway" -ForegroundColor Green
        }
        Write-Host "Configuracion exitosa!" -ForegroundColor Green
    } catch {
        Write-Host "Error critico: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function borrarScopes {
    try {
        Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force
        Write-Host "Scopes eliminados correctamente." -ForegroundColor Green
    } catch {
        Write-Host "error al borrar scopes: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function monitoreo {
    Write-Host "================== MONITOREO DHCP ==================" -ForegroundColor Blue
    $servicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    if ($servicio) {
        $color = if ($servicio.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "estado del servicio: " -NoNewline
        Write-Host "$($servicio.Status)" -ForegroundColor $color
    } else {
        Write-Host "el servicio DHCP no esta instalado correctamente" -ForegroundColor Red
        return
    }
    Write-Host "----------------------------------------------------"
    Write-Host "equipos conectados (leases activos):" -ForegroundColor Yellow
    try {
        $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($ambitos) {
            $hayleases = $false
            foreach ($ambito in $ambitos) {
                $leases = Get-DhcpServerv4Lease -ScopeId $ambito.ScopeId -ErrorAction SilentlyContinue
                if ($leases) {
                    $leases | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | Format-Table -AutoSize
                    $hayleases = $true
                }
            }
            if (-not $hayleases) {
                Write-Host "no hay equipos conectados actualmente" -ForegroundColor Gray
            }
        } else {
            Write-Host "no hay ambitos (scopes) configurados"
        }
    } catch {
        Write-Host "no existe el servicio o no hay clientes disponibles" -ForegroundColor Yellow
    }
}

function menuDhcp {
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE SERVICIO DHCP          " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar instalacion"    -ForegroundColor Yellow
    Write-Host "2. Instalar servicio"        -ForegroundColor Yellow
    Write-Host "3. Desinstalar servicio"     -ForegroundColor Yellow
    Write-Host "4. Configurar DHCP"          -ForegroundColor Yellow
    Write-Host "5. Borrar scopes"            -ForegroundColor Yellow
    Write-Host "6. Monitoreo"                -ForegroundColor Yellow
    Write-Host "7. Volver al menu principal" -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { verificarInstalacion }
        "2" { instalacion }
        "3" { desinstalacion }
        "4" { configuracionDhcp }
        "5" { borrarScopes }
        "6" { monitoreo }
        "7" { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}