# ============================================================================
# fix_ftp_530.ps1
# Corrige el error "530 - home directory inaccessible" en IIS FTP
# Ejecutar como Administrador en el servidor
# ============================================================================

$FTP_ROOT = "C:\ftp"

# Resolver cuentas por SID (independiente del idioma del SO)
function Resolve-SID {
    param([string]$Sid)
    $sidObj = New-Object System.Security.Principal.SecurityIdentifier($Sid)
    return $sidObj.Translate([System.Security.Principal.NTAccount])
}

$ID_ADMINS   = Resolve-SID "S-1-5-32-544"   # Administrators
$ID_SYSTEM   = Resolve-SID "S-1-5-18"        # SYSTEM
$ID_AUTH     = Resolve-SID "S-1-5-11"        # Authenticated Users
$ID_IUSR     = Resolve-SID "S-1-5-17"        # IUSR  (anonimo IIS)
$ID_IISUSR   = Resolve-SID "S-1-5-32-568"   # IIS_IUSRS (workers IIS)

function New-ACLRule {
    param([object]$Identity, [string]$Rights = "FullControl", [string]$Type = "Allow")
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights,
        "ContainerInherit,ObjectInherit", "None", $Type
    )
}

function New-ACLRule-DenyDelete {
    param([object]$Identity)
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity,
        [System.Security.AccessControl.FileSystemRights]::Delete,
        "None", "None", "Deny"
    )
}

function Set-FolderACL {
    param([string]$Path, [System.Security.AccessControl.FileSystemAccessRule[]]$Rules)
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in $Rules) { $acl.AddAccessRule($rule) }
    Set-Acl -Path $Path -AclObject $acl
}

# ============================================================================
# PASO 1: Reparar permisos de la carpeta raiz LocalUser
# IIS_IUSRS necesita ReadAndExecute aqui para enrutar a cada usuario
# ============================================================================
Write-Host "`n[1/4] Reparando permisos de C:\ftp y LocalUser..." -ForegroundColor Cyan

Set-FolderACL -Path $FTP_ROOT -Rules @(
    (New-ACLRule $ID_ADMINS  "FullControl"),
    (New-ACLRule $ID_SYSTEM  "FullControl"),
    (New-ACLRule $ID_IISUSR  "ReadAndExecute"),
    (New-ACLRule $ID_IUSR    "ReadAndExecute")
)
Write-Host "  C:\ftp OK" -ForegroundColor Green

Set-FolderACL -Path "$FTP_ROOT\LocalUser" -Rules @(
    (New-ACLRule $ID_ADMINS  "FullControl"),
    (New-ACLRule $ID_SYSTEM  "FullControl"),
    (New-ACLRule $ID_IISUSR  "ReadAndExecute"),
    (New-ACLRule $ID_IUSR    "ReadAndExecute")
)
Write-Host "  C:\ftp\LocalUser OK" -ForegroundColor Green

# ============================================================================
# PASO 2: Reparar permisos de cada jaula de usuario existente
# ============================================================================
Write-Host "`n[2/4] Reparando jaulas de usuarios..." -ForegroundColor Cyan

$grupos = @("reprobados", "recursadores")
$usuariosReparados = 0

foreach ($grupo in $grupos) {
    $miembros = Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue
    foreach ($m in $miembros) {
        $usuario = $m.Name -replace ".*\\", ""
        $jaula   = "$FTP_ROOT\LocalUser\$usuario"

        if (-not (Test-Path $jaula)) {
            Write-Host "  [AVISO] Jaula no encontrada para '$usuario': $jaula" -ForegroundColor Yellow
            # Recrear la jaula si no existe
            New-Item -ItemType Directory -Path $jaula -Force | Out-Null
            $personal = "$jaula\$usuario"
            New-Item -ItemType Directory -Path $personal -Force | Out-Null

            # Junctions
            $jGeneral = "$jaula\general"
            if (-not (Test-Path $jGeneral)) {
                cmd /c "mklink /J `"$jGeneral`" `"$FTP_ROOT\LocalUser\Public\general`"" | Out-Null
            }
            $jGrupo = "$jaula\$grupo"
            if (-not (Test-Path $jGrupo)) {
                cmd /c "mklink /J `"$jGrupo`" `"$FTP_ROOT\LocalUser\$grupo`"" | Out-Null
            }
            Write-Host "  Jaula recreada para '$usuario'." -ForegroundColor Yellow
        }

        # Obtener cuenta del usuario por SID
        try {
            $userSID     = (Get-LocalUser -Name $usuario).SID
            $userAccount = $userSID.Translate([System.Security.Principal.NTAccount])
        } catch {
            Write-Host "  [ERROR] No se pudo resolver cuenta de '$usuario'" -ForegroundColor Red
            continue
        }

        # Permisos del home del usuario:
        # IIS_IUSRS necesita ReadAndExecute para que IIS pueda ingresar a la jaula
        # El usuario necesita ReadAndExecute sobre su home (la raiz de la jaula)
        Set-FolderACL -Path $jaula -Rules @(
            (New-ACLRule $ID_ADMINS   "FullControl"),
            (New-ACLRule $ID_SYSTEM   "FullControl"),
            (New-ACLRule $ID_IISUSR   "ReadAndExecute"),
            (New-ACLRule $userAccount "ReadAndExecute")
        )

        # Permisos carpeta personal (dentro de la jaula)
        $personal = "$jaula\$usuario"
        if (Test-Path $personal) {
            Set-FolderACL -Path $personal -Rules @(
                (New-ACLRule $ID_ADMINS   "FullControl"),
                (New-ACLRule $ID_SYSTEM   "FullControl"),
                (New-ACLRule $ID_IISUSR   "ReadAndExecute"),
                (New-ACLRule $userAccount "Modify"),
                (New-ACLRule-DenyDelete    $userAccount)
            )
        }

        Write-Host "  Jaula de '$usuario' ($grupo) reparada." -ForegroundColor Green
        $usuariosReparados++
    }
}

if ($usuariosReparados -eq 0) {
    Write-Host "  No se encontraron usuarios en los grupos FTP." -ForegroundColor Yellow
}

# ============================================================================
# PASO 3: Reparar permisos carpetas general y de grupo
# ============================================================================
Write-Host "`n[3/4] Reparando permisos de carpetas compartidas..." -ForegroundColor Cyan

# Public (home del anonimo)
Set-FolderACL -Path "$FTP_ROOT\LocalUser\Public" -Rules @(
    (New-ACLRule $ID_ADMINS  "FullControl"),
    (New-ACLRule $ID_SYSTEM  "FullControl"),
    (New-ACLRule $ID_IISUSR  "ReadAndExecute"),
    (New-ACLRule $ID_IUSR    "ReadAndExecute")
)
Write-Host "  LocalUser\Public OK" -ForegroundColor Green

# general (dentro de Public)
if (Test-Path "$FTP_ROOT\LocalUser\Public\general") {
    Set-FolderACL -Path "$FTP_ROOT\LocalUser\Public\general" -Rules @(
        (New-ACLRule $ID_ADMINS  "FullControl"),
        (New-ACLRule $ID_SYSTEM  "FullControl"),
        (New-ACLRule $ID_IISUSR  "ReadAndExecute"),
        (New-ACLRule $ID_AUTH    "Modify"),
        (New-ACLRule-DenyDelete   $ID_AUTH),
        (New-ACLRule $ID_IUSR    "ReadAndExecute")
    )
    Write-Host "  general OK" -ForegroundColor Green
}

# Carpetas de grupo
foreach ($grupo in $grupos) {
    $carpetaGrupo = "$FTP_ROOT\LocalUser\$grupo"
    if (Test-Path $carpetaGrupo) {
        $grupoIdentity = New-Object System.Security.Principal.NTAccount($grupo)
        Set-FolderACL -Path $carpetaGrupo -Rules @(
            (New-ACLRule $ID_ADMINS    "FullControl"),
            (New-ACLRule $ID_SYSTEM    "FullControl"),
            (New-ACLRule $ID_IISUSR    "ReadAndExecute"),
            (New-ACLRule $grupoIdentity "Modify"),
            (New-ACLRule-DenyDelete     $grupoIdentity)
        )
        Write-Host "  $grupo OK" -ForegroundColor Green
    }
}

# ============================================================================
# PASO 4: Reiniciar servicio FTP para aplicar todo
# ============================================================================
Write-Host "`n[4/4] Reiniciando servicio FTP..." -ForegroundColor Cyan

Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Service ftpsvc
Start-Sleep -Seconds 2

$svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
$color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
Write-Host "  Estado ftpsvc: $($svc.Status)" -ForegroundColor $color

& "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site "ServidorFTP" 2>$null

# ============================================================================
# RESUMEN
# ============================================================================
Write-Host "`n============================================" -ForegroundColor Blue
Write-Host "  Reparacion completada" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Blue
Write-Host "  Usuarios reparados : $usuariosReparados"
Write-Host "  Ahora intenta conectarte de nuevo con FileZilla."
Write-Host "  Si el error persiste ejecuta: Ver-Estado para revisar el sitio."
Write-Host "============================================" -ForegroundColor Blue