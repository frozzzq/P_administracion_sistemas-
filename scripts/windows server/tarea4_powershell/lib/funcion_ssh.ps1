function verificarSsh {
    Write-Host "`n--- Verificando estado de OpenSSH Server ---" -ForegroundColor Cyan

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($cap.State -eq "Installed") {
        Write-Host "OpenSSH Server: INSTALADO" -ForegroundColor Green
    } else {
        Write-Host "OpenSSH Server: NO instalado" -ForegroundColor Red
        Write-Host "Sugerencia: usa la opcion Instalar SSH del menu." -ForegroundColor Yellow
        return
    }

    $servicio = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($servicio) {
        $color = if ($servicio.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "Estado del servicio  : " -NoNewline
        Write-Host "$($servicio.Status)" -ForegroundColor $color
        Write-Host "Tipo de inicio       : $($servicio.StartType)"
    }

    $regla = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
    if ($regla) {
        Write-Host "Regla de Firewall    : EXISTE (puerto 22 abierto)" -ForegroundColor Green
    } else {
        Write-Host "Regla de Firewall    : NO encontrada" -ForegroundColor Red
    }
}

function instalarSsh {
    Write-Host "`n--- Instalacion de OpenSSH Server ---" -ForegroundColor Cyan

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($cap.State -eq "Installed") {
        Write-Host "OpenSSH Server ya esta instalado. No se requiere accion." -ForegroundColor Green
    } else {
        Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
            Write-Host "Instalacion completada." -ForegroundColor Green
        } catch {
            Write-Host "Error durante la instalacion: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    Write-Host "Iniciando el servicio sshd..." -ForegroundColor Yellow
    try {
        Start-Service sshd
        Write-Host "Servicio sshd iniciado." -ForegroundColor Green
    } catch {
        Write-Host "Error al iniciar el servicio: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Configurando inicio automatico..." -ForegroundColor Yellow
    Set-Service -Name sshd -StartupType Automatic
    Write-Host "Inicio automatico configurado." -ForegroundColor Green

    $reglaExiste = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
    if (-not $reglaExiste) {
        Write-Host "Creando regla de Firewall para el puerto 22..." -ForegroundColor Yellow
        try {
            New-NetFirewallRule `
                -Name        "sshd" `
                -DisplayName "OpenSSH Server (SSH)" `
                -Enabled     True `
                -Direction   Inbound `
                -Protocol    TCP `
                -Action      Allow `
                -LocalPort   22
            Write-Host "Regla de Firewall creada correctamente." -ForegroundColor Green
        } catch {
            Write-Host "Error al crear la regla: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "La regla de Firewall ya existe." -ForegroundColor Green
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.InterfaceAlias -like "*Ethernet*" -and $_.IPAddress -notlike "169.254*" } |
           Select-Object -First 1).IPAddress
    Write-Host "`nSSH configurado. Desde el cliente conectate con:" -ForegroundColor Cyan
    Write-Host "  ssh Administrador@$ip" -ForegroundColor Yellow
}

function desinstalarSsh {
    Write-Host "`n--- Desinstalacion de OpenSSH Server ---" -ForegroundColor Magenta

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    if ($cap.State -ne "Installed") {
        Write-Host "OpenSSH Server no esta instalado. No hay nada que desinstalar." -ForegroundColor Yellow
        return
    }

    Write-Host "Deteniendo el servicio sshd..." -ForegroundColor Yellow
    Stop-Service sshd -Force -ErrorAction SilentlyContinue

    Write-Host "Desinstalando OpenSSH Server..." -ForegroundColor Yellow
    try {
        Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Host "Desinstalacion completada." -ForegroundColor Green
    } catch {
        Write-Host "Error al desinstalar: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $regla = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
    if ($regla) {
        Remove-NetFirewallRule -Name "sshd"
        Write-Host "Regla de Firewall eliminada." -ForegroundColor Green
    }
}

function menuSsh {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE SERVICIO SSH           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar estado de SSH"   -ForegroundColor Yellow
    Write-Host "2. Instalar y configurar SSH" -ForegroundColor Yellow
    Write-Host "3. Desinstalar SSH"           -ForegroundColor Yellow
    Write-Host "4. Volver al menu principal"  -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { verificarSsh }
        "2" { instalarSsh }
        "3" { desinstalarSsh }
        "4" { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}