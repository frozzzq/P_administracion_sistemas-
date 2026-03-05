# ============================================================================
# diagnostico_ftp.ps1
# Corre este script y manda el resultado completo para poder ayudarte
# ============================================================================

$FTP_ROOT     = "C:\ftp"
$SITE_NAME    = "ServidorFTP"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTICO FTP - 530 inaccessible       " -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

Import-Module WebAdministration -ErrorAction SilentlyContinue

# --- 1. Estado del servicio ---
Write-Host "[1] SERVICIO FTPSVC" -ForegroundColor Yellow
$svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
Write-Host "    Estado      : $($svc.Status)"
Write-Host "    Inicio      : $($svc.StartType)"

# --- 2. Sitio IIS ---
Write-Host "`n[2] SITIO IIS FTP" -ForegroundColor Yellow
$site = Get-Website -Name $SITE_NAME -ErrorAction SilentlyContinue
if ($site) {
    Write-Host "    Nombre      : $($site.Name)"
    Write-Host "    Estado      : $($site.State)"
    Write-Host "    Ruta fisica : $($site.PhysicalPath)"
    Write-Host "    Bindings    : $($site.Bindings.Collection | ForEach-Object { $_.bindingInformation })"
} else {
    Write-Host "    ERROR: Sitio '$SITE_NAME' NO ENCONTRADO" -ForegroundColor Red
}

# --- 3. Modo de aislamiento ---
Write-Host "`n[3] MODO DE AISLAMIENTO" -ForegroundColor Yellow
try {
    $isolation = Get-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name "ftpServer.userIsolation.mode" -ErrorAction Stop
    Write-Host "    Valor actual: $($isolation.Value)"
    Write-Host "    (Debe ser 3 = IsolateAllDirectories)"
    if ($isolation.Value -ne 3) {
        Write-Host "    PROBLEMA: El valor no es 3" -ForegroundColor Red
    }
} catch {
    Write-Host "    ERROR al leer: $_" -ForegroundColor Red
}

# --- 4. Autenticacion ---
Write-Host "`n[4] AUTENTICACION" -ForegroundColor Yellow
try {
    $basic = Get-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authentication/basicAuthentication" `
        -PSPath "IIS:\" -Location $SITE_NAME -Name "enabled"
    $anon  = Get-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authentication/anonymousAuthentication" `
        -PSPath "IIS:\" -Location $SITE_NAME -Name "enabled"
    Write-Host "    Basica    : $($basic.Value)  (debe ser True)"
    Write-Host "    Anonima   : $($anon.Value)"
} catch {
    Write-Host "    ERROR al leer auth: $_" -ForegroundColor Red
}

# --- 5. Usuarios y carpetas ---
Write-Host "`n[5] USUARIOS Y CARPETAS" -ForegroundColor Yellow

$grupos = @("reprobados","recursadores")
foreach ($g in $grupos) {
    $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
    foreach ($m in $miembros) {
        $u     = $m.Name -replace ".*\\",""
        $jaula = "$FTP_ROOT\LocalUser\$u"

        Write-Host "`n  --- Usuario: $u (grupo: $g) ---" -ForegroundColor Cyan

        # Cuenta del sistema
        $acct = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
        if ($acct) {
            Write-Host "    Cuenta habilitada : $($acct.Enabled)"
            Write-Host "    Pass caducada     : $($acct.PasswordExpired)"
            Write-Host "    Pass nunca expira : $($acct.PasswordNeverExpires)"
        } else {
            Write-Host "    ERROR: Cuenta de sistema NO encontrada" -ForegroundColor Red
        }

        # Carpeta jaula
        Write-Host "    Jaula esperada    : $jaula"
        if (Test-Path $jaula) {
            Write-Host "    Jaula existe      : SI" -ForegroundColor Green
        } else {
            Write-Host "    Jaula existe      : NO" -ForegroundColor Red
        }

        # Subcarpetas dentro de la jaula
        if (Test-Path $jaula) {
            $subs = Get-ChildItem $jaula -ErrorAction SilentlyContinue
            if ($subs) {
                foreach ($s in $subs) {
                    $tipo = if ($s.LinkType) { "junction" } else { "carpeta" }
                    Write-Host "      $($s.Name) [$tipo]"
                }
            } else {
                Write-Host "      (vacia o sin acceso)" -ForegroundColor Red
            }
        }

        # Permisos de la jaula
        if (Test-Path $jaula) {
            Write-Host "    Permisos de $jaula :"
            $acl = Get-Acl $jaula
            foreach ($rule in $acl.Access) {
                Write-Host "      $($rule.IdentityReference) | $($rule.FileSystemRights) | $($rule.AccessControlType)"
            }
        }
    }
}

# --- 6. Derechos de logon ---
Write-Host "`n[6] DERECHOS DE LOGON (SeInteractiveLogonRight)" -ForegroundColor Yellow
$tmpInf = "$env:TEMP\sec_diag.inf"
& secedit /export /cfg $tmpInf /quiet 2>$null
$cfg    = Get-Content $tmpInf -ErrorAction SilentlyContinue
$linea  = $cfg | Where-Object { $_ -match "SeInteractiveLogonRight" }
Write-Host "    $linea"
$lineaDeny = $cfg | Where-Object { $_ -match "SeDenyInteractiveLogonRight" }
Write-Host "    Deny: $lineaDeny"
$lineaBatch = $cfg | Where-Object { $_ -match "SeBatchLogonRight" }
Write-Host "    Batch: $lineaBatch"
$lineaNetwork = $cfg | Where-Object { $_ -match "SeNetworkLogonRight" }
Write-Host "    Network: $lineaNetwork"
Remove-Item $tmpInf -ErrorAction SilentlyContinue

# --- 7. Permisos carpeta LocalUser ---
Write-Host "`n[7] PERMISOS DE C:\ftp\LocalUser" -ForegroundColor Yellow
if (Test-Path "$FTP_ROOT\LocalUser") {
    $acl = Get-Acl "$FTP_ROOT\LocalUser"
    foreach ($rule in $acl.Access) {
        Write-Host "    $($rule.IdentityReference) | $($rule.FileSystemRights) | $($rule.AccessControlType)"
    }
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  FIN DEL DIAGNOSTICO" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan