#Requires -RunAsAdministrator

function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }

$rutaFunciones = "$PSScriptRoot\..\lib\Practica9"

. "$rutaFunciones\T9_AD.ps1"
. "$rutaFunciones\T9_Delegacion.ps1"
. "$rutaFunciones\T9_Politicas.ps1"
. "$rutaFunciones\T9_MFA.ps1"

function Ver-Usuarios-Roles {
    Clear-Host
    Write-Host "========== Usuarios y Roles Actuales =========="
    Write-Host ""

    $usuarios = @()
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue

    $ou_map = @{}
    foreach ($u in (Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue)) {
        $ou_map[$u.SamAccountName] = "Cuates"
    }
    foreach ($u in (Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue)) {
        $ou_map[$u.SamAccountName] = "NoCuates"
    }

    $formato = "{0,-20} {1,-12} {2}"
    Write-Host ($formato -f "Usuario", "OU", "Rol actual")
    Write-Host ($formato -f "-------", "--", "----------")

    foreach ($u in $usuarios) {
        $rol = Obtener-Rol -Sam $u.SamAccountName
        $rolTexto = if ($rol) { $rol } else { "(sin rol)" }
        $ou = $ou_map[$u.SamAccountName]
        Write-Host ($formato -f $u.SamAccountName, $ou, $rolTexto)
    }

    Write-Host ""
}

function Seleccionar-Usuario {
    $usuarios = @()
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=Cuates,$DC_PATH" -ErrorAction SilentlyContinue
    $usuarios += Get-ADUser -Filter * -SearchBase "OU=NoCuates,$DC_PATH" -ErrorAction SilentlyContinue

    if ($usuarios.Count -eq 0) {
        Print-Err "No hay usuarios en Cuates ni NoCuates."
        return $null
    }

    Write-Host ""
    Write-Host "Usuarios disponibles:"
    for ($i = 0; $i -lt $usuarios.Count; $i++) {
        $rol = Obtener-Rol -Sam $usuarios[$i].SamAccountName
        $rolTexto = if ($rol) { "[$rol]" } else { "[sin rol]" }
        Write-Host "  [$($i+1)] $($usuarios[$i].SamAccountName) $rolTexto"
    }

    Write-Host ""
    $sel = Read-Host "Selecciona usuario (numero)"

    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $usuarios.Count) {
        return $usuarios[[int]$sel - 1].SamAccountName
    }

    Print-Err "Seleccion invalida."
    return $null
}

function Seleccionar-Rol {
    Write-Host ""
    Write-Host "Roles disponibles:"
    Write-Host "  [1] identidad  - Crear/Eliminar/Modificar/Reset usuarios en Cuates y NoCuates"
    Write-Host "  [2] storage    - Gestionar cuotas y apantallamiento FSRM"
    Write-Host "  [3] politicas  - Lectura en todo el dominio + GPOs"
    Write-Host "  [4] auditoria  - Lectura en todo el dominio + logs de seguridad"
    Write-Host ""

    $sel = Read-Host "Selecciona rol (numero)"

    switch ($sel) {
        "1" { return "identidad" }
        "2" { return "storage"   }
        "3" { return "politicas" }
        "4" { return "auditoria" }
        default {
            Print-Err "Seleccion invalida."
            return $null
        }
    }
}

function Administrar-Usuarios {
    do {
        Clear-Host
        Write-Host "========== Administrar Usuarios =========="
        Write-Host ""
        Write-Host "  [1] Ver usuarios y sus roles actuales"
        Write-Host "  [2] Asignar rol a usuario"
        Write-Host "  [3] Eliminar rol de usuario"
        Write-Host "  [4] Cambiar rol de usuario"
        Write-Host "  [5] Volver"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" {
                Ver-Usuarios-Roles
                Read-Host "`nEnter para continuar"
            }
            "2" {
                Clear-Host
                Write-Host "========== Asignar Rol =========="
                $sam = Seleccionar-Usuario
                if (-not $sam) { Read-Host "`nEnter para continuar"; break }
                $rol = Seleccionar-Rol
                if (-not $rol) { Read-Host "`nEnter para continuar"; break }
                Write-Host ""
                Asignar-Rol -Sam $sam -Rol $rol
                Read-Host "`nEnter para continuar"
            }
            "3" {
                Clear-Host
                Write-Host "========== Eliminar Rol =========="
                $sam = Seleccionar-Usuario
                if (-not $sam) { Read-Host "`nEnter para continuar"; break }
                Write-Host ""
                Eliminar-Rol -Sam $sam
                Read-Host "`nEnter para continuar"
            }
            "4" {
                Clear-Host
                Write-Host "========== Cambiar Rol =========="
                $sam = Seleccionar-Usuario
                if (-not $sam) { Read-Host "`nEnter para continuar"; break }
                $rol = Seleccionar-Rol
                if (-not $rol) { Read-Host "`nEnter para continuar"; break }
                Write-Host ""
                Cambiar-Rol -Sam $sam -NuevoRol $rol
                Read-Host "`nEnter para continuar"
            }
            "5" { return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========== Practica 09: Seguridad, Delegacion y MFA =========="
        Write-Host ""
        Write-Host "  [1] Inicializar entorno"
        Write-Host "  [2] Configurar Active Directory"
        Write-Host "  [3] Configurar Delegacion RBAC"
        Write-Host "  [4] Configurar Politicas y Auditoria"
        Write-Host "  [5] Configurar MFA"
        Write-Host "  [6] Administrar Usuarios"
        Write-Host "  [7] Salir"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Inicializar-Entorno;   Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Configurar-AD;         Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Configurar-Delegacion; Read-Host "`nEnter para continuar" }
            "4" { Clear-Host; Configurar-Politicas;  Read-Host "`nEnter para continuar" }
            "5" { Clear-Host; Configurar-MFA;        Read-Host "`nEnter para continuar" }
            "6" { Administrar-Usuarios }
            "7" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu