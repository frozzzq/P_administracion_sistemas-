# ============================================================================
# Script de Automatizacion de Servidor FTP - Windows Server 2025
# Administracion de Sistemas - IIS con FTP Service
# ============================================================================
param(
    [switch]$verify,
    [switch]$install,
    [switch]$users,
    [switch]$restart,
    [switch]$status,
    [switch]$list,
    [switch]$help
)

# ============================================================================
# Colores y utilidades
# ============================================================================
function Print-Info   { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Gray }
function Print-Ok     { param($msg) Write-Host "[OK]    $msg" -ForegroundColor DarkYellow }
function Print-Error  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Print-Warn   { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Print-Titulo { param($msg) Write-Host "`n=== $msg ===`n" -ForegroundColor Yellow }

# ============================================================================
# Verificar Administrador
# ============================================================================
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Print-Error "Este script debe ejecutarse como Administrador"
    exit 1
}

# ============================================================================
# Variables Globales
# S-1-5-32-544 = Administrators   S-1-5-18 = SYSTEM
# S-1-5-11     = Authenticated Users   S-1-5-17 = IUSR
# ============================================================================
$FTP_ROOT           = "C:\ftp"
$USERS_ROOT         = "C:\ftp\LocalUser"
$PUB_ROOT           = "C:\ftp\LocalUser\Public"
$GENERAL_DIR        = "C:\ftp\LocalUser\Public\general"
$GRUPO_REPROBADOS   = "reprobados"
$GRUPO_RECURSADORES = "recursadores"
$FTP_SITE_NAME      = "ServidorFTP"
$FTP_PORT           = 21

function Resolve-SID {
    param([string]$Sid)
    return (New-Object System.Security.Principal.SecurityIdentifier($Sid)).Translate([System.Security.Principal.NTAccount])
}

$ID_ADMINS = Resolve-SID "S-1-5-32-544"
$ID_SYSTEM = Resolve-SID "S-1-5-18"
$ID_AUTH   = Resolve-SID "S-1-5-11"
$ID_IUSR   = Resolve-SID "S-1-5-17"

# ============================================================================
# Funciones auxiliares de ACL
# ============================================================================
function New-ACLRule {
    param([object]$Identity, [string]$Rights = "FullControl", [string]$Type = "Allow")
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights, "ContainerInherit,ObjectInherit", "None", $Type
    )
}

function New-ACLRule-DenyDelete {
    param([object]$Identity)
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, [System.Security.AccessControl.FileSystemRights]::Delete,
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
# FUNCION: Otorgar derecho "Log on locally" requerido por IIS FTP
# ============================================================================
function Grant-FTPLogonRight {
    param([string]$Username)
    $exportInf = "$env:TEMP\secedit_export.inf"
    $applyInf  = "$env:TEMP\secedit_apply.inf"
    $applyDb   = "$env:TEMP\secedit_apply.sdb"
    & secedit /export /cfg $exportInf /quiet 2>$null
    $cfg   = Get-Content $exportInf -ErrorAction SilentlyContinue
    $linea = $cfg | Where-Object { $_ -match "^SeInteractiveLogonRight" }
    if ($linea -and $linea -match [regex]::Escape($Username)) {
        Print-Info "  '$Username' ya tiene derecho de logon local."
        return
    }
    $nuevaLinea = if ($linea) { "$linea,*$Username" } else { "SeInteractiveLogonRight = *$Username" }
    @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
$nuevaLinea
"@ | Out-File -FilePath $applyInf -Encoding Unicode
    & secedit /configure /db $applyDb /cfg $applyInf /quiet 2>$null
    Remove-Item $exportInf, $applyInf, $applyDb -ErrorAction SilentlyContinue
    Print-Ok "  Derecho 'Log on locally' otorgado a '$Username'."
}

# ============================================================================
# FUNCION: Verificar instalacion de IIS y FTP
# ============================================================================
function Verificar-Instalacion {
    Print-Info "Verificando instalacion de IIS y FTP..."
    $iis = Get-WindowsFeature -Name "Web-Server"     -ErrorAction SilentlyContinue
    $ftp = Get-WindowsFeature -Name "Web-Ftp-Server" -ErrorAction SilentlyContinue
    if ($iis.Installed -and $ftp.Installed) {
        Print-Ok "IIS y FTP Service instalados."
        return $true
    }
    if (-not $iis.Installed) { Print-Error "IIS (Web-Server) no instalado." }
    if (-not $ftp.Installed) { Print-Error "FTP Service (Web-Ftp-Server) no instalado." }
    return $false
}

# ============================================================================
# FUNCION: Configurar firewall
# ============================================================================
function Configurar-Firewall {
    Print-Info "Configurando firewall..."
    if (-not (Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Puerto 21" `
            -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
        Print-Ok "Puerto 21 abierto."
    } else { Print-Info "Regla puerto 21 ya existe." }

    if (-not (Get-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" `
            -Direction Inbound -Protocol TCP -LocalPort 40000-40100 -Action Allow | Out-Null
        Print-Ok "Puertos pasivos 40000-40100 abiertos."
    } else { Print-Info "Regla puertos pasivos ya existe." }
}

# ============================================================================
# FUNCION: Crear grupos locales
# ============================================================================
function Crear-Grupos {
    Print-Info "Verificando grupos del sistema..."
    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo -Description "Grupo FTP $grupo" | Out-Null
            Print-Ok "Grupo '$grupo' creado."
        } else {
            Print-Info "Grupo '$grupo' ya existe."
        }
    }
}

# ============================================================================
# FUNCION: Aplicar permisos recursivos en carpetas compartidas
# Equivalente a setfacl en Linux: propaga ACLs con herencia a todo el
# contenido existente y a cualquier subcarpeta nueva (cualquier profundidad).
# ============================================================================
function Aplicar-Permisos-Recursivos {
    param([string]$Dir, [object]$Identity, [string]$Grupo)

    Print-Info "  Aplicando permisos recursivos en '$Dir' para '$Grupo'..."

    # Permisos en la carpeta raiz con herencia total
    $acl = Get-Acl $Dir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $denyRule = New-ACLRule-DenyDelete $Identity
    $acl.AddAccessRule($rule)
    $acl.AddAccessRule($denyRule)
    Set-Acl -Path $Dir -AclObject $acl

    # Propagar recursivamente a todo el contenido existente
    Get-ChildItem -Path $Dir -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $itemAcl = Get-Acl $_.FullName
            $ruleRec = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $itemAcl.AddAccessRule($ruleRec)
            Set-Acl -Path $_.FullName -AclObject $itemAcl
        } catch { }
    }

    Print-Ok "  Permisos recursivos (ACL) aplicados en '$Dir' para grupo '$Grupo'."
}

# ============================================================================
# FUNCION: Crear estructura de directorios base
#
# C:\ftp\
# └── LocalUser\
#     ├── Public\          <- home del anonimo
#     │   └── general\     <- carpeta publica compartida
#     ├── reprobados\      <- carpeta compartida del grupo
#     └── recursadores\    <- carpeta compartida del grupo
# ============================================================================
function Crear-Estructura-Base {
    Print-Info "Creando estructura de directorios..."

    $dirs = @(
        $FTP_ROOT, $USERS_ROOT, $PUB_ROOT, $GENERAL_DIR,
        "$FTP_ROOT\LocalUser\$GRUPO_REPROBADOS",
        "$FTP_ROOT\LocalUser\$GRUPO_RECURSADORES"
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Print-Ok "Creado: $dir"
        } else {
            Print-Info "Ya existe: $dir"
        }
    }

    # Raiz FTP: solo admins
    Set-FolderACL -Path $FTP_ROOT -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl")
    )

    # Public: anonimo + usuarios autenticados pueden traversar
    Set-FolderACL -Path $PUB_ROOT -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $ID_IUSR   "ReadAndExecute"),
        (New-ACLRule $ID_AUTH   "ReadAndExecute")
    )

    # general: todos escriben, nadie borra la raiz
    Set-FolderACL -Path $GENERAL_DIR -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $ID_AUTH   "Modify"),
        (New-ACLRule-DenyDelete $ID_AUTH),
        (New-ACLRule $ID_IUSR   "ReadAndExecute")
    )
    Print-Ok "Permisos 'general' configurados (sticky + setgid activos)."

    # Carpetas de grupo
    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $grupoIdentity = New-Object System.Security.Principal.NTAccount($grupo)
        Set-FolderACL -Path "$FTP_ROOT\LocalUser\$grupo" -Rules @(
            (New-ACLRule $ID_ADMINS "FullControl"),
            (New-ACLRule $ID_SYSTEM "FullControl"),
            (New-ACLRule $grupo     "Modify"),
            (New-ACLRule-DenyDelete $grupoIdentity)
        )
        Print-Ok "Permisos '$grupo' configurados."
    }

    # users_root: solo admins
    Set-FolderACL -Path $USERS_ROOT -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl")
    )

    # Aplicar ACLs recursivas para que subcarpetas nuevas hereden permisos
    Aplicar-Permisos-Recursivos -Dir $GENERAL_DIR `
        -Identity $ID_AUTH -Grupo "authenticated users"
    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $grupoIdentity = New-Object System.Security.Principal.NTAccount($grupo)
        Aplicar-Permisos-Recursivos -Dir "$FTP_ROOT\LocalUser\$grupo" `
            -Identity $grupoIdentity -Grupo $grupo
    }

    Print-Ok "Estructura base lista."
}

# ============================================================================
# FUNCION: Configurar sitio FTP en IIS
# ============================================================================
function Configurar-FTP {
    Print-Info "Configurando sitio FTP en IIS..."
    Import-Module WebAdministration -ErrorAction Stop

    if (Get-WebSite -Name $FTP_SITE_NAME -ErrorAction SilentlyContinue) {
        & "$env:SystemRoot\System32\inetsrv\appcmd.exe" stop site $FTP_SITE_NAME 2>$null
        Remove-WebSite -Name $FTP_SITE_NAME
        Print-Info "Sitio anterior eliminado."
    }

    New-WebFtpSite -Name $FTP_SITE_NAME -Port $FTP_PORT -PhysicalPath $FTP_ROOT -Force | Out-Null
    Print-Ok "Sitio '$FTP_SITE_NAME' creado."

    # User Isolation modo 3: cada usuario enjaulado en LocalUser\<username>
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.userIsolation.mode" -Value 3
    Print-Ok "User Isolation activado."

    # Autenticacion basica y anonima
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.security.authentication.basicAuthentication.enabled" -Value $true
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" -Value $true
    Print-Ok "Autenticacion configurada."

    # SSL: permitir texto plano (entorno de laboratorio)
    $configFile = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
    [xml]$xml = Get-Content $configFile
    $siteNode = $xml.configuration.'system.applicationHost'.sites.site |
        Where-Object { $_.name -eq $FTP_SITE_NAME }
    if ($siteNode) {
        $sslNode = $siteNode.ftpServer.security.ssl
        if ($sslNode) {
            $sslNode.SetAttribute("controlChannelPolicy", "SslAllow")
            $sslNode.SetAttribute("dataChannelPolicy",    "SslAllow")
            $sslNode.SetAttribute("serverCertHash",       "")
            $sslNode.SetAttribute("serverCertStoreName",  "")
            $xml.Save($configFile)
        }
    }
    Set-ItemProperty -Path "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslAllow"
    Set-ItemProperty -Path "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value "SslAllow"
    Print-Ok "SSL configurado para permitir texto plano."

    # Puertos pasivos
    Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.ftpServer/firewallSupport" -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.ftpServer/firewallSupport" -Name "highDataChannelPort" -Value 40100
    Print-Ok "Puertos pasivos 40000-40100 configurados."

    # Reglas de autorizacion
    Clear-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $FTP_SITE_NAME -ErrorAction SilentlyContinue
    # Anonimo: solo lectura
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $FTP_SITE_NAME `
        -Value @{ accessType="Allow"; users="?"; roles=""; permissions=1 } -ErrorAction SilentlyContinue
    # Autenticados: lectura y escritura
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $FTP_SITE_NAME `
        -Value @{ accessType="Allow"; users="*"; roles=""; permissions=3 } -ErrorAction SilentlyContinue

    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service ftpsvc
    Start-Sleep -Seconds 2
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site $FTP_SITE_NAME
    $estado = (& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list site $FTP_SITE_NAME)
    Print-Ok "Estado del sitio: $estado"
}

# ============================================================================
# FUNCION: Verificar si una junction existe y apunta a destino real
# Equivalente a esta_montado() con /proc/mounts en Alpine
# ============================================================================
function Esta-Junction {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
    return ($item -and $item.LinkType -eq "Junction")
}

# ============================================================================
# FUNCION: Crear junction (equivalente a mount --bind en Alpine)
# ============================================================================
function Crear-Junction {
    param([string]$Src, [string]$Dst, [object]$UserAccount, [string]$Grupo)

    if (-not (Test-Path $Dst)) {
        New-Item -ItemType Directory -Path $Dst -Force | Out-Null
    }

    if (Esta-Junction $Dst) {
        Print-Info "  Junction ya existe: $Dst"
        return $true
    }

    cmd /c "rmdir `"$Dst`"" 2>$null | Out-Null
    cmd /c "mklink /J `"$Dst`" `"$Src`"" | Out-Null

    if (-not (Esta-Junction $Dst)) {
        Print-Error "  Junction creado pero no verificado: $Dst"
        return $false
    }

    Print-Ok "  Junction: $Dst -> $Src"
    return $true
}

# ============================================================================
# FUNCION: Eliminar junction (equivalente a desmontar_bind en Alpine)
# ============================================================================
function Eliminar-Junction {
    param([string]$Dst)

    if (Esta-Junction $Dst) {
        cmd /c "rmdir `"$Dst`"" | Out-Null
        Print-Ok "  Junction eliminado: $Dst"
    } elseif (Test-Path $Dst) {
        Remove-Item -Path $Dst -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# FUNCION: Construir jaula del usuario con junctions
#
# Estructura visible al usuario:
#   /                    <- C:\ftp\LocalUser\<usuario>\
#   ├── general\         <- junction -> general compartida
#   ├── <grupo>\         <- junction -> carpeta del grupo
#   └── <usuario>\       <- carpeta personal fisica
# ============================================================================
function Construir-Jaula-Usuario {
    param([string]$usuario, [string]$grupo)

    Print-Info "Construyendo jaula FTP para '$usuario'..."
    $jaula    = "$USERS_ROOT\$usuario"
    $personal = "$jaula\$usuario"

    if (-not (Test-Path $jaula))    { New-Item -ItemType Directory -Path $jaula    -Force | Out-Null }
    if (-not (Test-Path $personal)) { New-Item -ItemType Directory -Path $personal -Force | Out-Null }

    $userSID     = (Get-LocalUser -Name $usuario).SID
    $userAccount = $userSID.Translate([System.Security.Principal.NTAccount])

    # Jaula: root no heredable (IIS FTP exige que el home sea de Admins)
    Set-FolderACL -Path $jaula -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "ReadAndExecute")
    )

    # Carpeta personal con permisos recursivos (usuario puede crear subcarpetas)
    Set-FolderACL -Path $personal -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "Modify"),
        (New-ACLRule-DenyDelete $userAccount)
    )
    # ACLs recursivas: cualquier subcarpeta hereda automaticamente
    Get-ChildItem -Path $personal -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $aclRec = Get-Acl $_.FullName
            $ruleRec = New-Object System.Security.AccessControl.FileSystemAccessRule($userAccount, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $aclRec.AddAccessRule($ruleRec)
            Set-Acl -Path $_.FullName -AclObject $aclRec
        } catch { }
    }
    Print-Ok "  Carpeta personal: $personal (permisos recursivos aplicados)"

    # Junction general
    $jGeneral = "$jaula\general"
    Crear-Junction -Src $GENERAL_DIR -Dst $jGeneral -UserAccount $userAccount -Grupo "general"
    Set-FolderACL -Path $jGeneral -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "ReadAndExecute"),
        (New-ACLRule $ID_AUTH     "Modify"),
        (New-ACLRule-DenyDelete $ID_AUTH)
    )
    Print-Ok "  ACL junction 'general' configurada."

    # Junction grupo
    $jGrupo = "$jaula\$grupo"
    Crear-Junction -Src "$FTP_ROOT\LocalUser\$grupo" -Dst $jGrupo -UserAccount $userAccount -Grupo $grupo
    $grupoIdentity = New-Object System.Security.Principal.NTAccount($grupo)
    Set-FolderACL -Path $jGrupo -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "ReadAndExecute"),
        (New-ACLRule $grupo       "Modify"),
        (New-ACLRule-DenyDelete $grupoIdentity)
    )
    Print-Ok "  ACL junction '$grupo' configurada."

    Print-Ok "Jaula lista para '$usuario'."
}

# ============================================================================
# FUNCION: Destruir jaula del usuario
# ============================================================================
function Destruir-Jaula-Usuario {
    param([string]$usuario)

    Print-Info "Eliminando jaula de '$usuario'..."
    $jaula = "$USERS_ROOT\$usuario"

    Eliminar-Junction "$jaula\general"
    Eliminar-Junction "$jaula\$GRUPO_REPROBADOS"
    Eliminar-Junction "$jaula\$GRUPO_RECURSADORES"

    if (Test-Path $jaula) {
        Remove-Item -Path $jaula -Recurse -Force
        Print-Ok "  Carpeta home eliminada."
    }
}

# ============================================================================
# FUNCION: Validar nombre de usuario
# ============================================================================
function Validar-Usuario {
    param([string]$usuario)
    if ([string]::IsNullOrEmpty($usuario))                          { Print-Error "El nombre no puede estar vacio.";                      return $false }
    if ($usuario.Length -lt 3 -or $usuario.Length -gt 20)          { Print-Error "El nombre debe tener entre 3 y 20 caracteres.";        return $false }
    if ($usuario -notmatch '^[a-zA-Z][a-zA-Z0-9_-]*$')             { Print-Error "Solo letras, numeros, - y _. Debe iniciar con letra."; return $false }
    if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) { Print-Error "El usuario '$usuario' ya existe.";                    return $false }
    return $true
}

# ============================================================================
# FUNCION: Crear usuario FTP
# ============================================================================
function Crear-Usuario-FTP {
    param([string]$usuario, [string]$password, [string]$grupo)

    Print-Info "Creando usuario '$usuario' en grupo '$grupo'..."
    $securePass = ConvertTo-SecureString $password -AsPlainText -Force
    try {
        New-LocalUser -Name $usuario -Password $securePass `
            -PasswordNeverExpires -UserMayNotChangePassword `
            -Description "Usuario FTP - $grupo" | Out-Null
        Print-Ok "Usuario del sistema creado."
    } catch {
        Print-Error "Error al crear usuario '$usuario': $_"
        return $false
    }

    Start-Sleep -Seconds 1
    Grant-FTPLogonRight -Username $usuario

    $otroGrupo = if ($grupo -eq $GRUPO_REPROBADOS) { $GRUPO_RECURSADORES } else { $GRUPO_REPROBADOS }
    Remove-LocalGroupMember -Group $otroGrupo -Member $usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $grupo      -Member $usuario -ErrorAction SilentlyContinue
    Print-Ok "Usuario agregado al grupo '$grupo'."

    Construir-Jaula-Usuario -usuario $usuario -grupo $grupo

    Write-Host ""
    Print-Ok "═══════════════════════════════════════════"
    Print-Ok "  Usuario '$usuario' creado correctamente"
    Print-Ok "═══════════════════════════════════════════"
    Print-Info "  Estructura al conectar por FTP:"
    Print-Info "    /general/      (publica, todos leen y escriben)"
    Print-Info "    /$grupo/       (solo tu grupo)"
    Print-Info "    /$usuario/     (personal)"
    Print-Ok "═══════════════════════════════════════════"
    return $true
}

# ============================================================================
# FUNCION: Cambiar usuario de grupo
# ============================================================================
function Cambiar-Grupo-Usuario {
    param([string]$usuario)

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        Print-Error "El usuario '$usuario' no existe."
        return
    }

    $grupoActual = $null
    foreach ($g in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { ($_.Name -replace "^.*\\","") -eq $usuario }) {
            $grupoActual = $g; break
        }
    }

    Print-Info "Grupo actual de '$usuario': $(if ($grupoActual) { $grupoActual } else { '(ninguno)' })"

    Write-Host ""
    Write-Host "  Nuevo grupo:"
    Write-Host "  1) $GRUPO_REPROBADOS"
    Write-Host "  2) $GRUPO_RECURSADORES"
    $opcion = Read-Host "Seleccione [1-2]"

    $nuevoGrupo = switch ($opcion) {
        "1" { $GRUPO_REPROBADOS }
        "2" { $GRUPO_RECURSADORES }
        default { Print-Error "Opcion invalida."; return }
    }

    if ($grupoActual -eq $nuevoGrupo) { Print-Info "El usuario ya pertenece a '$nuevoGrupo'."; return }

    Print-Info "Cambiando '$usuario': '$grupoActual' -> '$nuevoGrupo'..."

    $jaula = "$USERS_ROOT\$usuario"

    # Si la jaula no existe, reconstruirla desde cero
    if (-not (Test-Path $jaula)) {
        Print-Warn "Jaula no encontrada, reconstruyendo desde cero..."
        New-Item -ItemType Directory -Path $jaula -Force | Out-Null
        New-Item -ItemType Directory -Path "$jaula\$usuario" -Force | Out-Null
        $userSID     = (Get-LocalUser -Name $usuario).SID
        $userAccount = $userSID.Translate([System.Security.Principal.NTAccount])
        Set-FolderACL -Path $jaula -Rules @(
            (New-ACLRule $ID_ADMINS "FullControl"), (New-ACLRule $ID_SYSTEM "FullControl"),
            (New-ACLRule $userAccount "ReadAndExecute")
        )
        Crear-Junction -Src $GENERAL_DIR -Dst "$jaula\general" -UserAccount $userAccount -Grupo "general"
    }

    # Detener FTP ANTES de tocar junctions
    Print-Warn "Deteniendo servicio FTP para liberar junctions..."
    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Eliminar AMBOS grupos para limpiar estado inconsistente
    Eliminar-Junction "$jaula\$GRUPO_REPROBADOS"
    Eliminar-Junction "$jaula\$GRUPO_RECURSADORES"

    # Cambiar grupo del sistema
    if ($grupoActual) {
        Remove-LocalGroupMember -Group $grupoActual -Member $usuario -ErrorAction SilentlyContinue
        Print-Ok "Removido de '$grupoActual'."
    }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario -ErrorAction SilentlyContinue
    Print-Ok "Agregado a '$nuevoGrupo'."

    # Re-aplicar permisos en la carpeta real del grupo destino
    $grupoIdentity = New-Object System.Security.Principal.NTAccount($nuevoGrupo)
    Set-FolderACL -Path "$FTP_ROOT\LocalUser\$nuevoGrupo" -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $nuevoGrupo "Modify"),
        (New-ACLRule-DenyDelete $grupoIdentity)
    )
    Aplicar-Permisos-Recursivos -Dir "$FTP_ROOT\LocalUser\$nuevoGrupo" `
        -Identity $grupoIdentity -Grupo $nuevoGrupo
    Print-Ok "Permisos verificados en '$FTP_ROOT\LocalUser\$nuevoGrupo'."

    # Crear junction del nuevo grupo
    $userSID     = (Get-LocalUser -Name $usuario).SID
    $userAccount = $userSID.Translate([System.Security.Principal.NTAccount])
    $jNuevo = "$jaula\$nuevoGrupo"
    if (Crear-Junction -Src "$FTP_ROOT\LocalUser\$nuevoGrupo" -Dst $jNuevo -UserAccount $userAccount -Grupo $nuevoGrupo) {
        Set-FolderACL -Path $jNuevo -Rules @(
            (New-ACLRule $ID_ADMINS   "FullControl"),
            (New-ACLRule $ID_SYSTEM   "FullControl"),
            (New-ACLRule $userAccount "ReadAndExecute"),
            (New-ACLRule $nuevoGrupo  "Modify"),
            (New-ACLRule-DenyDelete $grupoIdentity)
        )
        Print-Ok "Junction '$nuevoGrupo' creado correctamente."
    } else {
        Print-Error "Error al crear junction. Verifica que corres el script como Administrador."
    }

    # Garantizar permisos correctos de la jaula (IIS FTP exige Admins en home)
    Set-FolderACL -Path $jaula -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "ReadAndExecute")
    )

    # Arrancar FTP de nuevo
    Start-Service ftpsvc
    Start-Sleep -Seconds 2
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site $FTP_SITE_NAME | Out-Null

    if ((Get-Service ftpsvc).Status -eq "Running") {
        Print-Ok "Servicio FTP reiniciado correctamente."
    } else {
        Print-Error "FTP no arranco. Revisa el Visor de Eventos."
    }

    Print-Ok "Usuario '$usuario' movido a '$nuevoGrupo'."
    Print-Info "Nueva estructura FTP:"
    Print-Info "  /general/         (publica)"
    Print-Info "  /$nuevoGrupo/     (nuevo grupo)"
    Print-Info "  /$usuario/        (personal)"
    Print-Warn "El usuario debe reconectarse en FileZilla."
}

# ============================================================================
# FUNCION: Instalar y configurar servidor FTP completo
# ============================================================================
function Instalar-FTP {
    Print-Titulo "Instalacion y Configuracion de Servidor FTP"

    if (Verificar-Instalacion) {
        $reconf = Read-Host "IIS y FTP ya instalados. Reconfigurar? [s/N]"
        if ($reconf -notmatch '^[Ss]$') { Print-Info "Cancelado."; return }
    } else {
        Print-Info "Instalando IIS y FTP Service..."
        $result = Install-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service, Web-Mgmt-Console `
            -IncludeManagementTools
        if ($result.Success) { Print-Ok "IIS y FTP instalados." }
        else { Print-Error "Error en la instalacion."; return }
    }

    Import-Module WebAdministration -ErrorAction Stop

    Crear-Grupos
    Crear-Estructura-Base
    Configurar-FTP
    Configurar-Firewall

    Set-Service -Name ftpsvc -StartupType Automatic

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1).IPAddress

    Write-Host ""
    Print-Ok "══════════════════════════════════════════════"
    Print-Ok "  Servidor FTP listo"
    Print-Ok "══════════════════════════════════════════════"
    Print-Info "  IP     : $ip"
    Print-Info "  Puerto : 21"
    Print-Info "  Anon   : ftp://$ip  (solo lectura en /general)"
    Print-Ok "══════════════════════════════════════════════"
    Print-Info "Cree usuarios con: .\ftp_server.ps1 -users"
}

# ============================================================================
# FUNCION: Listar usuarios FTP
# ============================================================================
function Listar-Usuarios-FTP {
    Print-Titulo "Usuarios FTP Configurados"

    $encontrados = 0
    Write-Host ("{0,-20} {1,-15} {2,-10}" -f "Usuario", "Grupo", "Jaula") -ForegroundColor Gray
    Write-Host ("{0,-20} {1,-15} {2,-10}" -f "-------", "-----", "-----")

    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $miembros = Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue
        foreach ($m in $miembros) {
            $nombre  = $m.Name -replace ".*\\", ""
            $jaulaOk = Test-Path "$USERS_ROOT\$nombre"
            $jaula   = if ($jaulaOk) { "OK" } else { "FALTA" }
            $color   = if ($jaulaOk) { "DarkYellow" } else { "Red" }
            Write-Host ("{0,-20} {1,-15} " -f $nombre, $grupo) -NoNewline
            Write-Host $jaula -ForegroundColor $color
            $encontrados++
        }
    }

    if ($encontrados -eq 0) { Print-Info "No hay usuarios FTP configurados." }
}

# ============================================================================
# FUNCION: Gestionar usuarios FTP
# ============================================================================
function Gestionar-Usuarios {
    Print-Titulo "Gestion de Usuarios FTP"

    if (-not (Verificar-Instalacion)) {
        Print-Error "IIS/FTP no instalado. Ejecute: .\ftp_server.ps1 -install"
        return
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    Write-Host "  1) Crear nuevos usuarios"
    Write-Host "  2) Cambiar grupo de un usuario"
    Write-Host "  3) Eliminar usuario"
    Write-Host "  4) Cambiar contrasena de usuario"
    Write-Host "  5) Volver"
    Write-Host ""
    $opcion = Read-Host "Seleccione [1-5]"

    switch ($opcion) {
        "1" {
            $num = Read-Host "Cuantos usuarios desea crear?"
            if (-not ($num -match '^\d+$') -or [int]$num -lt 1) { Print-Error "Numero invalido."; return }

            for ($i = 1; $i -le [int]$num; $i++) {
                Write-Host ""
                Print-Titulo "Usuario $i de $num"

                $usuario = ""
                do {
                    $usuario = (Read-Host "Nombre de usuario").Trim()
                } while (-not (Validar-Usuario -usuario $usuario))

                $password = ""
                do {
                    $password = (Read-Host "Contrasena (min 8 caracteres, una mayuscula, un numero y un caracter especial)").Trim()
                } while ([string]::IsNullOrWhiteSpace($password))

                Write-Host "  1) $GRUPO_REPROBADOS"
                Write-Host "  2) $GRUPO_RECURSADORES"
                $gOp = Read-Host "Grupo [1-2]"
                $grupo = switch ($gOp) {
                    "1" { $GRUPO_REPROBADOS }
                    "2" { $GRUPO_RECURSADORES }
                    default { Print-Warn "Opcion invalida, asignando a reprobados."; $GRUPO_REPROBADOS }
                }
                Crear-Usuario-FTP -usuario $usuario -password $password -grupo $grupo
            }
        }
        "2" {
            Listar-Usuarios-FTP
            $usuario = (Read-Host "Usuario a cambiar de grupo").Trim()
            Cambiar-Grupo-Usuario -usuario $usuario
        }
        "3" {
            Listar-Usuarios-FTP
            $usuario = (Read-Host "Usuario a eliminar").Trim()
            if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
                Print-Error "Usuario '$usuario' no existe."; return
            }
            $confirmar = Read-Host "Confirma eliminar '$usuario'? [s/N]"
            if ($confirmar -match '^[Ss]$') {
                Destruir-Jaula-Usuario -usuario $usuario
                Remove-LocalUser -Name $usuario -ErrorAction SilentlyContinue
                Print-Ok "Usuario '$usuario' eliminado."
            } else { Print-Info "Cancelado." }
        }
        "4" {
            Listar-Usuarios-FTP
            $usuario = (Read-Host "Nombre del usuario").Trim()
            if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
                Print-Error "Usuario '$usuario' no existe."; return
            }
            $newPass = (Read-Host "Nueva contrasena").Trim()
            $secPass = ConvertTo-SecureString $newPass -AsPlainText -Force
            Set-LocalUser -Name $usuario -Password $secPass
            Print-Ok "Contrasena de '$usuario' actualizada."
        }
        "5" { return }
        default { Print-Error "Opcion invalida." }
    }
}

# ============================================================================
# FUNCION: Ver estado del servidor
# ============================================================================
function Ver-Estado {
    Print-Titulo "ESTADO DEL SERVIDOR FTP"
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  Servicio ftpsvc : " -NoNewline
        $color = if ($svc.Status -eq "Running") { "DarkYellow" } else { "Red" }
        Write-Host $svc.Status -ForegroundColor $color
    }

    $puerto = netstat -an | Select-String ":21 " | Select-Object -First 1
    Write-Host "  Puerto 21       : " -NoNewline
    if ($puerto) { Write-Host "Escuchando" -ForegroundColor DarkYellow }
    else         { Write-Host "No escuchando" -ForegroundColor Red }

    $estado = & "$env:SystemRoot\System32\inetsrv\appcmd.exe" list site $FTP_SITE_NAME 2>$null
    Write-Host "  Sitio IIS       : $estado"

    $isolation = (Get-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name "ftpServer.userIsolation.mode" -ErrorAction SilentlyContinue).Value
    $isoText = switch ($isolation) {
        3 { "IsolateAllDirectories (correcto)" }
        0 { "Sin aislamiento (incorrecto)" }
        default { "Modo $isolation" }
    }
    Write-Host "  User Isolation  : $isoText"

    Write-Host ""
    Print-Info "Conexiones activas en puerto 21:"
    netstat -an | Select-String ":21 "

    Write-Host ""
    Listar-Usuarios-FTP
}

# ============================================================================
# FUNCION: Reiniciar FTP
# ============================================================================
function Reiniciar-FTP {
    Print-Info "Reiniciando servidor FTP..."
    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service ftpsvc
    Start-Sleep -Seconds 2
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site $FTP_SITE_NAME
    Print-Ok "Servidor FTP reiniciado."
}

# ============================================================================
# FUNCION: Mostrar ayuda
# ============================================================================
function Mostrar-Ayuda {
    Write-Host ""
    Write-Host "Uso: .\ftp_server.ps1 [opcion]" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -install   Instala y configura el servidor FTP (primera vez)"
    Write-Host "  -users     Gestionar usuarios (crear, cambiar grupo, eliminar)"
    Write-Host "  -status    Ver estado del servidor y usuarios"
    Write-Host "  -restart   Reiniciar el servicio FTP"
    Write-Host "  -verify    Verificar si IIS y FTP estan instalados"
    Write-Host "  -list      Listar usuarios y estructura"
    Write-Host "  -help      Mostrar esta ayuda"
    Write-Host ""
    Write-Host "Orden recomendado (primera vez):" -ForegroundColor Yellow
    Write-Host "  1. .\ftp_server.ps1 -install"
    Write-Host "  2. .\ftp_server.ps1 -users"
    Write-Host ""
}

# ============================================================================
# ENTRY POINT
# ============================================================================
if     ($verify)  { Verificar-Instalacion }
elseif ($install) { Instalar-FTP }
elseif ($users)   { Gestionar-Usuarios }
elseif ($restart) { Reiniciar-FTP }
elseif ($status)  { Ver-Estado }
elseif ($list)    { Listar-Usuarios-FTP }
elseif ($help)    { Mostrar-Ayuda }
else              { Mostrar-Ayuda }