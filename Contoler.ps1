<#
/**
 * Controler adn UI for S2 Netpox Toolbox Scripts
 * @author Brian.Kendrick
 * @version 1.0
 */
 #>

#------------------------------------------------------------------------------#
#Sev Some Varibles 
#------------------------------------------------------------------------------#
Remove-Variable * -ErrorAction SilentlyContinue
[string] $output=""
[string []] $keylist=@()
$comands= [ordered]@{}
$comands.Add("Add Tiem Specs","S2.API.Add.TimeSpec_v2.0.0.ps1")
$comands.Add("Add Tiem Spec Groups","S2.API.Add.TimeSpecGroups_v2.0.0.ps1")
$comands.Add("Add Holidays","S2.API.Add.Holidays_v1.5.0.ps1")
$comands.Add("Add S2 Nodes","S2.POST.Add.S2Node_v1.0.0.ps1")
$comands.Add("Add Mercury Panels","S2.POST.Add.MercuryPanel_v1.6.0.ps1")
$comands.Add("Add Transact Panels\Nodes","S2.POST.Add.TransactPanels_v2.0.0.ps1")
$comands.Add("Add Transct Readers","S2.POST.Add.Readers_v2.0.0.ps1")
$comands.Add("Add Inputs","S2.POST.Add.Inputs_v2.0.0.ps1")
$comands.Add("Add Outputs","S2.POST.Add.Outputs_v2.0.0.ps1")
$comands.Add("Add Transct Portals","S2.POST.Add.TransacPortals_v3.3.1.ps1")
$comands.Add("Build Portal Builder JSON","S2.POST.Add.ProtalBuilderJSON_v1.5.0.ps1")
$comands.Add("Add Portal Groups","S2.API.Add.PortalGroups_v2.0.0.ps1")
$comands.Add("Add Reader Groups","S2.API.Add.ReaderGroups_v2.0.0.ps1")
$comands.Add("Add Access Level Groups","S2.API.Add.AccessLevelGroups_v2.0.0.ps1")
$comands.Add("Add Access Levels","S2.API.Add.AccessLevel_v2.0.2.ps1")
$Systemobj = New-Object -ComObject Scripting.FileSystemObject 
$path = $Systemobj.GetFolder("$($PSScriptRoot)") 
[string]$Script:workingPath=$path.ShortPath



#------------------------------------------------------------------------------#
#MAIN UI
#------------------------------------------------------------------------------#
do {
$couter=1
Write-host ""
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
Write-host "S2 NetBox Tool Box" -ForegroundColor Yellow
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
Foreach ($comnad in $comands.keys){
    $keyList += $comnad
    if (Test-Path -Path "$($Script:workingPath)\bin\$($comands[$keyList[$couter-1]])" -PathType leaf) {
        $color = "White"
     }else{
        $color="DarkMagenta"
     }
    Write-host $couter"  |  "$comnad -ForegroundColor $color
    $couter++
}
$max=$couter
Write-host $couter"  |  Exit"
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
#------------------------------------------------------------------------------#
# USERINPUT
#------------------------------------------------------------------------------#
$select =  $(Write-Host 'Please enter a task number: ' -ForegroundColor yellow -NoNewLine; Read-Host)
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
$select= $select-1
if($select -lt $max-1 -and $select -gt -1){
    $Script:datetime = Get-Date -format "yyyy-MM-dd HH:m:ss "
    $filepath = "$($Script:workingPath)\bin\$($comands[$($keyList[$($select)])])"
    if (Test-Path "$filepath") {
    $do = Get-Item "$filepath" | Resolve-Path -Relative
        & $do
    }else {
        $log = "$($Script:datetime) | e | File Not Found : $($Script:workingPath)\bin\$($comands[$keyList[$select]])"
    Write-Warning $log
    }
}
} while ( $select -lt $max-1 )

