$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"
$MULTIOTP_MSI  = "$PSScriptRoot\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\VC_redist.x64.exe"
$CSV_USUARIOS  = "$PSScriptRoot\usuarios.csv"
$RUTA_CLAVES   = "$env:USERPROFILE\claves_mfa.txt"
$DOMINIO_MFA   = "empresa.local"


function Generar-ClaveTOTP {
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bytes       = New-Object byte[] 20
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $clave = ""
    for ($i = 0; $i -lt 20; $i++) {
        $clave += $base32Chars[$bytes[$i] % 32]
    }
    return $clave
}


function Registrar-Usuario-Token {
    param([string]$Sam)

    $clave = Generar-ClaveTOTP
    & $MULTIOTP_EXE -createga $Sam $clave | Out-Null

    if ($LASTEXITCODE -eq 11) {
        & $MULTIOTP_EXE -set $Sam prefix-pin=0 | Out-Null
        Print-Ok "  $Sam registrado"

        "Usuario: $Sam"                     | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Nombre en GA: $Sam@$DOMINIO_MFA" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Clave:        $clave"            | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        ""                                  | Out-File $RUTA_CLAVES -Append -Encoding UTF8

    } elseif ($LASTEXITCODE -eq 22) {
        Print-Warn "  $Sam ya registrado en multiOTP (se omite)"
    } else {
        Print-Err "  Error al registrar $Sam (codigo: $LASTEXITCODE)"
    }
}


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


function Configurar-MultiOTP {
    Print-Info "Configurando multiOTP..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Instala primero multiOTP."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3       | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800  | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1    -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 1    -ErrorAction SilentlyContinue
    Print-Ok "Credential Provider configurado."

    # Generar server-secret para que el cliente pueda conectarse
    $secretPath = "$env:USERPROFILE\multiotp_secret.txt"
    $secret = & $MULTIOTP_EXE -showconfig 2>$null | Select-String "server-secret" | ForEach-Object { ($_ -split "=")[1].Trim() }
    if (-not $secret) {
        # Si no existe, generar uno nuevo
        $secret = [System.Guid]::NewGuid().ToString("N")
        & $MULTIOTP_EXE -config server-secret=$secret | Out-Null
    }
    $secret | Out-File $secretPath -Encoding UTF8
    Print-Ok "Server-secret guardado en: $secretPath"
    Print-Info "Copia ese archivo al cliente para la opcion 3 de practica9_cliente.ps1"
}


function Registrar-Usuarios-MFA {
    Print-Info "Registrando usuarios en multiOTP..."

    "========== Claves MFA - $DOMINIO_MFA ==========" | Out-File $RUTA_CLAVES -Encoding UTF8
    "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "Instrucciones:" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "  Abre Google Authenticator -> + -> Ingresar clave -> Tipo: Basada en tiempo" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8

    Write-Host ""
    Print-Info "Registrando Administrador (builtin)..."
    Registrar-Usuario-Token -Sam "Administrador"

    if (Test-Path $CSV_USUARIOS) {
        Write-Host ""
        Print-Info "Registrando usuarios del CSV..."
        $usuarios = Import-Csv $CSV_USUARIOS
        foreach ($u in $usuarios) {
            Registrar-Usuario-Token -Sam $u.Usuario
        }
    } else {
        Print-Warn "CSV no encontrado: $CSV_USUARIOS"
    }

    Write-Host ""
    Print-Ok "Claves guardadas en: $RUTA_CLAVES"
    Write-Host ""
    Write-Host "========== Claves generadas ==========" -ForegroundColor Yellow
    Get-Content $RUTA_CLAVES
    Write-Host "======================================" -ForegroundColor Yellow
}


function Configurar-MFA {
    Clear-Host
    Write-Host "========== Configuracion de MFA =========="
    Write-Host ""

    Instalar-MultiOTP
    Write-Host ""
    Configurar-MultiOTP
    Write-Host ""
    Registrar-Usuarios-MFA

    Write-Host ""
    Print-Ok "MFA configurado correctamente."
    Print-Info "Cada usuario debe agregar su clave a Google Authenticator."
    Print-Info "Las claves estan en: $RUTA_CLAVES"
    Write-Host ""
}