# ============================================================================
# Script de Automatizacion de Servidor FTP - Windows Server
# Administracion de Sistemas - IIS con FTP Service
# ============================================================================

# ============================================================================
# Colores y utilidades
# ============================================================================
function Print-Info   { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Print-Ok     { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Print-Error  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Print-Warn   { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Print-Titulo { param($msg) Write-Host "`n=== $msg ===`n" -ForegroundColor Yellow }

# ============================================================================
# Variables Globales
# ============================================================================
$FTP_ROOT           = "C:\ftp"
$GRUPO_REPROBADOS   = "reprobados"
$GRUPO_RECURSADORES = "recursadores"
$FTP_SITE_NAME      = "ServidorFTP"
$FTP_PORT           = 21

# ============================================================================
# IDENTIDADES POR SID - Independiente del idioma del SO
# S-1-5-32-544 = Administrators / Administradores
# S-1-5-18     = SYSTEM / SISTEMA
# S-1-5-11     = Authenticated Users / Usuarios autenticados
# S-1-5-17     = IUSR (cuenta anonima IIS)
# ============================================================================
function Resolve-SID {
    param([string]$Sid)
    $sidObj = New-Object System.Security.Principal.SecurityIdentifier($Sid)
    return $sidObj.Translate([System.Security.Principal.NTAccount])
}

$ID_ADMINS = Resolve-SID "S-1-5-32-544"
$ID_SYSTEM = Resolve-SID "S-1-5-18"
$ID_AUTH   = Resolve-SID "S-1-5-11"
$ID_IUSR   = Resolve-SID "S-1-5-17"

# ============================================================================
# FUNCION: Crear regla ACL reutilizable
# ============================================================================
function New-ACLRule {
    param(
        [object]$Identity,
        [string]$Rights = "FullControl",
        [string]$Type   = "Allow"
    )
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights,
        "ContainerInherit,ObjectInherit", "None", $Type
    )
}

# ============================================================================
# FUNCION: Aplicar ACL limpia a una carpeta
# ============================================================================
function Set-FolderACL {
    param(
        [string]$Path,
        [System.Security.AccessControl.FileSystemAccessRule[]]$Rules
    )
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in $Rules) {
        $acl.AddAccessRule($rule)
    }
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

    $cfg    = Get-Content $exportInf -ErrorAction SilentlyContinue
    $linea  = $cfg | Where-Object { $_ -match "^SeInteractiveLogonRight" }

    if ($linea -and $linea -match [regex]::Escape($Username)) {
        Print-Info "  '$Username' ya tiene derecho de logon local."
        return
    }

    if ($linea) {
        $nuevaLinea = "$linea,*$Username"
    } else {
        $nuevaLinea = "SeInteractiveLogonRight = *$Username"
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

        $servicio = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
        if ($servicio) {
            $color = if ($servicio.Status -eq "Running") { "Green" } else { "Red" }
            Write-Host "  Servicio FTPSVC : " -NoNewline
            Write-Host "$($servicio.Status)" -ForegroundColor $color
        }

        $regla21 = Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue
        if ($regla21) {
            Print-Ok "  Regla Firewall puerto 21: EXISTE"
        } else {
            Print-Warn "  Regla Firewall puerto 21: NO encontrada"
        }
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
# FUNCION: Crear estructura de directorios base
# ============================================================================
function Crear-Estructura-Base {
    Print-Info "Creando estructura de directorios..."

    $dirs = @(
        $FTP_ROOT,
        "$FTP_ROOT\LocalUser",
        "$FTP_ROOT\LocalUser\Public",
        "$FTP_ROOT\LocalUser\Public\general",
        "$FTP_ROOT\LocalUser\reprobados",
        "$FTP_ROOT\LocalUser\recursadores"
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Print-Ok "Creado: $dir"
        } else {
            Print-Info "Ya existe: $dir"
        }
    }

    Set-FolderACL -Path $FTP_ROOT -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl")
    )

    Set-FolderACL -Path "$FTP_ROOT\LocalUser\Public" -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $ID_IUSR   "ReadAndExecute")
    )

    Set-FolderACL -Path "$FTP_ROOT\LocalUser\Public\general" -Rules @(
        (New-ACLRule $ID_ADMINS "FullControl"),
        (New-ACLRule $ID_SYSTEM "FullControl"),
        (New-ACLRule $ID_AUTH   "Modify"),
        (New-ACLRule $ID_IUSR   "ReadAndExecute")
    )
    Print-Ok "Permisos 'general' configurados."

    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        Set-FolderACL -Path "$FTP_ROOT\LocalUser\$grupo" -Rules @(
            (New-ACLRule $ID_ADMINS "FullControl"),
            (New-ACLRule $ID_SYSTEM "FullControl"),
            (New-ACLRule $grupo     "Modify")
        )
        Print-Ok "Permisos '$grupo' configurados."
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

    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.userIsolation.mode" -Value 3
    Print-Ok "User Isolation activado."

    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name "ftpServer.security.authentication.basicAuthentication.enabled" -Value $true
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" -Value $true
    Print-Ok "Autenticacion configurada."

    $configFile = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
    [xml]$xml   = Get-Content $configFile
    $siteNode   = $xml.configuration.'system.applicationHost'.sites.site |
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
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value "SslAllow"
    Print-Ok "SSL configurado para permitir texto plano."

    Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.ftpServer/firewallSupport" -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.ftpServer/firewallSupport" -Name "highDataChannelPort" -Value 40100
    Print-Ok "Puertos pasivos 40000-40100 configurados."

    Clear-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $FTP_SITE_NAME -ErrorAction SilentlyContinue

    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $FTP_SITE_NAME `
        -Value @{ accessType="Allow"; users="?"; roles=""; permissions=1 } -ErrorAction SilentlyContinue

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
# FUNCION: Construir jaula del usuario con junctions
# ============================================================================
function Construir-Jaula-Usuario {
    param([string]$usuario, [string]$grupo)

    Print-Info "Construyendo jaula FTP para '$usuario'..."

    $jaula    = "$FTP_ROOT\LocalUser\$usuario"
    $personal = "$jaula\$usuario"

    if (-not (Test-Path $jaula))    { New-Item -ItemType Directory -Path $jaula    -Force | Out-Null }
    if (-not (Test-Path $personal)) { New-Item -ItemType Directory -Path $personal -Force | Out-Null }

    $userSID     = (Get-LocalUser -Name $usuario).SID
    $userAccount = $userSID.Translate([System.Security.Principal.NTAccount])

    Set-FolderACL -Path $jaula -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "Modify")
    )

    Set-FolderACL -Path $personal -Rules @(
        (New-ACLRule $ID_ADMINS   "FullControl"),
        (New-ACLRule $ID_SYSTEM   "FullControl"),
        (New-ACLRule $userAccount "Modify")
    )
    Print-Ok "  Carpeta personal: $personal"

    $jGeneral = "$jaula\general"
    if (-not (Test-Path $jGeneral)) {
        cmd /c "mklink /J `"$jGeneral`" `"$FTP_ROOT\LocalUser\Public\general`"" | Out-Null
        Print-Ok "  Junction 'general' creado."
    } else { Print-Info "  Junction 'general' ya existe." }

    $jGrupo = "$jaula\$grupo"
    if (-not (Test-Path $jGrupo)) {
        cmd /c "mklink /J `"$jGrupo`" `"$FTP_ROOT\LocalUser\$grupo`"" | Out-Null
        Print-Ok "  Junction '$grupo' creado."
    } else { Print-Info "  Junction '$grupo' ya existe." }

    Print-Ok "Jaula lista para '$usuario'."
}

# ============================================================================
# FUNCION: Destruir jaula del usuario
# ============================================================================
function Destruir-Jaula-Usuario {
    param([string]$usuario)

    Print-Info "Eliminando jaula de '$usuario'..."
    $jaula = "$FTP_ROOT\LocalUser\$usuario"

    foreach ($junc in @("general", $GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $juncPath = "$jaula\$junc"
        if (Test-Path $juncPath) {
            cmd /c "rmdir `"$juncPath`"" | Out-Null
            Print-Ok "  Junction '$junc' eliminado."
        }
    }

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

    if ([string]::IsNullOrEmpty($usuario)) {
        Print-Error "El nombre no puede estar vacio."; return $false
    }
    if ($usuario.Length -lt 3 -or $usuario.Length -gt 20) {
        Print-Error "El nombre debe tener entre 3 y 20 caracteres."; return $false
    }
    if ($usuario -notmatch '^[a-zA-Z][a-zA-Z0-9_-]*$') {
        Print-Error "Solo letras, numeros, - y _. Debe iniciar con letra."; return $false
    }
    if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
        Print-Error "El usuario '$usuario' ya existe."; return $false
    }
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
    $usuario = (Read-Host "Nombre del usuario a cambiar de grupo").Trim()

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

    Write-Host "  1. $GRUPO_REPROBADOS"   -ForegroundColor Yellow
    Write-Host "  2. $GRUPO_RECURSADORES" -ForegroundColor Yellow
    $opcion = Read-Host "Nuevo grupo [1-2]"

    $nuevoGrupo = switch ($opcion) {
        "1" { $GRUPO_REPROBADOS }
        "2" { $GRUPO_RECURSADORES }
        default { Print-Error "Opcion invalida."; return }
    }

    if ($grupoActual -eq $nuevoGrupo) {
        Print-Info "El usuario ya pertenece a '$nuevoGrupo'."
        return
    }

    if ($grupoActual) {
        Remove-LocalGroupMember -Group $grupoActual -Member $usuario -ErrorAction SilentlyContinue
        Print-Ok "Removido de '$grupoActual'."
    }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario -ErrorAction SilentlyContinue
    Print-Ok "Agregado a '$nuevoGrupo'."

    $jaula = "$FTP_ROOT\LocalUser\$usuario"
    if ($grupoActual) {
        $juncViejo = "$jaula\$grupoActual"
        if (Test-Path $juncViejo) {
            cmd /c "rmdir `"$juncViejo`"" | Out-Null
            Print-Ok "Junction '$grupoActual' eliminado."
        }
    }
    $juncNuevo = "$jaula\$nuevoGrupo"
    if (-not (Test-Path $juncNuevo)) {
        cmd /c "mklink /J `"$juncNuevo`" `"$FTP_ROOT\LocalUser\$nuevoGrupo`"" | Out-Null
        Print-Ok "Junction '$nuevoGrupo' creado."
    }

    Print-Ok "Usuario '$usuario' movido a '$nuevoGrupo'."
    Print-Info "Nueva estructura FTP: /general/ | /$nuevoGrupo/ | /$usuario/"
}

# ============================================================================
# FUNCION: Listar usuarios FTP
# ============================================================================
function Listar-Usuarios-FTP {
    Print-Titulo "Usuarios FTP Configurados"

    $usuarios = @()
    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $miembros = Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue
        foreach ($m in $miembros) {
            $nombre   = $m.Name -replace ".*\\", ""
            $jaulaOk  = Test-Path "$FTP_ROOT\LocalUser\$nombre"
            $usuarios += [PSCustomObject]@{
                Usuario = $nombre
                Grupo   = $grupo
                Jaula   = if ($jaulaOk) { "OK" } else { "FALTA" }
            }
        }
    }

    if ($usuarios.Count -eq 0) { Print-Info "No hay usuarios FTP configurados." ; return }
    $usuarios | Format-Table -AutoSize
}

# ============================================================================
# FUNCION: Instalar FTP (instalacion + configuracion completa)
# ============================================================================
function instalarFtp {
    Print-Titulo "Instalacion y Configuracion de Servidor FTP"

    if (Verificar-Instalacion) {
        $reconf = Read-Host "IIS y FTP ya instalados. Reconfigurar? (s/n)"
        if ($reconf -notmatch '^[Ss]$') { Print-Info "Cancelado." ; return }
    } else {
        Print-Info "Instalando IIS y FTP Service..."
        $result = Install-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service, Web-Mgmt-Console `
            -IncludeManagementTools
        if ($result.Success) { Print-Ok "IIS y FTP instalados." }
        else                 { Print-Error "Error en la instalacion." ; return }
    }

    Import-Module WebAdministration -ErrorAction Stop

    Crear-Grupos
    Crear-Estructura-Base
    Configurar-FTP
    Configurar-Firewall

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1).IPAddress

    Write-Host ""
    Print-Ok "══════════════════════════════════════════"
    Print-Ok "  Servidor FTP listo"
    Print-Ok "══════════════════════════════════════════"
    Print-Info "  IP     : $ip"
    Print-Info "  Puerto : 21"
    Print-Info "  Anon   : ftp://$ip  (solo lectura en /general)"
    Print-Ok "══════════════════════════════════════════"
}

# ============================================================================
# FUNCION: Desinstalar FTP
# ============================================================================
function desinstalarFtp {
    Print-Titulo "Desinstalacion de IIS FTP Server"

    $ftp = Get-WindowsFeature -Name "Web-Ftp-Server" -ErrorAction SilentlyContinue
    if (-not $ftp.Installed) {
        Print-Warn "IIS FTP Server no esta instalado. No hay nada que desinstalar."
        return
    }

    $confirmar = Read-Host "Esto eliminara el servicio FTP. Continuar? (s/n)"
    if ($confirmar -notmatch '^[Ss]$') { Print-Info "Cancelado." ; return }

    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Uninstall-WindowsFeature -Name Web-Ftp-Server

    foreach ($r in @("FTP Puerto 21", "FTP Pasivo 40000-40100")) {
        Remove-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue
    }
    Print-Ok "Desinstalacion completada y reglas de firewall eliminadas."
}

# ============================================================================
# FUNCION: Gestion de usuarios (submenu)
# ============================================================================
function gestionarUsuariosFtp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE USUARIOS FTP           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Crear usuarios"          -ForegroundColor Yellow
    Write-Host "2. Cambiar grupo"           -ForegroundColor Yellow
    Write-Host "3. Eliminar usuario"        -ForegroundColor Yellow
    Write-Host "4. Cambiar contrasena"      -ForegroundColor Yellow
    Write-Host "5. Listar usuarios"         -ForegroundColor Yellow
    Write-Host "6. Volver"                  -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" {
            $num = Read-Host "Cuantos usuarios desea crear?"
            if (-not ($num -match '^\d+$') -or [int]$num -lt 1) {
                Print-Error "Numero invalido." ; return
            }
            for ($i = 1; $i -le [int]$num; $i++) {
                Write-Host ""
                Print-Titulo "Usuario $i de $num"

                do { $usuario = (Read-Host "Nombre de usuario").Trim() } `
                    while (-not (Validar-Usuario -usuario $usuario))

                do { $password = (Read-Host "Contrasena").Trim() } `
                    while ([string]::IsNullOrWhiteSpace($password))

                Write-Host "  1. $GRUPO_REPROBADOS"   -ForegroundColor Yellow
                Write-Host "  2. $GRUPO_RECURSADORES" -ForegroundColor Yellow
                $gOp  = Read-Host "Grupo [1-2]"
                $grupo = switch ($gOp) {
                    "1" { $GRUPO_REPROBADOS }
                    "2" { $GRUPO_RECURSADORES }
                    default { Print-Warn "Opcion invalida, asignando a reprobados." ; $GRUPO_REPROBADOS }
                }
                Crear-Usuario-FTP -usuario $usuario -password $password -grupo $grupo
            }
        }
        "2" { Cambiar-Grupo-Usuario }
        "3" {
            Listar-Usuarios-FTP
            $usuario = (Read-Host "Usuario a eliminar").Trim()
            if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
                Print-Error "Usuario '$usuario' no existe." ; return
            }
            $confirmar = Read-Host "Confirma eliminar '$usuario'? (s/n)"
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
                Print-Error "Usuario '$usuario' no existe." ; return
            }
            $newPass = (Read-Host "Nueva contrasena").Trim()
            $secPass = ConvertTo-SecureString $newPass -AsPlainText -Force
            Set-LocalUser -Name $usuario -Password $secPass
            Print-Ok "Contrasena de '$usuario' actualizada."
        }
        "5" { Listar-Usuarios-FTP }
        "6" { return }
        default { Print-Error "Opcion invalida." }
    }
}

# ============================================================================
# FUNCION: Estado del servidor
# ============================================================================
function monitoreoFtp {
    Print-Titulo "ESTADO DEL SERVIDOR FTP"
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "  Servicio ftpsvc : " -NoNewline
        Write-Host $svc.Status -ForegroundColor $color
    }

    $estado    = & "$env:SystemRoot\System32\inetsrv\appcmd.exe" list site $FTP_SITE_NAME 2>$null
    $isolation = (Get-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name "ftpServer.userIsolation.mode" -ErrorAction SilentlyContinue).Value
    $isoText = switch ($isolation) {
        3       { "IsolateAllDirectories (correcto)" }
        0       { "Sin aislamiento (incorrecto)" }
        default { "Modo $isolation" }
    }

    Write-Host "  Sitio IIS       : $estado"
    Write-Host "  User Isolation  : $isoText"

    Write-Host ""
    Print-Info "Conexiones activas en puerto 21:"
    netstat -an | Select-String ":21 "

    Write-Host ""
    Listar-Usuarios-FTP
}

# ============================================================================
# MENU PRINCIPAL FTP
# ============================================================================
function menuFtp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE SERVICIO FTP           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar instalacion"    -ForegroundColor Yellow
    Write-Host "2. Instalar FTP"             -ForegroundColor Yellow
    Write-Host "3. Desinstalar FTP"          -ForegroundColor Yellow
    Write-Host "4. Gestionar usuarios"       -ForegroundColor Yellow
    Write-Host "5. Monitoreo / Estado"       -ForegroundColor Yellow
    Write-Host "6. Volver al menu principal" -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { Verificar-Instalacion }
        "2" { instalarFtp }
        "3" { desinstalarFtp }
        "4" { gestionarUsuariosFtp }
        "5" { monitoreoFtp }
        "6" { return }
        default { Print-Error "Opcion invalida." }
    }
}