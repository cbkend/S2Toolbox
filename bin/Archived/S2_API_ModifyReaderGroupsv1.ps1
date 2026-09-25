<#
    .NOTES
    ===========================================================================
        FileName:  S2_API_ModifyReaderGroups.ps1
        Author:  Brian.Kendrick
        Created On:  2023/05/26
        Last Updated:  2023/05/26
        Package: AccessToolBox
        Version:      v1.0
    ===========================================================================

    .DESCRIPTION
        Add Mercury Panels S2 Netpox Toolbox Script
    .DEPENDENCIES
#>
 

#------------------------------------------------------------------------------#
#Sev Some Varibles 
#------------------------------------------------------------------------------#
#region Script Varibles Defintion
Param(
    [string]$server = $(Write-Host 'Input your server IP address : ' -ForegroundColor yellow -NoNewLine; Read-Host),
    [string]$username = $(Write-Host 'Input your S2 User Name : ' -ForegroundColor yellow -NoNewLine; Read-Host),
    [string]$password =  $(Write-Host 'Input your S2 Password : ' -ForegroundColor yellow -NoNewLine; Read-Host),
    [switch]$appoutput = $false
)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} ;
Remove-Variable * -Exclude "server","username","password","appoutput" -ErrorAction SilentlyContinue
$output=""
$Script:errors = @()
$Script:datetime = Get-Date -format "yyyy-MM-dd HH:m:ss "
$LogDate = Get-Date -format "yyyy-MM-dd_HH_m_ss"
$inputFile = "ModifyReaderGroup.csv"
$Script:Reader =@{}
$Script:RederGroups = @{}
$Script:ReaderGroupsAPI = @{}
$Script:RawData
$Script:sessionID
$Script:session_id
$Script:configNames
$Script:Data
$APIERRORS = "API initialization failure","API is disabled","API no command", "API parse error", "API authentication failure","API unknown command"
Write-host "Modify Reader Groups"
#------------------------------------------------------------------------------#
# USERINPUT
#------------------------------------------------------------------------------#
$Script:urihost =  $server
$Script:S2User= $username
$Script:S2Password=  $password
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
#endregionVaribles

#------------------------------------------------------------------------------#
# HELPER FUNCTIONS
#------------------------------------------------------------------------------#
#region Helper Functions
#Wirte to log file
Function Addlog{
Param([String] $msg)
    $file=$inputFile -split '.csv'
    $file = $file[0] -replace '\s'
    $exportPath=".\logs\$($file)_$($LogDate).log"
    try{
        Add-Content -Path $exportPath -Value $msg
    }catch{
         $Script:errors += $PSItem.Exception
    }
}

#Checks if null and sets outpu color lane 
Function isNull([string] $value){
    [string] $color=""
    # Write-Host $Script:datetime "| i | Check Value : $value :" -ForegroundColor Cyan
    if($value -ne ""){
        if ($value -like "*failure*" -or $value -like "*action=`"/login/`"*"){
             $color="Red"
        } else {
            $color="Cyan"
        }
    } else{
        $color="Red"
    }
    return $color
}

#Checks if null and sets outpu color lane 
Function ErrorCheck([object] $output, [string]$function){
    if($output.result -like "*failure*" -or $output -like "*action=`"/login/`"*" -or $output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
        $Script:errors +=  "$($Script:datetime)`t| e |`t$($function): $($output.message)`n"
        $note ="e"
    }  elseif ($output -eq ''){
        $note ="e"
    } else {
        $note ="i"
    }
    return $note
}

#Xml To Screen
function showxml{
Param([String] $object)
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";
    $output.WriteTo( $XmlWriter );
    $XmlWriter.Flush();
    $StringWriter.Flush();
    [string] $str = $StringWriter.ToString()

    Write-Host ( $str | Format-Table | Out-String )
}
#endregion Helper Functions

#------------------------------------------------------------------------------#
#MAIN FUNCTIONS
#------------------------------------------------------------------------------#
#region Main Functions
#Read Input file to specify Readers that will be added and pull in the Relivent Data
#HEADER ROW :: ReaderGroup,	Reader
Function InputCSV {
    Param ([string]$filename)
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try{
        if (Test-Path ".\import\$filename"){
        $Script:RawData = Import-CSV ".\import\$filename"
        } else {
        $Script:errors = " File Missing form path  .\import\$filename"
        }
    } catch {
        $Script:errors += $PSItem.Exception
        $Script:errors += $Script:RawData 
        $Script:errors += ""
    }
    $color= isNull($Script:RawData )
    $log = "$($Script:datetime)`t| i |`tRead CSV READER DATA : .\import\$($filename)"
    Addlog($log)
    Write-Host $log  -ForegroundColor $color
}

#Login to the S2 System - Useing API NETBOX CALL
Function Login{
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try {
        [xml]$loginCommandxml = @"
<NETBOX-API>
    <COMMAND name="Login" num="1" dateformat="tzoffset">
        <PARAMS>
            <USERNAME>$Script:S2User</USERNAME>
            <PASSWORD>$Script:S2Password</PASSWORD>
        </PARAMS>
    </COMMAND>
</NETBOX-API>
"@
        $output = Invoke-RestMethod -Uri https://$($Script:urihost)/nbws/goforms/nbapi -Method Post -ContentType 'application/xml' -Body $LoginCommandxml
        if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
            $errorNumber =$output.NETBOX.RESPONSE.APIERROR-1
            $log = "$($Script:datetime)`t| e |`t Log In :$($Script:S2User)@$($Script:urihost)`n"
            $log += "$($Script:datetime)`t| e |`t$APIERRORS[$errorNumber]`n"
            $log += "$($Script:datetime)`t| e |`t$($output.NETBOX.RESPONSE.DETAILS.ERRMSG)`n"
            Addlog($log)
            Write-Host $log -ForegroundColor Red
            $Script:errors += "$($log)`n"
        }
        $Script:sessionID = $output.NETBOX.sessionid
    } catch {
        $log = "$($Script:datetime)`t| e |`tLogin: $($PSItem.Exception)"
        Addlog($log)
        $Script:errors += "$($log)`n"
    }
    $logType =  ErrorCheck($output)
    $log= "$($Script:datetime)`t| $($logType) |`tLog In :$($Script:S2User)@$($Script:urihost)"
    Addlog($log)
    Write-Host $log -ForegroundColor Cyan
    $color= isNull($Script:sessionID )
    $log= "$($Script:datetime)`t| $($logType) |`tSESSION ID: $($Script:sessionID) "
    Addlog($log)
    Write-Host $log -ForegroundColor $color
}

#Build Reader Groups Hash Map form CSV Data
function BuildGrouplist{
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try {
        $currentGroup =""
        foreach( $line in $Script:RawData)
        {
            if ($line.ReaderGroup -ne $currentGroup){
                $Script:RederGroups.add($line.ReaderGroup,"")
                $currentGroup = $line.ReaderGroup
            }
            $color= isNull($Script:RederGroups)
            $log = "$($Script:datetime)`t| i |`tReader Group Data: $($line.ReaderGroup)"
            Addlog($log)
            Write-Host $log  -ForegroundColor $color
        }
    } catch {
        $log = "$($Script:datetime)`t| e |`tReader Group Data: $($PSItem.Exception)"
        Addlog($log)
        $Script:errors += "$($log)`n"
        
    }
}

#Get the Reader Groups Keys - Useing API NETBOX CALL
function GetReaderGroupsKeys{
Param ([string]$StartKey)
$Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try {

    if ($StartKey -lt 0 -AND $StartKey -ne -1) {
        $StartKey=0
    }

[xml]$Commandxml = @"
<NETBOX-API sessionid="$($Script:sessionID)">
    <COMMAND name="GetReaderGroups" num="1">
        <STARTFROMKEY>$($StartKey)</STARTFROMKEY>
    </COMMAND>
</NETBOX-API>
"@
        $output = Invoke-RestMethod -Uri https://$($Script:urihost)/nbws/goforms/nbapi -Method Post -ContentType 'application/xml' -Body $Commandxml
        if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
            $errorNumber =$output.NETBOX.RESPONSE.APIERROR-1
            $log = "$($Script:datetime)`t| e |`tGet Reader Groups Keys: $($reader.NETBOX.RESPONSE.DETAILS.READERGROUPS.READERGROUP.NAME,$reader.NETBOX.RESPONSE.DETAILS.READERGROUPS.READERGROUP.READERGROUPKEY)`n"
            $log += "$($Script:datetime)`t| e |`t$APIERRORS[$errorNumber]`n"
            $log += "$($Script:datetime)`t| e |`t$($output.NETBOX.RESPONSE.DETAILS.ERRMSG)`n"
            Addlog($log)
            Write-Host $log -ForegroundColor Red
            $Script:errors += "$($log)`n"
        }

       
        Foreach($reader in $output.NETBOX.RESPONSE.DETAILS.READERGROUPS.READERGROUP){
            $Script:ReaderGroupsAPI.add($($reader.NAME),$($reader.READERGROUPKEY))
            $color= isNull($Script:ReaderGroupsAPI)
            $logType =  ErrorCheck($output)
            $log= "$($Script:datetime)`t| $($logType) |`tGet Reader Groups XML KEYS: $($reader.NAME),$($reader.READERGROUPKEY)"
            Addlog($log)
            Write-Host $log  -ForegroundColor $color
        }

        if ($output.NETBOX.RESPONSE.DETAILS.NEXTKEY -gt 0){
            GetReaderGroupsKeys -StartKey $($output.NETBOX.RESPONSE.DETAILS.NEXTKEY)
        }
    } catch {
        $log = "$($Script:datetime)`t| e |`tGet Reader Groups XML KEYSs: $($PSItem.Exception)"
        Addlog($log)
        $Script:errors += "$($log)`n"
        
    }
}

#Get the Reader Keys - Useing API NETBOX CALL
Function GetReaders{
Param ([string]$StartKey)
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try {

    
    if ($StartKey -lt 0 -AND $StartKey -ne -1) {
        $StartKey=0
    }


[xml]$Commandxml = @"
<NETBOX-API sessionid="$($Script:sessionID)">
    <COMMAND name="GetReaders" num="1">
        <PARAMS>
            <STARTFROMKEY>$($StartKey)</STARTFROMKEY>
        </PARAMS>
    </COMMAND>
</NETBOX-API>
"@
        $output = Invoke-RestMethod -Uri https://$($Script:urihost)/nbws/goforms/nbapi -Method Post -ContentType 'application/xml' -Body $Commandxml
        if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
            $errorNumber =$output.NETBOX.RESPONSE.APIERROR-1
            $log = "$($Script:datetime)`t| e |`tGet Readers:`n"
            $log += "$($Script:datetime)`t| e |`t$APIERRORS[$errorNumber]`n"
            $log += "$($Script:datetime)`t| e |`t$($output.NETBOX.RESPONSE.DETAILS.ERRMSG)`n"
            Addlog($log)
            Write-Host $log -ForegroundColor Red
            $Script:errors += "$($log)`n"
        }
        Foreach($reader in $output.NETBOX.RESPONSE.DETAILS.READERS.READER){
            $Script:Reader.add($reader.NAME,$reader.READERKEY)
            $color= isNull($Script:Reader)
            $logType =  ErrorCheck($output)
            $log= "$($Script:datetime)`t| $($logType) |`tGet Readers: $($reader.NAME,$reader.READER.NAME)"
            Addlog($log)
            Write-Host $log  -ForegroundColor $color
        }
        
        if ($output.NETBOX.RESPONSE.DETAILS.NEXTKEY -gt 0){
           GetReaders -StartKey $($output.NETBOX.RESPONSE.DETAILS.NEXTKEY)
        }
    } catch {
        $log = "$($Script:datetime)`t| e |`tGet Readers: $($PSItem.Exception)"
        Addlog($log)
        $Script:errors += "$($log)`n"
        
    }
}

#Build Reader Key XML
Function BuildReaderKeys() {
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
   try{
        foreach($line in $Script:RawData){
        $ReaderXML ="" 
            foreach ($group in $Script:RederGroups) {
                if($line.ReaderGroup -eq $group.keys -and $line.Reader -ne ''){ 
                    $ReaderXML += $Script:RederGroups[$line.ReaderGroup] 
                    $ReaderXML += "`n<READERKEY>"+$($Script:Reader[$line.Reader])+"</READERKEY>"
                    $Script:RederGroups[$line.ReaderGroup] ="$ReaderXML"
                }
                $color= isNull($Script:RederGroups.Values)
                $logType =  ErrorCheck($Script:RederGroups.Values)
                $log= "$($Script:datetime)`t| $($logType) |`tGet Reader XML KEYS: $($line.Reader)"
                Addlog($log)
                Write-Host $log  -ForegroundColor $color 
            }
        }
    } catch {
       $log = "$($Script:datetime)`t| e |`tGet Reader XML KEYS: $($PSItem.Exception)"
       Addlog($log)
        $Script:errors += "$($log)`n"
    }
}

#Mods Reader Groups  - Useing API NETBOX CALL 
Function ModReaderGroups() {
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    #try{
        foreach ($group in $Script:RederGroups.Keys) {
        if($Script:ReaderGroupsAPI.ContainsKey($($group))){
            [xml]$Commandxml = @"
<NETBOX-API sessionid="$($Script:sessionID)">
    <COMMAND name="ModifyReaderGroup" num="1">
    <PARAMS>
        <READERGROUPKEY>$($Script:ReaderGroupsAPI[$($group)])</READERGROUPKEY>
        <NAME>$($group)</NAME>
        <READERKEYS>$($Script:RederGroups[$group])</READERKEYS>
    </PARAMS>
    </COMMAND>
</NETBOX-API>
"@
            $output = Invoke-RestMethod -Uri https://$($Script:urihost)/nbws/goforms/nbapi -Method Post -ContentType 'application/xml' -Body $Commandxml
            if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
                $errorNumber =$output.NETBOX.RESPONSE.APIERROR-1
                $log = "$($Script:datetime)`t| e |`tModify Reader to Group : $($group)`n"
                $log += "$($Script:datetime)`t| e |`t$APIERRORS[$errorNumber]`n"
                $log += "$($Script:datetime)`t| e |`t$($output.NETBOX.RESPONSE.DETAILS.ERRMSG)`n"
                Addlog($log)
                Write-Host $log -ForegroundColor Red
                $Script:errors += "$($log)`n"
            }
            $color= isNull($output)
            $logType =  ErrorCheck($output)
            $log= "$($Script:datetime)`t| $($logType) |`tModify Reader to Group : $($group)"
            Addlog($log)
            Write-Host $log -ForegroundColor $color
         } else {
            $log = "$($Script:datetime)`t| e |`tModify Reader to Group: $($group) dose not exist in S2"
            Addlog($log)
            $Script:errors += "$($log)`n"
         }
        }
    #} catch {
    #    $log = "$($Script:datetime)`t| e |`tModify Reader to Group: $($PSItem.Exception)"
    #    Addlog($log)
    #    $Script:errors += "$($log)`n"
    #}
   
}

#Logout of the S2 System  - Useing API NETBOX CALL
Function Logout{
    $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try{
        [xml]$logoutCommandxml = @"
<NETBOX-API sessionid="$($Script:sessionID)">
<COMMAND name="Logout" num="1">
</COMMAND>
</NETBOX-API>
"@
        $output = Invoke-RestMethod  -Uri https://$($Script:urihost)/nbws/goforms/nbapi -Method Post -ContentType 'application/xml' -Body $LogoutCommandxml
         if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
            $errorNumber =$output.NETBOX.RESPONSE.APIERROR-1
            $log = "$($Script:datetime)`t| e |`t Log Out :$($Script:S2User)@$($Script:urihost)`n"
            $log += "$($Script:datetime)`t| e |`t$($APIERRORS[$($errorNumber)])`n"
            $log += "$($Script:datetime)`t| e |`t$($output.NETBOX.RESPONSE.DETAILS.ERRMSG)`n"
            Addlog($log)
            Write-Host $log -ForegroundColor Red
            $Script:errors += "$($log)`n"
        }
    } catch {
        $log = "$($Script:datetime)`t| e |`tLog Out: $($PSItem.Exception)"
        Addlog($log)
        $Script:errors += "$($log)`n"
    }
    $logType =  ErrorCheck($output)
    $log= "$($Script:datetime)`t| $($logType) |`tLog Out :$($Script:S2User)@$($Script:urihost)"
    Addlog($log)
    Write-Host $log -ForegroundColor Cyan
}

#Validate Files vs Load 
function Valdate{
$Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
    try {
        $logAdded =""
        $logMissing=""
        foreach($line in $Script:RawData){
    [xml]$Commandxml = @"
        <NETBOX-API sessionid="$($Script:sessionID)">
            <COMMAND name="GetReaderGroup" num="$($Script:ReaderGroupsAPI[$($line.ReaderGroup )])">
                <PARAMS>
                    <READERGROUPKEY>$($Script:ReaderGroupsAPI[$($line.ReaderGroup )])</READERGROUPKEY>
                </PARAMS>
            </COMMAND>
        </NETBOX-API>
"@
            $output = Invoke-RestMethod -Uri https://$($Script:urihost)/nbws/goforms/nbapi -Method Post -ContentType 'application/xml' -Body $Commandxml
            if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
                $errorNumber =$output.NETBOX.RESPONSE.APIERROR-1
                $log = "$($Script:datetime)`t| e |`tValidataion Report API Call: Failed`n"
                $log += "$($Script:datetime)`t| e |`t$($APIERRORS[$($errorNumber)])`n"
                $log += "$($Script:datetime)`t| e |`t$($output.NETBOX.RESPONSE.DETAILS.ERRMSG)`n"
                Addlog($log)
                Write-Host $log -ForegroundColor Red
                $Script:errors += "$($log)`n"
            }
            foreach ($group in $output.NETBOX.RESPONSE.DETAILS.READERGROUP) {
                if($line.ReaderGroup -eq $group.Name -and $group.READERS.READER -ne ''){
                    $logAdded += "$($Script:datetime)`t| s |`tValisation Report :Loaded $($group.Name)`n"
                    foreach ($reader in  $group.READERS.READER){
                        if ($reader.Name -eq $line.Reader ) {
                            $pass=1
                        }
                    }
                    if($pass -eq 1){
                        $logAdded += "$($Script:datetime)`t| s |`tValisation Report :$($line.Reader) Loaded to $($line.ReaderGoup)`n"
                    }
                } else {
                    $logMissing += "$($Script:datetime)`t| r |`tValisation Report :Check $($line.ReaderGoup) for issues.`n"
                }
            }
        }      
    }catch{
        $log = "$($Script:datetime)`t| e |`tValidation Report: $($PSItem.Exception)"
        Addlog($log)
        $Script:errors += "$($log)`n"
    }
    $logAdded = $logAdded.Trim()
    Write-Host $logAdded -ForegroundColor Cyan
    $logMissing.Trim()
    Addlog($logMissing)
    Write-Host $logMissing -ForegroundColor Red
}

#endregion Main Functions

#------------------------------------------------------------------------------#
#MAIN UI
#------------------------------------------------------------------------------#
#region Main UI
Write-host "-------------------------------------------------------------" -ForegroundColor Yellow
Login
InputCSV $inputFile
BuildGrouplist
GetReaderGroupsKeys -StartKey 0
GetReaders -StartKey 0
BuildReaderKeys 
modReaderGroups 
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
if ($Script:errors -ne $null ){
    $log = "$($Script:datetime)`t| e |`tErrors : "
    Addlog($log)
    Write-Host $log -ForegroundColor Red
    Addlog($Script:errors)
    Write-host $($Script:errors)
    Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
}
$log = "$($Script:datetime)`t| v |`tValidation Report:"
Addlog($log)
Write-Host $log -ForegroundColor Yellow
Valdate
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
Logout
#Write-host $Script:datetime "| v | Verbose Output : " 
#endregion Main UI