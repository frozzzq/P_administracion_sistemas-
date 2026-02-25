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
        Write-Host "OpenSSH Server ya esta instalado." -ForegroundColor Green
    } else {
        Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
            Write-Host "Instalacion completada." -ForegroundColor Green

            # Esperar a que el servicio quede registrado
            Write-Host "Esperando registro del servicio..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5

        } catch {
            Write-Host "Error durante la instalacion: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    # Verificar que el servicio exista antes de intentar iniciarlo
    $servicio = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if (-not $servicio) {
        Write-Host "El servicio sshd aun no esta disponible." -ForegroundColor Red
        Write-Host "Intenta reiniciar el servidor y ejecutar la opcion 2 nuevamente." -ForegroundColor Yellow
        return
    }
}
    # Resto del script igual...

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