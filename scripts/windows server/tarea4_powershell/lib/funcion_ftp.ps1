$ftpRootPath = "C:\inetpub\ftproot"
$ftpSiteName = "FTPPractica5"
$ftpPort     = 21

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

    $regla = Get-NetFirewallRule -DisplayName "FTP Practica5" -ErrorAction SilentlyContinue
    if ($regla) {
        Remove-NetFirewallRule -DisplayName "FTP Practica5"
        Write-Host "Regla de Firewall eliminada." -ForegroundColor Green
    }
}

function configurarFtp {
    Write-Host "`n=== CONFIGURACION DEL SERVICIO FTP ===" -ForegroundColor Blue

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # --- Estructura de directorios ---
    foreach ($dir in @("", "general", "reprobados", "recursadores")) {
        $ruta = if ($dir -eq "") { $ftpRootPath } else { "$ftpRootPath\$dir" }
        if (-not (Test-Path $ruta)) {
            New-Item -ItemType Directory -Path $ruta | Out-Null
            Write-Host "Directorio creado: $ruta" -ForegroundColor Green
        } else {
            Write-Host "Directorio ya existe: $ruta" -ForegroundColor Yellow
        }
    }

    # --- Grupos locales ---
    foreach ($grupo in @("reprobados", "recursadores")) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo -Description "Grupo FTP $grupo"
            Write-Host "Grupo '$grupo' creado." -ForegroundColor Green
        } else {
            Write-Host "Grupo '$grupo' ya existe." -ForegroundColor Yellow
        }
    }

    # --- Permisos NTFS en carpetas de grupo y general ---
    # general: IUSR lectura | reprobados y recursadores escritura
    $aclGeneral = Get-Acl "$ftpRootPath\general"
    $reglaIUSR  = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $reglaReprob = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "reprobados", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $reglaRecurs = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "recursadores", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $aclGeneral.SetAccessRule($reglaIUSR)
    $aclGeneral.SetAccessRule($reglaReprob)
    $aclGeneral.SetAccessRule($reglaRecurs)
    Set-Acl "$ftpRootPath\general" $aclGeneral
    Write-Host "Permisos configurados en: general" -ForegroundColor Green

    # reprobados: solo grupo reprobados
    $aclReprob  = Get-Acl "$ftpRootPath\reprobados"
    $reglaGrupo = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "reprobados", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $aclReprob.SetAccessRule($reglaGrupo)
    Set-Acl "$ftpRootPath\reprobados" $aclReprob
    Write-Host "Permisos configurados en: reprobados" -ForegroundColor Green

    # recursadores: solo grupo recursadores
    $aclRecurs  = Get-Acl "$ftpRootPath\recursadores"
    $reglaGrupo = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "recursadores", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $aclRecurs.SetAccessRule($reglaGrupo)
    Set-Acl "$ftpRootPath\recursadores" $aclRecurs
    Write-Host "Permisos configurados en: recursadores" -ForegroundColor Green

    # --- Sitio FTP ---
    if (-not (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name $ftpSiteName -Port $ftpPort -PhysicalPath $ftpRootPath -Force
        Write-Host "Sitio FTP '$ftpSiteName' creado en puerto $ftpPort." -ForegroundColor Green
    } else {
        Write-Host "Sitio FTP '$ftpSiteName' ya existe." -ForegroundColor Yellow
    }

    # SSL desactivado (sin certificado)
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

    # Autenticacion anonima y basica habilitadas
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled    -Value $true

    # ---------------------------------------------------------------
    # Reglas de autorizacion FTP  (FIX: usar MACHINE/WEBROOT/APPHOST)
    # ---------------------------------------------------------------
    $appHostPath = "MACHINE/WEBROOT/APPHOST"
    $authPath    = "/system.ftpServer/security/authorization"

    # Desbloquear la seccion a nivel servidor para que acepte overrides
    Set-WebConfiguration "$authPath" `
        -Metadata overrideMode `
        -Value Allow `
        -PSPath "IIS:\" `
        -ErrorAction SilentlyContinue

    # Limpiar reglas existentes para este sitio
    Clear-WebConfiguration $authPath `
        -PSPath $appHostPath `
        -Location $ftpSiteName `
        -ErrorAction SilentlyContinue

    # Anonimo: solo lectura
    Add-WebConfiguration $authPath `
        -PSPath $appHostPath `
        -Location $ftpSiteName `
        -Value @{
            accessType  = "Allow"
            users       = ""
            roles       = ""
            permissions = "Read"
        }

    # Usuarios autenticados: lectura y escritura
    Add-WebConfiguration $authPath `
        -PSPath $appHostPath `
        -Location $ftpSiteName `
        -Value @{
            accessType  = "Allow"
            users       = "*"
            roles       = ""
            permissions = "Read, Write"
        }

    Start-Website -Name $ftpSiteName -ErrorAction SilentlyContinue
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

        # --- Crear usuario local ---
        $usuarioCreado = $false
        if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
            Write-Host "El usuario '$usuario' ya existe." -ForegroundColor Yellow
            $usuarioCreado = $true
        } else {
            try {
                New-LocalUser -Name $usuario -Password $password -FullName $usuario `
                    -Description "Usuario FTP Practica5" -PasswordNeverExpires -ErrorAction Stop
                Write-Host "Usuario '$usuario' creado." -ForegroundColor Green
                $usuarioCreado = $true
            } catch {
                Write-Host "Error al crear usuario '$usuario': $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Verifique que la contrasena cumpla los requisitos de complejidad de Windows." -ForegroundColor Yellow
                Write-Host "  - Minimo 8 caracteres" -ForegroundColor Yellow
                Write-Host "  - Debe incluir mayusculas, minusculas y numeros o simbolos" -ForegroundColor Yellow
                continue
            }
        }

        # Solo continuar si el usuario existe
        if (-not $usuarioCreado) { continue }

        # --- Agregar al grupo correspondiente ---
        Add-LocalGroupMember -Group $grupo -Member $usuario -ErrorAction SilentlyContinue
        Write-Host "Usuario '$usuario' agregado al grupo '$grupo'." -ForegroundColor Green

        # --- Crear carpeta personal ---
        $carpetaPersonal = "$ftpRootPath\$usuario"
        if (-not (Test-Path $carpetaPersonal)) {
            New-Item -ItemType Directory -Path $carpetaPersonal | Out-Null
        }

        # --- Permisos NTFS con nombre completo COMPUTERNAME\usuario ---
        try {
            $identidad = "$env:COMPUTERNAME\$usuario"
            $acl       = Get-Acl $carpetaPersonal
            $regla     = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identidad, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($regla)
            Set-Acl $carpetaPersonal $acl
            Write-Host "Carpeta personal configurada: $carpetaPersonal" -ForegroundColor Green
        } catch {
            Write-Host "Error al configurar permisos para '$usuario': $($_.Exception.Message)" -ForegroundColor Red
        }
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

    $grupoActual = $null
    foreach ($g in @("reprobados", "recursadores")) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -match "\\$usuario$" -or $_.Name -eq $usuario }) {
            $grupoActual = $g
            break
        }
    }

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

    # Remover del grupo anterior
    if ($grupoActual) {
        Remove-LocalGroupMember -Group $grupoActual -Member $usuario -ErrorAction SilentlyContinue
        Write-Host "Usuario removido del grupo '$grupoActual'." -ForegroundColor Yellow
    }

    # Agregar al nuevo grupo
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario -ErrorAction SilentlyContinue
    Write-Host "Usuario '$usuario' ahora pertenece al grupo '$nuevoGrupo'." -ForegroundColor Green
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
        if ($miembros) {
            Write-Host "  Grupo '$g':" -ForegroundColor Cyan
            $miembros | ForEach-Object { Write-Host "    - $($_.Name)" }
        } else {
            Write-Host "  Grupo '$g': sin miembros" -ForegroundColor Gray
        }
    }
}

function gestionarUsuariosFtp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "      GESTION DE USUARIOS FTP           " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Crear usuarios"    -ForegroundColor Yellow
    Write-Host "2. Cambiar grupo"     -ForegroundColor Yellow
    Write-Host "3. Eliminar usuario"  -ForegroundColor Yellow
    Write-Host "4. Volver"            -ForegroundColor Yellow

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