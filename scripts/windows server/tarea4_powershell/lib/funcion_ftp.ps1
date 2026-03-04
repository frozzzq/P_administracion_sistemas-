$ftpRootPath = "C:\inetpub\ftproot"
$ftpSiteName = "FTPPractica5"
$ftpPort     = 21

function crearJunction {
    param([string]$enlace, [string]$destino)
    if (-not (Test-Path $enlace)) {
        New-Item -ItemType Junction -Path $enlace -Target $destino | Out-Null
    }
}

function obtenerGrupoDeUsuario {
    param([string]$usuario)
    foreach ($g in @("reprobados", "recursadores")) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -match "\\$usuario$" -or $_.Name -eq $usuario }) {
            return $g
        }
    }
    return $null
}

function verificarInstalacionFtp {
    Write-Host "`n--- Verificando estado de IIS FTP ---" -ForegroundColor Cyan
    $feature = Get-WindowsFeature -Name Web-FTP-Server -ErrorAction SilentlyContinue
    if ($feature.Installed) {
        Write-Host "IIS FTP Server     : INSTALADO" -ForegroundColor Green
    } else {
        Write-Host "IIS FTP Server     : NO instalado" -ForegroundColor Red
        Write-Host "Sugerencia: usa la opcion Instalar FTP del menu." -ForegroundColor Yellow
        return
    }
    $servicio = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
    if ($servicio) {
        $color = if ($servicio.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "Estado del servicio: " -NoNewline
        Write-Host "$($servicio.Status)" -ForegroundColor $color
        Write-Host "Tipo de inicio     : $($servicio.StartType)"
    } else {
        Write-Host "Estado del servicio: NO encontrado" -ForegroundColor Red
    }
    $regla = Get-NetFirewallRule -DisplayName "FTP Practica5" -ErrorAction SilentlyContinue
    if ($regla) {
        Write-Host "Regla de Firewall  : EXISTE (puerto 21 abierto)" -ForegroundColor Green
    } else {
        Write-Host "Regla de Firewall  : NO encontrada" -ForegroundColor Red
    }
}

function instalarFtp {
    Write-Host "`n--- Instalacion de IIS FTP Server ---" -ForegroundColor Cyan
    $feature = Get-WindowsFeature -Name Web-FTP-Server -ErrorAction SilentlyContinue
    if ($feature.Installed) {
        Write-Host "IIS FTP Server ya esta instalado." -ForegroundColor Green
    } else {
        Write-Host "Instalando Web Server e IIS FTP Server..." -ForegroundColor Yellow
        try {
            Install-WindowsFeature -Name Web-Server, Web-FTP-Server -IncludeManagementTools
            Write-Host "Instalacion completada." -ForegroundColor Green
        } catch {
            Write-Host "Error durante la instalacion: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }
    $servicio = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
    if ($servicio -and $servicio.Status -ne "Running") {
        Start-Service FTPSVC -ErrorAction SilentlyContinue
        Set-Service  FTPSVC -StartupType Automatic
        Write-Host "Servicio FTPSVC iniciado y configurado en inicio automatico." -ForegroundColor Green
    }
    $regla = Get-NetFirewallRule -DisplayName "FTP Practica5" -ErrorAction SilentlyContinue
    if (-not $regla) {
        New-NetFirewallRule -DisplayName "FTP Practica5" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
        Write-Host "Regla de Firewall creada (puerto 21)." -ForegroundColor Green
    } else {
        Write-Host "Regla de Firewall ya existe." -ForegroundColor Yellow
    }
    Remove-NetFirewallRule -DisplayName "FTP Pasivo Practica5" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "FTP Pasivo Practica5" -Direction Inbound -Protocol TCP -LocalPort 5000-5100 -Action Allow | Out-Null
    Write-Host "Regla de Firewall para puertos pasivos (5000-5100) creada." -ForegroundColor Green
}

function desinstalarFtp {
    Write-Host "`n--- Desinstalacion de IIS FTP Server ---" -ForegroundColor Magenta
    $feature = Get-WindowsFeature -Name Web-FTP-Server -ErrorAction SilentlyContinue
    if (-not $feature.Installed) {
        Write-Host "IIS FTP Server no esta instalado. No hay nada que desinstalar." -ForegroundColor Yellow
        return
    }
    Write-Host "Deteniendo el servicio FTPSVC..." -ForegroundColor Yellow
    Stop-Service FTPSVC -Force -ErrorAction SilentlyContinue
    try {
        Uninstall-WindowsFeature -Name Web-FTP-Server
        Write-Host "Desinstalacion completada." -ForegroundColor Green
    } catch {
        Write-Host "Error al desinstalar: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    foreach ($r in @("FTP Practica5", "FTP Pasivo Practica5")) {
        Remove-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue
    }
    Write-Host "Reglas de Firewall eliminadas." -ForegroundColor Green
}

function configurarFtp {
    Write-Host "`n=== CONFIGURACION DEL SERVICIO FTP ===" -ForegroundColor Blue
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    foreach ($dir in @("", "general", "reprobados", "recursadores", "LocalUser", "LocalUser\Public")) {
        $ruta = if ($dir -eq "") { $ftpRootPath } else { "$ftpRootPath\$dir" }
        if (-not (Test-Path $ruta)) {
            New-Item -ItemType Directory -Path $ruta | Out-Null
            Write-Host "Directorio creado: $ruta" -ForegroundColor Green
        } else {
            Write-Host "Directorio ya existe: $ruta" -ForegroundColor Yellow
        }
    }

    crearJunction "$ftpRootPath\LocalUser\Public\general" "$ftpRootPath\general"
    Write-Host "Junction anonimo (Public\general) configurada." -ForegroundColor Green

    # Quitar herencia en LocalUser: solo Administradores, SYSTEM e IUSR
    $aclLocalUser = Get-Acl "$ftpRootPath\LocalUser"
    $aclLocalUser.SetAccessRuleProtection($true, $false)
    $aclLocalUser.Access | ForEach-Object { $aclLocalUser.RemoveAccessRule($_) | Out-Null }
    foreach ($id in @("SYSTEM", "Administrators")) {
        $aclLocalUser.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $id, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    }
    $aclLocalUser.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
    Set-Acl "$ftpRootPath\LocalUser" $aclLocalUser
    Write-Host "Permisos restrictivos aplicados en: LocalUser" -ForegroundColor Green

    foreach ($grupo in @("reprobados", "recursadores")) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo -Description "Grupo FTP $grupo"
            Write-Host "Grupo '$grupo' creado." -ForegroundColor Green
        } else {
            Write-Host "Grupo '$grupo' ya existe." -ForegroundColor Yellow
        }
    }

    $aclGeneral = Get-Acl "$ftpRootPath\general"
    foreach ($entrada in @(
        @{ id = "IUSR";         perm = "ReadAndExecute" },
        @{ id = "reprobados";   perm = "Modify" },
        @{ id = "recursadores"; perm = "Modify" }
    )) {
        $r = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $entrada.id, $entrada.perm, "ContainerInherit,ObjectInherit", "None", "Allow")
        $aclGeneral.SetAccessRule($r)
    }
    Set-Acl "$ftpRootPath\general" $aclGeneral
    Write-Host "Permisos configurados en: general" -ForegroundColor Green

    $aclReprob = Get-Acl "$ftpRootPath\reprobados"
    $aclReprob.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "reprobados", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
    Set-Acl "$ftpRootPath\reprobados" $aclReprob
    Write-Host "Permisos configurados en: reprobados" -ForegroundColor Green

    $aclRecurs = Get-Acl "$ftpRootPath\recursadores"
    $aclRecurs.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "recursadores", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
    Set-Acl "$ftpRootPath\recursadores" $aclRecurs
    Write-Host "Permisos configurados en: recursadores" -ForegroundColor Green

    if (-not (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name $ftpSiteName -Port $ftpPort -PhysicalPath $ftpRootPath -Force
        Write-Host "Sitio FTP '$ftpSiteName' creado en puerto $ftpPort." -ForegroundColor Green
    } else {
        Write-Host "Sitio FTP '$ftpSiteName' ya existe." -ForegroundColor Yellow
    }

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled    -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.userIsolation.mode -Value 3
    Write-Host "User Isolation activado." -ForegroundColor Green

    Set-WebConfigurationProperty "/system.ftpServer/firewallSupport" -PSPath "IIS:\" -Name lowDataChannelPort  -Value 5000
    Set-WebConfigurationProperty "/system.ftpServer/firewallSupport" -PSPath "IIS:\" -Name highDataChannelPort -Value 5100
    Write-Host "Puertos pasivos configurados: 5000-5100." -ForegroundColor Green

    $appHostPath = "MACHINE/WEBROOT/APPHOST"
    $authPath    = "/system.ftpServer/security/authorization"
    Set-WebConfiguration $authPath -Metadata overrideMode -Value Allow -PSPath "IIS:\" -ErrorAction SilentlyContinue
    Clear-WebConfiguration $authPath -PSPath $appHostPath -Location $ftpSiteName -ErrorAction SilentlyContinue
    Add-WebConfiguration $authPath -PSPath $appHostPath -Location $ftpSiteName -Value @{
        accessType = "Allow"; users = ""; roles = ""; permissions = "Read"
    }
    Add-WebConfiguration $authPath -PSPath $appHostPath -Location $ftpSiteName -Value @{
        accessType = "Allow"; users = "*"; roles = ""; permissions = "Read, Write"
    }

    Restart-Service FTPSVC -ErrorAction SilentlyContinue
    Write-Host "Configuracion FTP completada exitosamente." -ForegroundColor Green
}

function crearUsuariosFtp {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Write-Host "`n=== CREACION DE USUARIOS FTP ===" -ForegroundColor Blue

    do {
        $nStr = Read-Host "Ingrese el numero de usuarios a crear"
    } while (-not ($nStr -match '^\d+$') -or [int]$nStr -lt 1)
    $n = [int]$nStr

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Usuario $i de $n ---" -ForegroundColor Cyan
        $usuario  = Read-Host "Nombre de usuario"
        $password = Read-Host "Contrasena" -AsSecureString
        do {
            $grupo = Read-Host "Grupo (reprobados/recursadores)"
        } while ($grupo -ne "reprobados" -and $grupo -ne "recursadores")

        $usuarioCreado = $false
        if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
            Write-Host "El usuario '$usuario' ya existe." -ForegroundColor Yellow
            $usuarioCreado = $true
        } else {
            try {
                New-LocalUser -Name $usuario -Password $password -FullName $usuario `
                    -Description "Usuario FTP Practica5" -PasswordNeverExpires -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-Host "Usuario '$usuario' creado." -ForegroundColor Green
                $usuarioCreado = $true
            } catch {
                Write-Host "Error al crear usuario '$usuario': $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "La contrasena debe tener mayusculas, minusculas, numeros y minimo 8 caracteres." -ForegroundColor Yellow
                continue
            }
        }

        if (-not $usuarioCreado) { continue }

        Add-LocalGroupMember -Group $grupo -Member $usuario -ErrorAction SilentlyContinue
        Write-Host "Usuario '$usuario' agregado al grupo '$grupo'." -ForegroundColor Green

        # Carpeta personal real con permisos por SID
        $carpetaPersonal = "$ftpRootPath\$usuario"
        if (-not (Test-Path $carpetaPersonal)) {
            New-Item -ItemType Directory -Path $carpetaPersonal | Out-Null
        }
        try {
            $sid   = (Get-LocalUser -Name $usuario).SID
            $acl   = Get-Acl $carpetaPersonal
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $sid, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($regla)
            Set-Acl $carpetaPersonal $acl
        } catch {
            Write-Host "Aviso permisos carpeta personal: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Estructura LocalUser\usuario con junctions
        $homeDir = "$ftpRootPath\LocalUser\$usuario"
        if (-not (Test-Path $homeDir)) {
            New-Item -ItemType Directory -Path $homeDir | Out-Null
        }
        crearJunction "$homeDir\general"  "$ftpRootPath\general"
        crearJunction "$homeDir\$grupo"   "$ftpRootPath\$grupo"
        crearJunction "$homeDir\$usuario" "$ftpRootPath\$usuario"

        # Permisos homeDir: solo el propio usuario (por SID)
        try {
            $sid     = (Get-LocalUser -Name $usuario).SID
            $aclHome = Get-Acl $homeDir
            $aclHome.SetAccessRuleProtection($true, $false)
            $aclHome.Access | ForEach-Object { $aclHome.RemoveAccessRule($_) | Out-Null }
            foreach ($id in @("SYSTEM", "Administrators")) {
                $aclHome.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $id, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
            }
            $aclHome.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $sid, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
            Set-Acl $homeDir $aclHome
        } catch {
            Write-Host "Aviso permisos homeDir: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        Write-Host "Estructura de acceso creada para '$usuario': general, $grupo, $usuario" -ForegroundColor Green
    }

    Write-Host "`nCreacion de usuarios completada." -ForegroundColor Green
}

function cambiarGrupoUsuario {
    Write-Host "`n=== CAMBIO DE GRUPO DE USUARIO ===" -ForegroundColor Blue
    $usuario = Read-Host "Ingrese el nombre del usuario"

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario '$usuario' no existe." -ForegroundColor Red
        return
    }

    $grupoActual = obtenerGrupoDeUsuario $usuario
    if ($grupoActual) {
        Write-Host "Grupo actual del usuario: $grupoActual" -ForegroundColor Yellow
    } else {
        Write-Host "El usuario no pertenece a ningun grupo FTP." -ForegroundColor Yellow
    }

    do {
        $nuevoGrupo = Read-Host "Nuevo grupo (reprobados/recursadores)"
    } while ($nuevoGrupo -ne "reprobados" -and $nuevoGrupo -ne "recursadores")

    if ($grupoActual -eq $nuevoGrupo) {
        Write-Host "El usuario ya pertenece al grupo '$nuevoGrupo'. No se realizaron cambios." -ForegroundColor Yellow
        return
    }

    if ($grupoActual) {
        Remove-LocalGroupMember -Group $grupoActual -Member $usuario -ErrorAction SilentlyContinue
        Write-Host "Usuario removido del grupo '$grupoActual'." -ForegroundColor Yellow
    }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario -ErrorAction SilentlyContinue
    Write-Host "Usuario '$usuario' ahora pertenece al grupo '$nuevoGrupo'." -ForegroundColor Green

    $homeDir         = "$ftpRootPath\LocalUser\$usuario"
    $junctionAntigua = "$homeDir\$grupoActual"
    $junctionNueva   = "$homeDir\$nuevoGrupo"

    if ($grupoActual -and (Test-Path $junctionAntigua)) {
        (Get-Item $junctionAntigua).Delete()
        Write-Host "Junction '$grupoActual' eliminada." -ForegroundColor Yellow
    }
    crearJunction $junctionNueva "$ftpRootPath\$nuevoGrupo"
    Write-Host "Junction '$nuevoGrupo' creada en home de '$usuario'." -ForegroundColor Green
}

function eliminarUsuarioFtp {
    Write-Host "`n=== ELIMINACION DE USUARIO FTP ===" -ForegroundColor Magenta
    $usuario = Read-Host "Ingrese el nombre del usuario a eliminar"

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario '$usuario' no existe." -ForegroundColor Red
        return
    }

    foreach ($g in @("reprobados", "recursadores")) {
        Remove-LocalGroupMember -Group $g -Member $usuario -ErrorAction SilentlyContinue
    }

    $carpetaPersonal = "$ftpRootPath\$usuario"
    if (Test-Path $carpetaPersonal) {
        Remove-Item -Path $carpetaPersonal -Recurse -Force
        Write-Host "Carpeta personal eliminada: $carpetaPersonal" -ForegroundColor Green
    }

    $homeDir = "$ftpRootPath\LocalUser\$usuario"
    if (Test-Path $homeDir) {
        Get-ChildItem $homeDir | Where-Object { $_.LinkType -eq "Junction" } | ForEach-Object { $_.Delete() }
        Remove-Item -Path $homeDir -Recurse -Force
        Write-Host "Directorio de aislamiento eliminado: $homeDir" -ForegroundColor Green
    }

    Remove-LocalUser -Name $usuario
    Write-Host "Usuario '$usuario' eliminado correctamente." -ForegroundColor Green
}

function monitoreoFtp {
    Write-Host "`n================== MONITOREO FTP ==================" -ForegroundColor Blue
    $servicio = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
    if ($servicio) {
        $color = if ($servicio.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "Estado del servicio: " -NoNewline
        Write-Host "$($servicio.Status)" -ForegroundColor $color
    } else {
        Write-Host "El servicio FTPSVC no esta instalado correctamente." -ForegroundColor Red
        return
    }

    Write-Host "----------------------------------------------------"
    Write-Host "Sitio FTP:" -ForegroundColor Yellow
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    try {
        $sitio = Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue
        if ($sitio) {
            Write-Host "  Nombre  : $($sitio.Name)"
            Write-Host "  Estado  : $($sitio.State)"
            Write-Host "  Ruta    : $($sitio.PhysicalPath)"
            Write-Host "  Puerto  : $ftpPort"
        } else {
            Write-Host "  Sitio '$ftpSiteName' no encontrado. Ejecute la opcion Configurar FTP." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  No se pudo obtener informacion del sitio." -ForegroundColor Yellow
    }

    Write-Host "----------------------------------------------------"
    Write-Host "Usuarios por grupo:" -ForegroundColor Yellow
    foreach ($g in @("reprobados", "recursadores")) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        $validos  = $miembros | Where-Object {
            $nombre = ($_.Name -split "\\")[-1]
            Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue
        }
        if ($validos) {
            Write-Host "  Grupo '$g':" -ForegroundColor Cyan
            $validos | ForEach-Object { Write-Host "    - $($_.Name)" }
        } else {
            Write-Host "  Grupo '$g': sin miembros" -ForegroundColor Gray
        }
    }
}

function gestionarUsuariosFtp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE USUARIOS FTP           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Crear usuarios"   -ForegroundColor Yellow
    Write-Host "2. Cambiar grupo"    -ForegroundColor Yellow
    Write-Host "3. Eliminar usuario" -ForegroundColor Yellow
    Write-Host "4. Volver"           -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { crearUsuariosFtp }
        "2" { cambiarGrupoUsuario }
        "3" { eliminarUsuarioFtp }
        "4" { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}

function menuFtp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE SERVICIO FTP           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar instalacion"    -ForegroundColor Yellow
    Write-Host "2. Instalar FTP"             -ForegroundColor Yellow
    Write-Host "3. Desinstalar FTP"          -ForegroundColor Yellow
    Write-Host "4. Configurar FTP"           -ForegroundColor Yellow
    Write-Host "5. Gestionar usuarios"       -ForegroundColor Yellow
    Write-Host "6. Monitoreo"                -ForegroundColor Yellow
    Write-Host "7. Volver al menu principal" -ForegroundColor Yellow

    $op = Read-Host "Elige una opcion"
    switch ($op) {
        "1" { verificarInstalacionFtp }
        "2" { instalarFtp }
        "3" { desinstalarFtp }
        "4" { configurarFtp }
        "5" { gestionarUsuariosFtp }
        "6" { monitoreoFtp }
        "7" { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}