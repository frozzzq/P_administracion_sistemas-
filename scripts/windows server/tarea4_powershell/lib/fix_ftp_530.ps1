# ============================================================================
# fix_530_definitivo.ps1
# Corrige los 3 problemas detectados en el diagnostico
# ============================================================================

$FTP_ROOT  = "C:\ftp"
$SITE_NAME = "ServidorFTP"

Import-Module WebAdministration -ErrorAction Stop

# ============================================================================
# PROBLEMA 1: Modo de aislamiento no es 3
# ============================================================================
Write-Host "`n[1/3] Aplicando User Isolation modo 3..." -ForegroundColor Cyan

Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name "ftpServer.userIsolation.mode" -Value 3

$check = (Get-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name "ftpServer.userIsolation.mode").Value
Write-Host "    Valor ahora: $check" -ForegroundColor $(if ($check -eq 3) {"Green"} else {"Red"})

# ============================================================================
# PROBLEMA 2: SeBatchLogonRight - IIS FTP Basic Auth lo requiere
# Agregar TODOS los usuarios de los grupos FTP
# ============================================================================
Write-Host "`n[2/3] Otorgando SeBatchLogonRight a usuarios FTP..." -ForegroundColor Cyan

$exportInf = "$env:TEMP\sec_export.inf"
$applyInf  = "$env:TEMP\sec_apply.inf"
$applyDb   = "$env:TEMP\sec_apply.sdb"

& secedit /export /cfg $exportInf /quiet 2>$null
$cfg = Get-Content $exportInf

# Obtener linea actual de SeBatchLogonRight
$lineaBatch = $cfg | Where-Object { $_ -match "^SeBatchLogonRight" }

# Recolectar todos los usuarios FTP
$grupos   = @("reprobados","recursadores")
$usuarios = @()
foreach ($g in $grupos) {
    $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
    foreach ($m in $miembros) {
        $u = $m.Name -replace ".*\\",""
        $usuarios += $u
        Write-Host "    Procesando usuario: $u" -ForegroundColor Yellow
    }
}

if ($usuarios.Count -eq 0) {
    Write-Host "    AVISO: No hay usuarios en los grupos FTP." -ForegroundColor Yellow
} else {
    # Construir la nueva linea agregando cada usuario
    if ($lineaBatch) {
        $nuevaLinea = $lineaBatch
        foreach ($u in $usuarios) {
            if ($nuevaLinea -notmatch [regex]::Escape($u)) {
                $nuevaLinea = "$nuevaLinea,*$u"
            }
        }
    } else {
        $sids = ($usuarios | ForEach-Object { "*$_" }) -join ","
        $nuevaLinea = "SeBatchLogonRight = $sids"
    }

    $infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
$nuevaLinea
"@
    $infContent | Out-File -FilePath $applyInf -Encoding Unicode
    & secedit /configure /db $applyDb /cfg $applyInf /quiet 2>$null

    Remove-Item $exportInf,$applyInf,$applyDb -ErrorAction SilentlyContinue
    Write-Host "    SeBatchLogonRight aplicado a: $($usuarios -join ', ')" -ForegroundColor Green
}

# ============================================================================
# PROBLEMA 3: Sitio FTP detenido
# ============================================================================
Write-Host "`n[3/3] Iniciando el sitio FTP..." -ForegroundColor Cyan

# Reiniciar servicio para que tome el nuevo isolation mode
Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Service ftpsvc
Start-Sleep -Seconds 2

# Iniciar el sitio
$resultado = & "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site $SITE_NAME 2>&1
Write-Host "    appcmd: $resultado"

Start-Sleep -Seconds 2

# Verificar estado final
$site = Get-Website -Name $SITE_NAME -ErrorAction SilentlyContinue
$color = if ($site.State -eq "Started") {"Green"} else {"Red"}
Write-Host "    Estado del sitio: $($site.State)" -ForegroundColor $color

# ============================================================================
# VERIFICACION FINAL
# ============================================================================
Write-Host "`n============================================" -ForegroundColor Blue
Write-Host "  VERIFICACION FINAL" -ForegroundColor Blue
Write-Host "============================================" -ForegroundColor Blue

$svc      = Get-Service ftpsvc
$site     = Get-Website -Name $SITE_NAME -ErrorAction SilentlyContinue
$isoMode  = (Get-ItemProperty "IIS:\Sites\$SITE_NAME" -Name "ftpServer.userIsolation.mode").Value

Write-Host "  Servicio ftpsvc  : $($svc.Status)"
Write-Host "  Sitio '$SITE_NAME'  : $($site.State)"
Write-Host "  Isolation mode   : $isoMode (debe ser 3)"

if ($svc.Status -eq "Running" -and $site.State -eq "Started" -and $isoMode -eq 3) {
    Write-Host "`n  TODO CORRECTO - Intenta conectarte ahora con FileZilla." -ForegroundColor Green
} else {
    Write-Host "`n  Aun hay algo mal. Revisa los valores de arriba." -ForegroundColor Red
}
Write-Host "============================================" -ForegroundColor Blue