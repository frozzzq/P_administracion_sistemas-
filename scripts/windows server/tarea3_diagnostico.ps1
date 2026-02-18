Write Host "======================================================================" -ForegroundColor Yellow
Write Host "                           SERVIDOR DNS                               "
Write Host "======================================================================" -ForegroundColor Yellow


do{
    write host "[1] - VERIFICAR INSTALACION DNS"
    write host "[2] - INSTALAR SERVICIO DNS"
    write host "[3] - REMOVER SERVICIO DNS"

    $opc = Read host "ingrese una opcion:"  

    switch($opc){

        1{
            get-WindowsFeature DNS
        }

        2{
            install-WindowsFeature DNS
        }
            
        3{
            remove-WindowsFeature DNS
        }
            
    
    
    
    }




}while($opc -eq "si")




get-WindowsFeature DNS