# ==============================================================================
# ssh_functions.ps1
# Librería de funciones para la gestión del servicio OpenSSH en Windows Server
# ==============================================================================

function verificarSsh {
    Write-Host "`n--- Verificando estado de OpenSSH Server ---" -ForegroundColor Cyan

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($cap.State -eq "Installed") {
        Write-Host "OpenSSH Server: INSTALADO" -ForegroundColor Green
    } else {
        Write-Host "OpenSSH Server: NO instalado" -ForegroundColor Red
        Write-Host "Sugerencia: usa la opción 'Instalar SSH' del menú." -ForegroundColor Yellow
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

# ------------------------------------------------------------------------------

function instalarSsh {
    Write-Host "`n--- Instalación de OpenSSH Server ---" -ForegroundColor Cyan

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($cap.State -eq "Installed") {
        Write-Host "OpenSSH Server ya está instalado. No se requiere acción." -ForegroundColor Green
    } else {
        Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
            Write-Host "Instalación completada." -ForegroundColor Green
        } catch {
            Write-Host "Error durante la instalación: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    # Iniciar el servicio
    Write-Host "Iniciando el servicio sshd..." -ForegroundColor Yellow
    try {
        Start-Service sshd
        Write-Host "Servicio sshd iniciado." -ForegroundColor Green
    } catch {
        Write-Host "Error al iniciar el servicio: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Configurar inicio automático
    Write-Host "Configurando inicio automático..." -ForegroundColor Yellow
    Set-Service -Name sshd -StartupType Automatic
    Write-Host "Inicio automático configurado." -ForegroundColor Green

    # Abrir puerto 22 en el Firewall
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

    Write-Host "`n✔ SSH configurado. Desde el cliente puedes conectarte con:" -ForegroundColor Cyan
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.InterfaceAlias -like "*Ethernet*" -and $_.IPAddress -notlike "169.254*" } |
           Select-Object -First 1).IPAddress
    Write-Host "  ssh <usuario>@$ip" -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------

function desinstalarSsh {
    Write-Host "`n--- Desinstalación de OpenSSH Server ---" -ForegroundColor Magenta

    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    if ($cap.State -ne "Installed") {
        Write-Host "OpenSSH Server no está instalado. No hay nada que desinstalar." -ForegroundColor Yellow
        return
    }

    # Detener y desinstalar
    Write-Host "Deteniendo el servicio sshd..." -ForegroundColor Yellow
    Stop-Service sshd -Force -ErrorAction SilentlyContinue

    Write-Host "Desinstalando OpenSSH Server..." -ForegroundColor Yellow
    try {
        Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Host "Desinstalación completada." -ForegroundColor Green
    } catch {
        Write-Host "Error al desinstalar: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Eliminar regla del Firewall si existe
    $regla = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
    if ($regla) {
        Remove-NetFirewallRule -Name "sshd"
        Write-Host "Regla de Firewall eliminada." -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------

function menuSsh {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "        GESTIÓN DE SERVICIO SSH         " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar estado de SSH"              -ForegroundColor Yellow
    Write-Host "2. Instalar y configurar SSH"            -ForegroundColor Yellow
    Write-Host "3. Desinstalar SSH"                      -ForegroundColor Yellow
    Write-Host "4. Volver al menú principal"             -ForegroundColor Yellow

    $op = Read-Host "`nElige una opción"
    switch ($op) {
        "1" { verificarSsh }
        "2" { instalarSsh }
        "3" { desinstalarSsh }
        "4" { return }
        default { Write-Host "Opción inválida." -ForegroundColor Red }
    }
}