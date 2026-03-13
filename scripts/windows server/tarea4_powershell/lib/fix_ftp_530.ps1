# fix_general_traverse.ps1
# El problema: para llegar a la junction general -> Public\general
# Windows debe atravesar la carpeta Public, pero Authenticated Users
# no tiene permiso en Public. Se agrega ReadAndExecute a esa carpeta.

function Resolve-SID { param([string]$Sid)
    return (New-Object System.Security.Principal.SecurityIdentifier($Sid)).Translate(
        [System.Security.Principal.NTAccount])
}

$ID_ADMINS = Resolve-SID "S-1-5-32-544"
$ID_SYSTEM = Resolve-SID "S-1-5-18"
$ID_AUTH   = Resolve-SID "S-1-5-11"
$ID_IUSR   = Resolve-SID "S-1-5-17"
$ID_IISUSR = Resolve-SID "S-1-5-32-568"

function MkRule($id, $rights) {
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $id, $rights, "ContainerInherit,ObjectInherit", "None", "Allow")
}
function MkDeny($id) {
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $id, "Delete", "None", "None", "Deny")
}
function ApplyACL($path, $rules) {
    $acl = Get-Acl $path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in $rules) { $acl.AddAccessRule($r) }
    Set-Acl -Path $path -AclObject $acl
}

Write-Host "Reparando permisos de Public y general..." -ForegroundColor Cyan

# Public: Authenticated Users necesita ReadAndExecute para poder
# atravesar esta carpeta y llegar a la junction de general
ApplyACL "C:\ftp\LocalUser\Public" @(
    (MkRule $ID_ADMINS "FullControl"),
    (MkRule $ID_SYSTEM "FullControl"),
    (MkRule $ID_IISUSR "ReadAndExecute"),
    (MkRule $ID_AUTH   "ReadAndExecute"),   # <-- esto faltaba
    (MkRule $ID_IUSR   "ReadAndExecute")
)
Write-Host "  Public OK" -ForegroundColor Green

# general: Authenticated Users tiene Modify (leer + escribir)
# IUSR (anonimo) solo lectura
ApplyACL "C:\ftp\LocalUser\Public\general" @(
    (MkRule $ID_ADMINS "FullControl"),
    (MkRule $ID_SYSTEM "FullControl"),
    (MkRule $ID_IISUSR "ReadAndExecute"),
    (MkRule $ID_AUTH   "Modify"),
    (MkDeny $ID_AUTH),
    (MkRule $ID_IUSR   "ReadAndExecute")
)
Write-Host "  general OK" -ForegroundColor Green

Write-Host "`nReiniciando FTP..." -ForegroundColor Cyan
Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service ftpsvc
Start-Sleep -Seconds 2
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site ServidorFTP | Out-Null

$svc = Get-Service ftpsvc
Write-Host "Servicio: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq "Running") {"Green"} else {"Red"})
Write-Host "Listo. Prueba entrar a general en FileZilla." -ForegroundColor Cyan