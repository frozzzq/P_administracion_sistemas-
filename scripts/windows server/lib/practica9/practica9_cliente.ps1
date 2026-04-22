#Requires -RunAsAdministrator

function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }

$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_MSI  = "$PSScriptRoot\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\VC_redist.x64.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"
$RUTA_SECRET   = "$PSScriptRoot\multiotp_secret.txt"


function Instalar-MultiOTP {
    Print-Info "Verificando instalacion de multiOTP..."

    $instalado = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                 Where-Object { $_.DisplayName -like "*multiOTP*" } |
                 Select-Object -First 1

    if ($instalado) {
        Print-Warn "multiOTP ya instalado: $($instalado.DisplayVersion) (se omite)"
        return
    }

    if (-not (Test-Path $VCREDIST_EXE)) {
        Print-Err "No se encontro: $VCREDIST_EXE"
        Print-Info "Copia VC_redist.x64.exe y multiOTP.msi al mismo directorio que este script."
        return
    }

    if (-not (Test-Path $MULTIOTP_MSI)) {
        Print-Err "No se encontro: $MULTIOTP_MSI"
        return
    }

    Print-Info "Instalando Visual C++ Redistributable..."
    Start-Process $VCREDIST_EXE -ArgumentList "/quiet /norestart" -Wait
    Print-Ok "Visual C++ instalado."

    Print-Info "Instalando multiOTP Credential Provider..."
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MULTIOTP_MSI`" /quiet /norestart" -Wait
    Print-Ok "multiOTP instalado."
}


function Configurar-CredentialProvider {
    Print-Info "Configurando Credential Provider..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Ejecuta primero la opcion 1."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3      | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800 | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    try {
        Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e" -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e" -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1    -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 1    -ErrorAction Stop
        Print-Ok "Credential Provider configurado en registro."
    } catch {
        Print-Err "Error al escribir en registro: $_"
        Print-Warn "Verifica que multiOTP este correctamente instalado."
    }
}


function Configurar-Servidor {
    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Ejecuta primero la opcion 1."
        return
    }

    $ip = Read-Host "IP del servidor multiOTP (Windows Server)"

    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        Print-Err "IP no valida: $ip"
        return
    }

    if (-not (Test-Path $RUTA_SECRET)) {
        Print-Err "No se encontro: $RUTA_SECRET"
        Print-Info "Copia multiotp_secret.txt del servidor ($env:USERPROFILE\multiotp_secret.txt) a este directorio."
        return
    }

    $secret = (Get-Content $RUTA_SECRET -Raw).Trim()

    & $MULTIOTP_EXE -config server-url="http://$ip`:8112" | Out-Null
    & $MULTIOTP_EXE -config server-secret=$secret         | Out-Null
    & $MULTIOTP_EXE -config server-timeout=10             | Out-Null
    & $MULTIOTP_EXE -config server-cache-level=0          | Out-Null
    Print-Ok "Cliente apuntando al servidor: http://$ip`:8112"
    Print-Ok "Server-secret configurado."
    Print-Info "La validacion del OTP se realiza en el servidor, no localmente."
}


function Mostrar-Instrucciones {
    Clear-Host
    Write-Host "========== Instrucciones de uso ==========" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ANTES de ejecutar este script necesitas tener en este mismo"
    Write-Host "directorio los siguientes archivos del servidor:"
    Write-Host ""
    Write-Host "  - multiOTP.msi          (instalador del Credential Provider)"
    Write-Host "  - VC_redist.x64.exe     (dependencia de Visual C++)"
    Write-Host "  - multiotp_secret.txt   (generado por el script del servidor, opcion 5)"
    Write-Host ""
    Write-Host "Ubicacion en el servidor de los instaladores:"
    Write-Host "  \\<IP_SERVIDOR>\c$\...\scripts\windows server\lib\practica9\"
    Write-Host ""
    Write-Host "Ubicacion en el servidor de multiotp_secret.txt:"
    Write-Host "  \\<IP_SERVIDOR>\c$\Users\Administrador\multiotp_secret.txt"
    Write-Host ""
    Write-Host "ORDEN de ejecucion:"
    Write-Host "  1) Instalar multiOTP"
    Write-Host "  2) Configurar Credential Provider"
    Write-Host "  3) Apuntar al servidor"
    Write-Host "  4) Reiniciar"
    Write-Host ""
    Write-Host "Al iniciar sesion con EMPRESA\usuario se pedira contrasena"
    Write-Host "y luego el codigo de Google Authenticator."
    Write-Host ""
    Write-Host "El cliente NO almacena secrets — la validacion ocurre en el servidor."
    Write-Host ""
}


function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========== Practica 09: Configuracion MFA - Cliente =========="
        Write-Host ""
        Write-Host "  [1] Instalar multiOTP Credential Provider"
        Write-Host "  [2] Configurar Credential Provider"
        Write-Host "  [3] Apuntar al servidor multiOTP"
        Write-Host "  [4] Ver instrucciones"
        Write-Host "  [5] Salir"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Instalar-MultiOTP;             Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Configurar-CredentialProvider; Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Configurar-Servidor;           Read-Host "`nEnter para continuar" }
            "4" { Mostrar-Instrucciones;                     Read-Host "`nEnter para continuar" }
            "5" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu