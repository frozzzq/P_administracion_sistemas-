# =============================================
#   GESTION DE SERVICIO FTP - IIS Windows Server
# =============================================

$ftpRoot     = "C:\FTP"
$ftpSiteName = "FTPSite"
$ftpPort     = 21
$grupos      = @("reprobados", "recursadores")

# -----------------------------------------------
function verificarInstalacionFtp {
    Write-Host "`n--- Verificando instalacion de IIS FTP ---" -ForegroundColor Cyan

    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service")
    foreach ($f in $features) {
        $feat   = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        $color  = if ($feat.Installed) { "Green" } else { "Red" }
        $estado = if ($feat.Installed) { "INSTALADO" } else { "NO instalado" }
        Write-Host "  $f : $estado" -ForegroundColor $color
    }

    $svc = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host "  Servicio FTPSVC : $($svc.Status)" -ForegroundColor $color
        Write-Host "  Tipo de inicio  : $($svc.StartType)"
    } else {
        Write-Host "  Servicio FTPSVC : No encontrado" -ForegroundColor Red
    }

    $regla = Get-NetFirewallRule -Name "FTP-Puerto21" -ErrorAction SilentlyContinue
    if ($regla) {
        Write-Host "  Regla Firewall  : EXISTE (puerto 21 abierto)" -ForegroundColor Green
    } else {
        Write-Host "  Regla Firewall  : No configurada" -ForegroundColor Yellow
    }
}

# -----------------------------------------------
function instalarFtp {
    Write-Host "`n--- Instalando IIS + FTP Service ---" -ForegroundColor Cyan

    $features  = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service")
    $toInstall = $features | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }

    if ($toInstall.Count -eq 0) {
        Write-Host "Todos los componentes FTP ya estan instalados." -ForegroundColor Green
        return
    }

    Write-Host "Instalando: $($toInstall -join ', ')..." -ForegroundColor Yellow
    try {
        $res = Install-WindowsFeature -Name $toInstall -IncludeManagementTools
        if ($res.Success) {
            Write-Host "Instalacion completada con exito." -ForegroundColor Green
            if ($res.RestartNeeded -eq "Yes") {
                Write-Host "ADVERTENCIA: Se requiere reinicio para completar la instalacion." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Error durante la instalacion: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# -----------------------------------------------
function desinstalarFtp {
    Write-Host "`n--- Desinstalando IIS FTP ---" -ForegroundColor Magenta

    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) {
            Stop-Website  -Name $ftpSiteName -ErrorAction SilentlyContinue
            Remove-Website -Name $ftpSiteName
            Write-Host "Sitio FTP '$ftpSiteName' eliminado." -ForegroundColor Green
        }
        Stop-Service -Name FTPSVC -Force -ErrorAction SilentlyContinue
        $res = Uninstall-WindowsFeature -Name Web-Ftp-Service, Web-Ftp-Server
        if ($res.Success) {
            Write-Host "Desinstalacion completada." -ForegroundColor Green
        }
        $regla = Get-NetFirewallRule -Name "FTP-Puerto21" -ErrorAction SilentlyContinue
        if ($regla) {
            Remove-NetFirewallRule -Name "FTP-Puerto21"
            Write-Host "Regla de Firewall eliminada." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# -----------------------------------------------
function crearEstructuraBase {
    Write-Host "  Creando estructura base de directorios..." -ForegroundColor Yellow

    # Carpetas principales del servidor FTP
    $carpetas = @(
        "$ftpRoot\general",
        "$ftpRoot\groups\reprobados",
        "$ftpRoot\groups\recursadores",
        "$ftpRoot\users",
        "$ftpRoot\LocalUser\Public"
    )
    foreach ($c in $carpetas) {
        if (-not (Test-Path $c)) {
            New-Item -ItemType Directory -Path $c -Force | Out-Null
        }
    }

    # Acceso anonimo: LocalUser\Public contiene solo un enlace a "general"
    $juncPublic = "$ftpRoot\LocalUser\Public\general"
    if (-not (Test-Path $juncPublic)) {
        New-Item -ItemType Junction -Path $juncPublic -Target "$ftpRoot\general" | Out-Null
    }

    # Crear grupos locales de Windows
    foreach ($g in $grupos) {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $g -Description "Grupo FTP $g" | Out-Null
            Write-Host "  Grupo local '$g' creado." -ForegroundColor Green
        }
    }

    # Permisos NTFS: carpeta general
    # IUSR (anonimo) = solo lectura | Usuarios autenticados = Modificar
    icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)R"               /T /Q | Out-Null
    icacls "$ftpRoot\general" /grant "Authenticated Users:(OI)(CI)M" /T /Q | Out-Null

    # Permisos NTFS: carpetas de grupo -> solo el grupo correspondiente tiene acceso
    foreach ($g in $grupos) {
        icacls "$ftpRoot\groups\$g" /inheritance:r                    /Q | Out-Null
        icacls "$ftpRoot\groups\$g" /grant "Administrators:(OI)(CI)F" /Q | Out-Null
        icacls "$ftpRoot\groups\$g" /grant "${g}:(OI)(CI)M"        /T /Q | Out-Null
    }

    # IIS/FTP necesita acceso de lectura sobre LocalUser para enrutar usuarios
    icacls "$ftpRoot\LocalUser" /grant "IUSR:(OI)(CI)R" /T /Q | Out-Null

    Write-Host "  Estructura base lista." -ForegroundColor Green
}

# -----------------------------------------------
function configurarFtp {
    Write-Host "`n--- Configurando sitio FTP en IIS ---" -ForegroundColor Cyan

    if (-not (Get-WindowsFeature -Name Web-Ftp-Service).Installed) {
        Write-Host "Error: IIS FTP no esta instalado. Use la opcion Instalar primero." -ForegroundColor Red
        return
    }

    Import-Module WebAdministration

    # Paso 1: estructura de carpetas y permisos base
    crearEstructuraBase

    # Paso 2: crear sitio FTP
    if (-not (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name $ftpSiteName -Port $ftpPort -PhysicalPath $ftpRoot -Force
        Write-Host "Sitio FTP '$ftpSiteName' creado en puerto $ftpPort." -ForegroundColor Green
    } else {
        Write-Host "Sitio FTP '$ftpSiteName' ya existe." -ForegroundColor Yellow
    }

    # Paso 3: habilitar autenticacion anonima y basica
    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authentication/anonymousAuthentication" `
        -Name "enabled" -Value $true `
        -PSPath "IIS:\" -Location $ftpSiteName

    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authentication/basicAuthentication" `
        -Name "enabled" -Value $true `
        -PSPath "IIS:\" -Location $ftpSiteName

    # Paso 4: SSL permitido pero no requerido (entorno de laboratorio)
    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/security/ssl" `
        -Name "controlChannelPolicy" -Value "SslAllow" `
        -PSPath "IIS:\" -Location $ftpSiteName
    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/security/ssl" `
        -Name "dataChannelPolicy" -Value "SslAllow" `
        -PSPath "IIS:\" -Location $ftpSiteName

    # Paso 5: aislamiento de usuarios (cada usuario ve solo su carpeta raiz)
    # Valor correcto del enum: IsolateRootDirectoryOnly
    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='$ftpSiteName']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateRootDirectoryOnly" `
        -PSPath "IIS:\"

    # Paso 6: reglas de autorizacion FTP
    try {
        Clear-WebConfiguration `
            -Filter "/system.ftpServer/security/authorization" `
            -PSPath "IIS:\Sites\$ftpSiteName" -ErrorAction SilentlyContinue
    } catch {}

    # Anonimo (?): solo lectura
    Add-WebConfiguration `
        -Filter "/system.ftpServer/security/authorization" `
        -Value @{accessType="Allow"; users="?"; permissions="Read"} `
        -PSPath "IIS:\Sites\$ftpSiteName"

    # Usuarios autenticados (*): lectura y escritura
    Add-WebConfiguration `
        -Filter "/system.ftpServer/security/authorization" `
        -Value @{accessType="Allow"; users="*"; permissions="Read,Write"} `
        -PSPath "IIS:\Sites\$ftpSiteName"

    # Paso 7: iniciar sitio y servicio
    Start-Website -Name $ftpSiteName -ErrorAction SilentlyContinue
    Set-Service   -Name FTPSVC -StartupType Automatic
    Start-Service -Name FTPSVC -ErrorAction SilentlyContinue

    # Paso 8: regla de firewall para puerto 21
    if (-not (Get-NetFirewallRule -Name "FTP-Puerto21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "FTP-Puerto21" -DisplayName "FTP Puerto 21" `
            -Protocol TCP -LocalPort 21 -Action Allow -Direction Inbound | Out-Null
        Write-Host "Regla de firewall puerto 21 creada." -ForegroundColor Green
    }

    Write-Host "Configuracion FTP completada correctamente." -ForegroundColor Green
}

# -----------------------------------------------
function crearUsuarioFtp {
    param(
        [string]$nombreUsuario,
        [string]$password,
        [string]$grupo
    )

    # Crear usuario local de Windows
    if (-not (Get-LocalUser -Name $nombreUsuario -ErrorAction SilentlyContinue)) {
        $securePass = ConvertTo-SecureString $password -AsPlainText -Force
        New-LocalUser -Name $nombreUsuario -Password $securePass `
            -PasswordNeverExpires $true -UserMayNotChangePassword $false | Out-Null
        Write-Host "  Usuario '$nombreUsuario' creado." -ForegroundColor Green
    } else {
        Write-Host "  Usuario '$nombreUsuario' ya existe." -ForegroundColor Yellow
    }

    # Quitar de ambos grupos antes de asignar (idempotente)
    foreach ($g in $grupos) {
        try { Remove-LocalGroupMember -Group $g -Member $nombreUsuario -ErrorAction SilentlyContinue } catch {}
    }

    # Agregar al grupo correspondiente
    Add-LocalGroupMember -Group $grupo -Member $nombreUsuario
    Write-Host "  Asignado al grupo '$grupo'." -ForegroundColor Green

    # Crear carpeta personal del usuario
    $carpetaPersonal = "$ftpRoot\users\$nombreUsuario"
    if (-not (Test-Path $carpetaPersonal)) {
        New-Item -ItemType Directory -Path $carpetaPersonal -Force | Out-Null
    }
    # Solo el propio usuario tiene acceso a su carpeta personal
    icacls $carpetaPersonal /inheritance:r                            /Q | Out-Null
    icacls $carpetaPersonal /grant "Administrators:(OI)(CI)F"         /Q | Out-Null
    icacls $carpetaPersonal /grant "${nombreUsuario}:(OI)(CI)M"    /T /Q | Out-Null

    # Preparar directorio aislado: FTPRoot\LocalUser\nombreUsuario
    $userIsoDir = "$ftpRoot\LocalUser\$nombreUsuario"
    if (-not (Test-Path $userIsoDir)) {
        New-Item -ItemType Directory -Path $userIsoDir -Force | Out-Null
    } else {
        # Limpiar junctions previas (en caso de reconfigurar)
        Get-ChildItem $userIsoDir | Where-Object { $_.LinkType -eq "Junction" } | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # Al iniciar sesion el usuario vera exactamente estas 3 carpetas:
    #   general           -> carpeta publica (lectura y escritura)
    #   reprobados o recursadores -> carpeta de su grupo (lectura y escritura)
    #   nombreUsuario     -> su carpeta personal (solo el)
    New-Item -ItemType Junction -Path "$userIsoDir\general"        -Target "$ftpRoot\general"       | Out-Null
    New-Item -ItemType Junction -Path "$userIsoDir\$grupo"         -Target "$ftpRoot\groups\$grupo" | Out-Null
    New-Item -ItemType Junction -Path "$userIsoDir\$nombreUsuario" -Target $carpetaPersonal          | Out-Null

    Write-Host "  Vista FTP de '$nombreUsuario': [ general | $grupo | $nombreUsuario ]" -ForegroundColor Cyan
}

# -----------------------------------------------
function gestionarUsuariosFtp {
    Write-Host "`n=== GESTION DE USUARIOS FTP ===" -ForegroundColor Cyan

    # Asegurar que los grupos existan
    foreach ($g in $grupos) {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $g -Description "Grupo FTP $g" | Out-Null
        }
    }

    do {
        $nStr = Read-Host "Numero de usuarios a crear"
    } while (-not ($nStr -match '^\d+$') -or [int]$nStr -lt 1)

    $n = [int]$nStr

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Usuario $i de $n ---" -ForegroundColor Yellow

        $nombreUsuario = Read-Host "  Nombre de usuario"
        $password      = Read-Host "  Contrasena"

        do {
            $grupo = Read-Host "  Grupo (reprobados / recursadores)"
        } while ($grupo -notin $grupos)

        crearUsuarioFtp -nombreUsuario $nombreUsuario -password $password -grupo $grupo
    }

    Write-Host "`nTodos los usuarios han sido procesados." -ForegroundColor Green
}

# -----------------------------------------------
function cambiarGrupoUsuario {
    Write-Host "`n=== CAMBIO DE GRUPO DE USUARIO ===" -ForegroundColor Cyan

    $nombreUsuario = Read-Host "Nombre del usuario a reasignar"

    if (-not (Get-LocalUser -Name $nombreUsuario -ErrorAction SilentlyContinue)) {
        Write-Host "Error: el usuario '$nombreUsuario' no existe." -ForegroundColor Red
        return
    }

    # Detectar grupo actual
    $grupoActual = $null
    foreach ($g in $grupos) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -like "*\$nombreUsuario" }) {
            $grupoActual = $g
            break
        }
    }

    if ($grupoActual) {
        Write-Host "Grupo actual: $grupoActual" -ForegroundColor Yellow
    } else {
        Write-Host "El usuario no pertenece a ningun grupo FTP." -ForegroundColor Yellow
    }

    do {
        $nuevoGrupo = Read-Host "Nuevo grupo (reprobados / recursadores)"
    } while ($nuevoGrupo -notin $grupos)

    if ($nuevoGrupo -eq $grupoActual) {
        Write-Host "El usuario ya pertenece a '$nuevoGrupo'. No se realizaron cambios." -ForegroundColor Yellow
        return
    }

    # Actualizar membresia en grupos de Windows
    if ($grupoActual) {
        Remove-LocalGroupMember -Group $grupoActual -Member $nombreUsuario -ErrorAction SilentlyContinue
    }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $nombreUsuario
    Write-Host "Membresia actualizada: '$nuevoGrupo'." -ForegroundColor Green

    # Actualizar junctions en el directorio aislado del usuario
    $userIsoDir = "$ftpRoot\LocalUser\$nombreUsuario"
    if (Test-Path $userIsoDir) {
        # Eliminar junction del grupo anterior
        if ($grupoActual -and (Test-Path "$userIsoDir\$grupoActual")) {
            Remove-Item "$userIsoDir\$grupoActual" -Force
        }
        # Crear junction al nuevo grupo
        if (-not (Test-Path "$userIsoDir\$nuevoGrupo")) {
            New-Item -ItemType Junction -Path "$userIsoDir\$nuevoGrupo" `
                -Target "$ftpRoot\groups\$nuevoGrupo" | Out-Null
        }
        Write-Host "Vista FTP actualizada: el usuario ahora ve '$nuevoGrupo' en lugar de '$grupoActual'." -ForegroundColor Cyan
    } else {
        Write-Host "Advertencia: directorio aislado no encontrado en '$userIsoDir'." -ForegroundColor Yellow
    }
}

# -----------------------------------------------
function monitoreoFtp {
    Write-Host "`n=== MONITOREO DEL SERVICIO FTP ===" -ForegroundColor Cyan

    $svc = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "Servicio FTPSVC no encontrado. Verifique la instalacion." -ForegroundColor Red
        return
    }
    $colorSvc = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "Servicio FTPSVC  : $($svc.Status)" -ForegroundColor $colorSvc
    Write-Host "Tipo de inicio   : $($svc.StartType)"

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue
    if ($site) {
        $colorSite = if ($site.State -eq "Started") { "Green" } else { "Red" }
        Write-Host "Sitio '$ftpSiteName' : $($site.State)" -ForegroundColor $colorSite
        Write-Host "Puerto           : $ftpPort"
        Write-Host "Ruta fisica      : $($site.PhysicalPath)"
    } else {
        Write-Host "Sitio '$ftpSiteName' no configurado aun." -ForegroundColor Yellow
    }

    Write-Host "`nUsuarios por grupo:" -ForegroundColor Yellow
    foreach ($g in $grupos) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        Write-Host "  [$g]" -ForegroundColor Cyan
        if ($miembros) {
            foreach ($m in $miembros) {
                $u = $m.Name -replace ".*\\", ""
                Write-Host "    - $u" -ForegroundColor White
            }
        } else {
            Write-Host "    (sin usuarios)" -ForegroundColor Gray
        }
    }
}

# -----------------------------------------------
function menuFtp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE SERVICIO FTP           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar instalacion"        -ForegroundColor Yellow
    Write-Host "2. Instalar FTP"                 -ForegroundColor Yellow
    Write-Host "3. Desinstalar FTP"              -ForegroundColor Yellow
    Write-Host "4. Configurar sitio FTP"         -ForegroundColor Yellow
    Write-Host "5. Gestionar usuarios"           -ForegroundColor Yellow
    Write-Host "6. Cambiar grupo de usuario"     -ForegroundColor Yellow
    Write-Host "7. Monitoreo"                    -ForegroundColor Yellow
    Write-Host "8. Volver al menu principal"     -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { verificarInstalacionFtp }
        "2" { instalarFtp }
        "3" { desinstalarFtp }
        "4" { configurarFtp }
        "5" { gestionarUsuariosFtp }
        "6" { cambiarGrupoUsuario }
        "7" { monitoreoFtp }
        "8" { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}