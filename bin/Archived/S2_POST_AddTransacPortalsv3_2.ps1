#Sev Some Varibles 
#------------------------------------------------------------------------------#
#region Script Varibles Defintion
#region Constant Varibles
Param( 
	[Parameter(Mandatory=$false)][string] $hostValue = $(Write-Host 'Input your server IP address : ' -ForegroundColor yellow -NoNewLine; Read-Host),
    [Parameter(Mandatory=$false)][string] $S2User = $(Write-Host 'Input your S2 User Name : ' -ForegroundColor yellow -NoNewLine; Read-Host),
    [Parameter(Mandatory=$false)][string] $S2Password = $(Write-Host 'Input your S2 Password : ' -ForegroundColor yellow -NoNewLine; Read-Host),
	[Parameter(Mandatory=$false)][string] $varhtml = $(Write-Host 'http [0] /https [1] : ' -ForegroundColor yellow -NoNewLine; Read-Host),
	[Parameter(Mandatory=$false)][switch] $silent
	#TODO :: [Parameter(Mandatory=$false)][switch] $S2 or #TODO :: [Parameter(Mandatory=$false)][string] $source
)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls13
$code= @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
Add-Type -TypeDefinition $code -Language CSharp
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null #{$true} ;
[string[]] $ParamaterList = @(("hostValue"),("S2User"),("S2Password"),("varhtml"),("silent"))
Remove-Variable * -Exclude $ParamaterList  -ErrorAction SilentlyContinue
[string] $output=""
[string[]] $Script:Errors = @()
[string] $Script:datetime = Get-Date -format "yyyy-MM-dd`tHH:m:ss "
[string] $Script:LogFileDate = Get-Date -format "yyyy-MM-dd_HH_m_ss"
$Script:RawData
[string] $Script:sessionID
[string] $Script:session_id
[string[]] $APIERRORS = "API initialization failure","API is disabled","API no command", "API parse error", "API authentication failure","API unknown command"
[string] $Script:workingPath = Split-Path -Path $PSScriptRoot -Parent
$Systemobj = New-Object -ComObject Scripting.FileSystemObject 
$path = $Systemobj.GetFolder("$($Script:workingPath)") 
$Script:workingPath=$path.ShortPath
#endregion Constant Varibles
#region Logic Varibles
[string] $inputFile = "TransactPortalsImport.csv"
[string] $LogFile = "TransactPortalsImport"
[string[]] $events= @()
[Hashtable] $Script:NetworkNodeHash = @{}
[Hashtable] $Script:ReaderHash = @{}
[Hashtable] $Script:InputsHash = @{}
[Hashtable] $Script:OutputsHash = @{}
[Hashtable] $Script:PortalsHash = @{}
  

#------------------------------------------------------------------------------#
# USERINPUT
#------------------------------------------------------------------------------#

write-host $PSScriptRoot
[string] $Script:urihost = $hostValue
[securestring] $SecurePassword = $S2Password | ConvertTo-SecureString -AsPlainText -Force
$Script:S2Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $S2User, $SecurePassword
$SecurePassword = $null
[string] $S2Password = $null
[string] $Script:varhtml = $varhtml
if($Script:varhtml -eq 0){
	$Script:varhtml="http"
} elseif ($Script:varhtml -eq 1){
	$Script:varhtml = "https"
}else {
	$Script:varhtml = $(Write-Host 'http [0] /https [1] : ' -ForegroundColor yellow -NoNewLine; Read-Host)
}
Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
#endregion Logic Varibles
#endregion Script Varibles Defintion

#------------------------------------------------------------------------------#
# HELPER FUNCTIONS
#------------------------------------------------------------------------------#
#region Helper Functions
	#Wirte to log file
	Function Add-Log{
    [CmdletBinding(PositionalBinding=$false)]
			Param(
				[Parameter(Mandatory,HelpMessage="The Message for the Log")][String] $Message,
				[Parameter(Mandatory,HelpMessage="Name of the Log File")][Alias("LogFile")][String] $Log
			)
			[string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss "		
			$exportPath="$($Script:workingPath)\logs\$($Log)_$($Script:LogFileDate).log"
			try{
				Add-Content -Path $exportPath -Value $Message
			}catch{
				 $Script:Errors += "$($LogDateTime)`t| e |`tAdd-Log :: $Message"
				 $Script:Errors += "$($LogDateTime)`t| e |`tAdd-Log ::  $($PSItem.Exception)"
			}
		}

	#XML To Screen
	Function Show-XML{
		<#
			.SYNOPSIS
				Displays XMl to Console 
	 
			.DESCRIPTION
				Displays XMl to Console
	 
			.EXAMPLE
				Show-XML -value $xml
	  
			.PARAMETER Value 
				(required) The [XML] Object to be dispalyed.
		#>
        [CmdletBinding(PositionalBinding=$false)]
		Param(
			[Parameter(Mandatory)][xml] $object
		)
		$StringWriter = New-Object System.IO.StringWriter;
		$XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
		$XmlWriter.Formatting = "indented";
		$object.WriteTo( $XmlWriter );
		$XmlWriter.Flush();
		$StringWriter.Flush();
		[string] $str = $StringWriter.ToString()

		Write-Host ( $str | Format-Table | Out-String )
	}

    #Hastable to Screen
	Function showhashtabel{
    [CmdletBinding(PositionalBinding=$false)]
	Param($object)
		foreach( $line in $object){
			Write-host "$($line.Keys),$($line.Values)"
		}
	}

	#Formats the API Call XML
	Function Format-CommandXML{
    [CmdletBinding(PositionalBinding=$false)]
		Param (
		[Parameter(Mandatory)][string] $CommandName, 
		[Parameter(Mandatory)][string] $CommandNum, 
		[string] $CommandParams
		)
		if ($Script:sessionID -ne $null){
		[xml]$CommandXML = @"
<NETBOX-API sessionid="$($Script:sessionID)">
<COMMAND name="$($CommandName)" num="$($CommandNum)" dateformat="tzoffset">
	$($CommandParams)
</COMMAND>
</NETBOX-API>
"@
	} else {
		[xml]$CommandXML = @"
<NETBOX-API>
<COMMAND name="$($CommandName)" num="$($CommandNum)" dateformat="tzoffset">
	$($CommandParams)
</COMMAND>
</NETBOX-API>
"@    
		}
		return  [xml]$CommandXML
	}

	#Runs the API Comnad 
	Function Step-APICommnad{
    [CmdletBinding(PositionalBinding=$false)]
		Param ( 
			[Parameter(Mandatory)][string] $Name, 
			[Parameter(Mandatory)][xml] $CommandXML, 
			[Alias("Values")] [string] $CommandParams,
			[Parameter(Mandatory)][string] $LogFile
		)
		[string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
try{
		if($($Script:sessionID) -ne $null){
		$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
		$session.Cookies.Add((New-Object System.Net.Cookie(".sessionId", "$($Script:sessionID)", "/", "$($Script:urihost)")))
			$output = Invoke-RestMethod -Uri "$($Script:varhtml)://$($Script:urihost)/nbws/goforms/nbapi" -Method Post -ContentType 'application/xml' -Body $CommandXML -WebSession $session
		} else {
			$output = Invoke-RestMethod -Uri "$($Script:varhtml)://$($Script:urihost)/nbws/goforms/nbapi" -Method Post -ContentType 'application/xml' -Body $CommandXML
		}
		if($output.NETBOX.RESPONSE.CODE -ne "SUCCESS" ){
			$errorNumber =$output.NETBOX.RESPONSE.APIERROR
			$LogMesg= "$($LogDateTime)`t| e |`t$($Name) : $($CommandParams)`n"
            if($errorNumber -ne $null){
			    $LogMesg+= "$($LogDateTime)`t| e |`tAPI Error Number : $($errorNumber)`n"
			    $LogMesg+= "$($LogDateTime)`t| e |`tAPI Error Code : $($APIERRORS[$($errorNumber)])`n"
            }
			$LogMesg+= "$($LogDateTime)`t| e |`tAPI Message : $($output.NETBOX.RESPONSE.DETAILS.ERRMSG) :: $($output.NETBOX.RESPONSE)`n"
            $LogMesg = $LogMesg.Trim()
            Write-Warning $LogMesg
            $LogMesg+= "$($CommandXML.OuterXml)`n"
            $LogMesg+= "$($output.OuterXml)`n"
            $LogMesg+=  "-------------------------------------------------------------`n" 
			$LogMesg= $LogMesg.Trim()
			Add-Log -Message $LogMesg -LogFile $LogFile
			$Script:errors += "$($LogMesg)`n"
			$Script:errors = $Script:errors.Trim()
		} else {
            $LogMesg= "$($LogDateTime)`t| i |`t$($Name) : $($CommandParams)`n"
            $LogMesg+= "$($CommandXML.OuterXml)`n"
            $LogMesg+= "$($output.OuterXml)`n"
            $LogMesg+=  "-------------------------------------------------------------`n" 
			$LogMesg= $LogMesg.Trim()
			Add-Log -Message $LogMesg -LogFile $LogFile
        }
        } catch {
                $LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) to S2 API  : $($Script:S2Credentials.UserName)@$($Script:urihost).::  $($PSItem.toString()) "
			    $LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
			    $LogMesg = $LogMesg.trim()
			    Add-Log -Message $LogMesg -LogFile $LogFile
			    $Script:Errors += $PSItem.Exception.ToString()
			    #Write-Warning $LogMesg 
		    }    
		return $output
	}

    #Runs the URL and retruns the JSON Repsonce for Array Responce 
    Function Step-GetArrayURL{
     [CmdletBinding(PositionalBinding=$false)]
		    Param (
                [Parameter(Mandatory)][string] $UserFrendlyName,
                [Parameter(Mandatory)][string] $uriPath,
			    [Parameter(Mandatory)][string] $LogFile
		    )
		    [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    try {
                $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $session.Cookies.Add((New-Object System.Net.Cookie(".sessionId", "$($Script:sessionID)", "/", "$($Script:urihost)")))
                $output = Invoke-WebRequest -UseBasicParsing -Uri "$($Script:varhtml)://$($Script:urihost)/$($uriPath)" `
                -WebSession $session `

                $OutputJson = ConvertFrom-Json -InputObject $output

                 if ($OutputJson -ne $null) {
                    $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: Objects : $($OutputJson.count)"
			        $LogMesg = $LogMesg.Trim()
		            Add-Log -Message $LogMesg -LogFile $LogFile
			        Write-Output $LogMesg  
                } else {
                    $LogMesg = "$($LogDateTime)`t| e |`t$($UserFrendlyName)"
				    $LogMesg = $LogMesg.Trim()
			        Add-Log -Message $LogMesg -LogFile $LogFile
			        Write-Warning $LogMesg
			        $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim()
                }

            } catch {
				    $LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString())  "
                    $LogMesg+= "$($Script:varhtml)://$($Script:urihost)/$($uriPath)/?page=$page`n"
                    $LogMesg+= "$($output)`n"
                    $LogMesg+=  "-------------------------------------------------------------`n" 
				    $LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				    $LogMesg = $LogMesg.trim()
				    Add-Log -Message $LogMesg -LogFile $LogFile
                    $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim()
				    $Script:Errors += $PSItem.Exception.ToString()
				    Write-Warning $LogMesg 
		    }
            return $OutputJson

    }

    #Runs the URL and retruns the Row level for the JSON Repsonce 
    Function Step-GetJsonURL{
	[CmdletBinding(PositionalBinding=$false)]
	    Param (
            [Parameter(Mandatory)][string] $UserFrendlyName,
            [Parameter(Mandatory)][string] $uriPath,
            [string] $page,
		    [Parameter(Mandatory)][string] $LogFile
	    )
		    [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    try {
			    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
			    $session.Cookies.Add((New-Object System.Net.Cookie(".sessionId", "$($Script:sessionID)", "/", "$($Script:urihost)")))
			    $output=Invoke-RestMethod  -UseBasicParsing -Uri "$($Script:varhtml)://$($Script:urihost)/$($uriPath)/?page=$page"`
			    -WebSession $session
                                
                if( $output.total -gt 0){
                    $total = $output.total
		            $page = $output.page
		            $count = $output.page+1	
			    
                    if ($count -le $total) {
                        $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: Page : $page/$total Next Page:: $count"
				        $LogMesg = $LogMesg.Trim()
				        Add-Log -Message $LogMesg -LogFile $LogFile
				        Write-Output $LogMesg  
			            Step-GetJsonURL -userFrendlyName $UserFrendlyName -uriPath $uriPath -page $count -LogFile $LogFile
		            }
                } else {
                    $LogMesg = "$($LogDateTime)`t| e |`t$($UserFrendlyName)"
				    $LogMesg = $LogMesg.Trim()
			        Add-Log -Message $LogMesg -LogFile $LogFile
			        Write-Warning $LogMesg
			        $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim()
                }
	 
		    } catch {
				    $LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
                    $LogMesg+= "$($Script:varhtml)://$($Script:urihost)/$($uriPath)/?page=$page`n"
                    $LogMesg+= "$($output)`n"
                    $LogMesg+=  "-------------------------------------------------------------`n" 
				    $LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				    $LogMesg = $LogMesg.trim()
				    Add-Log -Message $LogMesg -LogFile $LogFile
                    $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim()
				    $Script:Errors += $PSItem.Exception.ToString()
				    Write-Warning $LogMesg 
		    }
            return $output
            
	    }

	#Defulat Checks for Error Tyes for logging
	Function Set-LogType{
    [CmdletBinding(PositionalBinding=$false)]
		Param(
			[object] $value, 
			[Parameter(Mandatory)][String]$FunctionName
		)
		[string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
        #Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
        #write-host $value
        #write-host $value.result
        #write-host $value.NETBOX.RESPONSE.CODE
        #write-host ($value.NETBOX.RESPONSE.CODE -ne "SUCCESS")
        #write-host ($value.result -like "*failure*")
        #write-host ($value -like "*action=`"/login/`"*")
        #Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
		if($value.NETBOX.RESPONSE.CODE -ne "SUCCESS"){
			$Script:errors +=  "$($LogDateTime)`t| e |`t$($FunctionName): $($value.message)`n"
			$logType = "e"
		}  elseif ($value -eq ''){
			$logType = "e"
		} else {
			$logType = "i"
		}
		return $logType
	}

    # Build URL For Json Hashtable 
    Function Setp-BuildJSONBody{
     [CmdletBinding(PositionalBinding=$false)]
		    Param (
                [Parameter(Mandatory)][hashtable] $jsonHash,
			    [Parameter(Mandatory)][string] $LogFile
		    )
        [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
        [string] $userFrendlyName="Build Body JSON for URI Call"
		try {
                $json = ConvertTo-Json -InputObject $jsonHash
                [URI] $uriJson = [URI]::EscapeUriString($json)
                $body = "json=$($uriJson)"
               
                
                <#if ($body -ne ""){
                     $LogMesg = "$($Script:datetime)`t| i |`t$($UserFrendlyName) "
				     $LogMesg = $LogMesg.Trim()
				     Add-Log -Message $LogMesg -LogFile $LogFile
				     Write-Output $LogMesg  
                } else {
                    $LogMesg = "$($Script:datetime)`t| e |`t$($UserFrendlyName) "
                    $LogMesg+= "$($uriJson)`n"
                    $LogMesg+=  "-------------------------------------------------------------`n" 
				    $LogMesg = $LogMesg.Trim()
			        Add-Log -Message $LogMesg -LogFile $LogFile
			        Write-Warning $LogMesg
			        $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim() 
                }#>
        
        } catch {
				    $LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
                    $LogMesg+= "$($jsonHash)`n"
                    $LogMesg+= "$($json)`n"
                    $LogMesg+= "$($uriJson)`n"
                    $LogMesg+= "$($body)`n"
                    $LogMesg+=  "-------------------------------------------------------------`n" 
				    $LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				    $LogMesg = $LogMesg.trim()
				    Add-Log -Message $LogMesg -LogFile $LogFile
                    $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim()
				    $Script:Errors += $PSItem.Exception.ToString()
				    Write-Warning $LogMesg 
        }
        return $body
    }

    Function Get-UIStamp{
    [CmdletBinding(PositionalBinding=$false)]		   
    Param (
		[Parameter(Mandatory)] $myID
    )
       $remainderID = $myID % 1000000
       $udate = [DateTimeOffset]::UtcNow.AddMonths(1).ToUnixTimeMilliseconds()
       return "$($remainderID)_$($udate)"
    }  

    Function Set-Null{
    [CmdletBinding(PositionalBinding=$false)]
		Param (
			$check 
        )
        if ($check -eq $null -or $check -eq '' -or $check -eq 0){
             $value = "null"
        } else {
             $value = $check
        }
        return $value
    }
#endregion Helper Functions

#------------------------------------------------------------------------------#
#MAIN FUNCTIONS
#------------------------------------------------------------------------------#
#region Main Cmdlets
    #region Base Cmdlets
        #Read Input file to specify Readers that will be added and pull in the Relivent Data
	    # HEADER ROW :: Name,	Description,	AccessLevel
	    Function InputCSV {
		[CmdletBinding(PositionalBinding=$false)]
		Param (
			[Parameter(Mandatory)][string] $filename, 
			[Parameter(Mandatory)][string] $LogFile
		)
		[string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		$UserFrendlyName = "Input CSV Data"
		try{
			if (Test-Path "$($Script:workingPath)\import\$($filename)"){
			$Script:RawData = Import-CSV "$($Script:workingPath)\import\$($filename)"
			} else {
			$Script:Errors = "$($LogDateTime)`t| e |`t$File Missing form path  $($Script:workingPath)\import\$($filename)"
			}
		} catch {
			$Script:Errors += $PSItem.Exception
			$Script:Errors += $Script:RawData 
			$Script:Errors += ""
			$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) : $($Script:workingPath)\import\$($filename). ::  $($PSItem.toString()) "
			$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
			$LogMesg = $LogMesg.trim()
			Add-Log -Message $LogMesg -LogFile $LogFile
			$Script:Errors += $PSItem.Exception.ToString()
			Write-Warning $LogMesg 
		}
		$LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) : $($Script:workingPath)\import\$($filename)"
		Add-Log -Message $LogMesg -LogFile $LogFile
		Write-Output $LogMesg 
	}

	    #Login to the S2 System - Useing API NETBOX CALL 
	    Function Step-Login{
		<#
			.SYNOPSIS
			   Runs S2 NBAPI v2 Login command

			.DESCRIPTION
			   Rest API Call 
			   The Login command logs into a partition of a system. The default partition is "Master."
			   Use SwitchPartition to switch the current partition.

			.EXAMPLE
			   Step-Login -UserName Bob -Password myPassword -LogFile "Add-ACLs"

			.PARAMETER UserName 
				(required) Username of a system user with full system setup, partition setup or user role mapping API privileges.

			.PARAMETER Password
				(required) Password of a system user with full system setup, partition setup or user role mapping API privileges.

			.PARAMETER Log
				(required) The Name of the Log File to be writen to 
		#>
		[CmdletBinding(PositionalBinding=$false)]
		Param (
			[Parameter(Mandatory)][string] $User, 
			[Parameter(Mandatory)][String] $Password,
			[Parameter(Mandatory)][string] $LogFile
		)
		[string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		$UserFrendlyName = "Login"
		$CommandName = "Login"
		try {
			$CommandParams ="<PARAMS><USERNAME>$($User)</USERNAME><PASSWORD>$($Password)</PASSWORD></PARAMS>"
			[xml]$CommandXML = Format-CommandXML -CommandName $CommandName -CommandNum "1" -CommandParams $CommandParams 
			$result = Step-APICommnad -Name $UserFrendlyName -CommandXML $CommandXML -LogFile $logfile
			$Script:sessionID = $result.NETBOX.sessionid
		} catch {
			$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) to S2 API  : $($User)@$($Script:urihost). ::  $($PSItem.toString()) "
			$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
			$LogMesg = $LogMesg.trim()
			Add-Log -Message $LogMesg -LogFile $LogFile
			$Script:Errors += $PSItem.Exception.ToString()
			Write-Warning $LogMesg 
		}
		$logType =  Set-LogType -Value $result -FunctionName $UserFrendlyName
		$LogMesg = "$($LogDateTime)`t| $($logType) |`t$($UserFrendlyName) : $($result.NETBOX.RESPONSE.CODE) : $($User)@$($Script:urihost)"
		Add-Log -Message $LogMesg -LogFile $LogFile
		if ($($logType) -eq 'e'){
            Write-Warning $LogMesg
        } else {
            Write-Output $LogMesg
        }
		$LogMesg = "$($LogDateTime)`t| $($logType) |`tSESSION ID : $($Script:sessionID) "
		Add-Log -Message $LogMesg -LogFile $LogFile
		if ($($logType) -eq 'e'){
            Write-Warning $LogMesg
        } else {
            Write-Output $LogMesg
        }
	}

        #Get The Cross Site Request Forgery Token - Useing the NETBOX Web URL
        Function Get-CSRFToken{
        [CmdletBinding(PositionalBinding=$false)]
		    Param (
			    [Parameter(Mandatory)][string] $LogFile
		    )
        [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
        [string] $userFrendlyName="CSRFT TOKEN"
		try {
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $session.Cookies.Add((New-Object System.Net.Cookie(".sessionId", "$Script:sessionID", "/", "$Script:urihost")))
            $object = Invoke-WebRequest -UseBasicParsing -Uri "$($Script:varhtml)://$Script:urihost/frameset/" `
            -WebSession $session `
            -Headers @{
              "Referer"="$($Script:varhtml)://$Script:urihost/login/"
              "Upgrade-Insecure-Requests"="1"
            }

            $break= $object -split 'csrft'
            $break = $break[1] -split ';' 
            $CSRFT = $break[0] -replace '"'
            $CSRFT = $CSRFT -replace '='
            $CSRFT = $CSRFT -replace '\s' 
            $Script:CSRFT=$CSRFT

            if ($Script:CSRFT -ne ""){
                 $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) : $($Script:CSRFT)"
				 $LogMesg = $LogMesg.Trim()
				 Add-Log -Message $LogMesg -LogFile $LogFile
				 Write-Output $LogMesg  
            } else {
                $LogMesg = "$($LogDateTime)`t| e |`t$($UserFrendlyName)"
				$LogMesg = $LogMesg.Trim()
			    Add-Log -Message $LogMesg -LogFile $LogFile
			    Write-Warning $LogMesg
			    $Script:errors += "$($LogMesg)`n"
			    $Script:errors = $Script:errors.Trim() 
            }

        } catch {
				    $LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
                    $LogMesg+= "$($object)`n"
                    $LogMesg+=  "-------------------------------------------------------------`n" 
				    $LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				    $LogMesg = $LogMesg.trim()
				    Add-Log -Message $LogMesg -LogFile $LogFile
                    $Script:errors += "$($LogMesg)`n"
			        $Script:errors = $Script:errors.Trim()
				    $Script:Errors += $PSItem.Exception.ToString()
				    Write-Warning $LogMesg 
        }
    }
    
	    #Logout of the S2 System  - Useing API NETBOX CALL
	    Function Step-Logout{
		<#
			.SYNOPSIS
			   Runs S2 NBAPI v2 Logout command

			.DESCRIPTION
			   Rest API Call 
			   The Logout command logs out of an API session created with a Login command. Use the session ID to log out of the session.

			.EXAMPLE
			   Step-Logout -LogFile "Add-ACLs"

			.PARAMETER LogFile
				(required) The Name of the Log File to be writen to 
		 #>
		[CmdletBinding(PositionalBinding=$false)]
		Param (
			[Parameter(Mandatory)][string] $LogFile
		)

		[string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		$UserFrendlyName = "Log Out"
		$CommandName = "Logout"
		try{
            $CommandParams =""
			[xml]$CommandXML = Format-CommandXML -CommandName $CommandName -CommandNum "1" -CommandParams $CommandParams 
			$result = Step-APICommnad -Name $UserFrendlyName -CommandXML $CommandXML -LogFile $logfile			
            #show-XML($CommandXML)							
		} catch {
            $LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) to S2 API  : $($Script:S2Credentials.UserName)@$($Script:urihost).::  $($PSItem.toString()) "
			$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
			$LogMesg = $LogMesg.trim()
			Add-Log -Message $LogMesg -LogFile $LogFile
			$Script:Errors += $PSItem.Exception.ToString()
			#Write-Warning $LogMesg 
		}
		$logType =  Set-LogType -Value $result -FunctionName $UserFrendlyName
		$LogMesg = "$($LogDateTime)`t| $($logType) |`t$($UserFrendlyName) : $($result.NETBOX.RESPONSE.CODE) : $($Script:S2Credentials.UserName)@$($Script:urihost)"
		Add-Log -Message $LogMesg -LogFile $Logfile
        if ($($logType) -eq 'e'){
            Write-Warning $LogMesg
        } else {
            Write-Output $LogMesg
        }
	} 

    #endregion Base Cmdlets
    #region File Cmdlets

        #Perform action(s) for each line of file 
        Function Step-paresFile{
        [CmdletBinding(PositionalBinding=$false)]		   
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Loading Portals"
		    try {
                $currentPortal =""
                Foreach ($Portal in $Script:RawData) {
                    $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName): $($Portal.PortalName)"
				    $LogMesg = $LogMesg.Trim()
				    Add-Log -Message $LogMesg -LogFile $LogFile
                    Write-Output $LogMesg  
                    if($Portal.PortalName -ne $currentPortal){ 
                        $UIStamp=$(Get-UIStamp -myID 1)
                        $jsonHash= [ordered]@{}                     
                        $jsonHash.Add("_csrf", $($Script:CSRFT))
                        #$jsonHash.Add("name","")
                        $jsonHash.Add("newName","$($Portal.PortalName)")
                        $jsonHash.Add("networkNode",$($Script:NetworkNodeHash[$($Portal.NodeName)]).id)
                        $jsonHash.Add("location",1)
                        $jsonHash.Add("lockResourceID",$($Script:OutputsHash[$($Portal.LKName)]).id) ## REVEIW
                        $jsonHash.Add("lockTime",5)
                        $jsonHash.Add("adaLockTime",20)
                        $jsonHash.Add("dsmResourceID",$($Script:InputsHash[$($Portal.DCName)]).id) ## REVEIW
                        $jsonHash.Add("dsmShuntTime",10)
                        $jsonHash.Add("adaDsmShuntTime",30)
                        $jsonHash.Add("dsmRelockOnOpen","on")
                        $jsonHash.Add("shuntops5",0)
                        $jsonHash.Add("rexResourceID",$($Script:InputsHash[$($Portal.REXName)]).id) ## REVEIW
                        $jsonHash.Add("auxOutputResourceID",0)
                        $jsonHash.Add("unlockOnRex","on")
                        $jsonHash.Add("rexDelayTime",0)
                        $jsonHash.Add("threatlvlgroup",0)
                        #$jsonHash.Add("REXMode","rbPIR")
                        $jsonHash.Add("REXMode","rbMomentary")
                        $jsonHash.Add("auxOutputTime",0)
                        $jsonHash.Add("unlockWhenOpen","on")
                        $jsonHash.Add("ignoredsmonvalid","on")
                        $jsonHash.Add("reader1ID",$Script:ReaderHash[$($Portal.ReaderName)].id)
                        $jsonHash.Add("altreader1ID",0)
                        $jsonHash.Add("reader1ReadReadyOnly","on")
                        $jsonHash.Add("primaryRegion",1)
                        $jsonHash.Add("keypad1ID",0)
                        $jsonHash.Add("altkeypad1ID",0)
                        $jsonHash.Add("timespeckp1",1)
                        $jsonHash.Add("threatlvlgrpkp1",0)
                        $jsonHash.Add("reader2ID",0)
                        $jsonHash.Add("reader2ReadReadyOnly","on")
                        #$jsonHash.Add("timespecrd2",1)
                        $jsonHash.Add("threatlvlgrprd2",0)
                        $jsonHash.Add("secondaryRegion",1)
                        $jsonHash.Add("keypad2ID",0)
                        $jsonHash.Add("timespeckp2",1)
                        $jsonHash.Add("threatlvlgrpkp2",0)
                        $jsonHash.Add("timespecrd2",1)
                        $jsonHash.Add("turnstileenabled","on")
                        $jsonHash.Add("minSirenTime",'')
                        $jsonHash.Add("heldAlarmReportTime",'')
                        $jsonHash.Add("forcedAlarmReportTime",'')
                        $jsonHash.Add("twoManRuleEnabled","on")
                        $jsonHash.Add("timespectmr",1)
                        $jsonHash.Add("threatlvlgrptmr",0)
                        $jsonHash.Add("doublecardenabled","on")
                        $jsonHash.Add("timespecdcp",1)
                        $jsonHash.Add("threatlvlgrpdcp",0)
                        $jsonHash.Add("timedunlockenabled","on")
                        $jsonHash.Add("threatlvlgrpsap",0)
                        $jsonHash.Add("threatlvlgrpuip",0)
                        $jsonHash.Add("threatlvlgrpuipmerc",0)
                        $jsonHash.Add("threatlvlgrpovrlckdp",0)
                        $jsonHash.Add("threatlvlgrpovrctrlp",0)
                        $jsonHash.Add("maskforced","on")
                        $jsonHash.Add("maskheld","on")
                        $jsonHash.Add("forcedOutputID",0)
                        $jsonHash.Add("heldOutputID",0)
                        $jsonHash.Add("invalidOutputID",0)
                        $jsonHash.Add("validOutputID",0)
                        $jsonHash.Add("forcedOutputTime",0)
                        $jsonHash.Add("heldOutputTime",0)
                        $jsonHash.Add("invalidOutputTime",0)
                        $jsonHash.Add("validOutputTime",0)
                        $jsonHash.Add("falmenabled","on")
                        $jsonHash.Add("halmenabled","on")
                        $jsonHash.Add("ialmenabled","on")
                        $jsonHash.Add("ulalmenabled","on")
                        $jsonHash.Add("fevtoid",0)
                        $jsonHash.Add("hevtoid",0)
                        $jsonHash.Add("ievtoid",0)
                        $jsonHash.Add("ulevtoid",0)
                        $jsonHash.Add("valmenabled","on")
                        $jsonHash.Add("dalmenabled","on")
                        $jsonHash.Add("dcpmenabled","on")
                        $jsonHash.Add("vevtoid",0)
                        $jsonHash.Add("devtoid",0)
                        $jsonHash.Add("dcptoid",0)
                        $jsonHash.Add("save","Save")
                        $jsonHash.Add("urlOk","portaldetail.asp")
                        $jsonHash.Add("urlError","portaldetail.asp")
                        $jsonHash.Add("focusfield","newName")
                        $jsonHash.Add("smid",-1)
                        $jsonHash.Add("currentPageAction", "add")
                        $jsonHash.Add(".mysqlQuery8","savePortal.1i;$($jsonHash.networkNode);$(Set-Null -check $($jsonHash.reader1ID));null;null;null;null;null;$(Set-Null -check $($jsonHash.lockResourceID));$(Set-Null -check $($jsonHash.dsmResourceID));$(Set-Null -check $($jsonHash.rexResourceID));0;0;0;0;10;true;5;20;true;false;false;false;0;null;1;null;null;1;null;null;1;null;$($UIStamp);30;null;0;false;false;1;null;false;1;null;false;false;false;null;null;null;null;0;null;null;false;$($Portal.PortalName)")
                        $jsonHash.Add(".mysqlQuery9","triggerPortal.1;$($jsonHash.reader1ID)")		
                        $jsonHash.Add(".mysqlQuery10","saveRegionPortalMap.1i;$($UIStamp);1;1")
                        $jsonHash.Add(".mysqlQuery11","saveLocationPortalMap.1i;$($UIStamp);1")


                        Add-Portal -PortalObj $jsonHash -LogFile $LogFile 
                        $currentPortal=$Portal.PortalName
                    }
                }
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		   }
        }

        #Get Transact Pannel ObjectID - Useing the NETBOX Web URL 
        Function Get_NetworkNodeHash{
        [CmdletBinding(PositionalBinding=$false)]
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Get the Transact Node Object IDs"
            $uriPath = "nbws/api/networknode"
           try { 
             $output = Step-GetJsonURL -uriPath $uriPath -UserFrendlyName $UserFrendlyName -LogFile $LogFile
             Foreach ($node in $output.rows){
                if(!$Script:NetworkNodeHash.ContainsKey($node.name))
                   {            
                        $Script:NetworkNodeHash.add($node.name, $node)
                        $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: $($node.name),$($node.id)"
			            $LogMesg = $LogMesg.Trim()
		                Add-Log -Message $LogMesg -LogFile $LogFile
			            Write-Output $LogMesg  
                    }
                }

            
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		    }
        }

        #Get Reader ObjectID - Useing the NETBOX Web URL 
        Function Get_ReaderHash{
        [CmdletBinding(PositionalBinding=$false)]
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Get the Reader Object IDs"
            $uriPath = "nbws/api/allreaderlimited"
           try { 
             $output = Step-GetJsonURL -uriPath $uriPath -UserFrendlyName $UserFrendlyName -LogFile $LogFile
             Foreach ($node in $output.rows){
                if(!$Script:ReaderHash.ContainsKey($node.name))
                   {            
                        $Script:ReaderHash.add($node.name, $node)
                        $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: $($node.name),$($node.id)"
			            $LogMesg = $LogMesg.Trim()
		                Add-Log -Message $LogMesg -LogFile $LogFile
			            Write-Output $LogMesg  
                    }
                }

            
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		    }
        }
		
        #Get Input Type ObjectID - Useing the NETBOX Web URL 
        Function Get_InputeHash{
        [CmdletBinding(PositionalBinding=$false)]
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Get the Inputs Object IDs"
            $uriPath = "nbws/api/input"
           try { 
             $output = Step-GetJsonURL -uriPath $uriPath -UserFrendlyName $UserFrendlyName -LogFile $LogFile
             Foreach ($node in $output.rows){
                if(!$Script:InputsHash.ContainsKey($node.name))
                   {            
                        $Script:InputsHash.add($node.name, $node)
                        $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: $($node.name),$($node.id)"
			            $LogMesg = $LogMesg.Trim()
		                Add-Log -Message $LogMesg -LogFile $LogFile
			            Write-Output $LogMesg  
                    }
                }

            
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		    }
        }
		
		#Get Input Type ObjectID - Useing the NETBOX Web URL 
        Function Get_OutputsHash{
        [CmdletBinding(PositionalBinding=$false)]
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Get the Outputs Object IDs"
            $uriPath = "nbws/api/output"
           try { 
             $output = Step-GetJsonURL -uriPath $uriPath -UserFrendlyName $UserFrendlyName -LogFile $LogFile
             Foreach ($node in $output.rows){
                if(!$Script:OutputsHash.ContainsKey($node.name))
                   {            
                        $Script:OutputsHash.add($node.name, $node)
                        $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: $($node.name),$($node.id)"
			            $LogMesg = $LogMesg.Trim()
		                Add-Log -Message $LogMesg -LogFile $LogFile
			            Write-Output $LogMesg  
                    }
                }

            
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		    }
        }
	 
		#Add Input - Useing the NETBOX Web URL 
        Function Add-Portal{
        [CmdletBinding(PositionalBinding=$false)]
        Param (
            [Parameter(Mandatory)][object] $PortalObj,
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Add Portal"

            $body = $PortalObj
            $ProgressPreference = 'SilentlyContinue'

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            [Net.ServicePointManager]::Expect100Continue = $false
            [Net.ServicePointManager]::DefaultConnectionLimit = 100

            try {
                # Build the same x-www-form-urlencoded POST body that Invoke-WebRequest was creating,
                # but send it with a lower-level HttpWebRequest so we can force HTTP/1.0 and no KeepAlive.
                $formPairs = New-Object System.Collections.Generic.List[string]
                foreach ($entry in $PortalObj.GetEnumerator()) {
                    $key = [System.Uri]::EscapeDataString([string]$entry.Key)
                    $value = ""
                    if ($null -ne $entry.Value) {
                        $value = [System.Uri]::EscapeDataString([string]$entry.Value)
                    }
                    $formPairs.Add("$key=$value")
                }
                $postData = [string]::Join("&", $formPairs.ToArray())
                $postBytes = [System.Text.Encoding]::UTF8.GetBytes($postData)

                $uri = New-Object System.Uri("$($Script:varhtml)://$($Script:urihost)/goform/Dmf/")
                $request = [System.Net.HttpWebRequest]::Create($uri)
                $request.Method = "POST"
                $request.ProtocolVersion = [Version]"1.0"
                $request.KeepAlive = $false
                $request.AllowWriteStreamBuffering = $true
                $request.Timeout = 120000
                $request.ReadWriteTimeout = 120000
                $request.ContentType = "application/x-www-form-urlencoded"
                $request.ContentLength = $postBytes.Length
                $request.UserAgent = "Mozilla/5.0"
                $request.Referer = "$($Script:varhtml)://$($Script:urihost)/portaldetail.asp?defaultIndex=0&src=&showChrome=1"
                $request.Headers.Add("Origin", "$($Script:varhtml)://$($Script:urihost)")
                $request.Headers.Add("Upgrade-Insecure-Requests", "1")

                $request.CookieContainer = New-Object System.Net.CookieContainer
                $request.CookieContainer.Add((New-Object System.Net.Cookie(".sessionId", "$($Script:sessionID)", "/", "$($Script:urihost)")))

                $requestStream = $request.GetRequestStream()
                $requestStream.Write($postBytes, 0, $postBytes.Length)
                $requestStream.Close()

                $response = $request.GetResponse()
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                $responseText = $reader.ReadToEnd()
                $reader.Close()
                $response.Close()

                $object = [PSCustomObject]@{
                    RawContentLength = $responseText.Length
                    Content = $responseText
                    id = $response.StatusCode
                }

                if ($object.RawContentLength -gt 100) {
                    $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName): $($PortalObj.newName) :: $($object.id)"
                    Add-Log -Message $LogMesg -LogFile $LogFile
                    Write-Output $LogMesg
                }
                else {
                    $LogMesg = "$($LogDateTime)`t| e |`t$($UserFrendlyName): $($PortalObj.newName) :: $($object.Content) `n"
                    $LogMesg += "-------------------------------------------------------------`n"
                    $LogMesg = $LogMesg.Trim()
                    Add-Log -Message $LogMesg -LogFile $LogFile
                    Write-Warning $LogMesg
                    $Script:errors += "$($LogMesg)`n"
                    $Script:errors = $Script:errors.Trim()
                }
            }
            catch {
                $LogMesg = "$($LogDateTime)`t| e |`tPOST failed for portal '$($PortalObj.newName)' to $($Script:varhtml)://$($Script:urihost)/goform/Dmf/`n"
                $LogMesg += "$($LogDateTime)`t| e |`tException: $($_.Exception.Message)`n"

                if ($_.Exception.InnerException) {
                    $LogMesg += "$($LogDateTime)`t| e |`tInnerException: $($_.Exception.InnerException.Message)`n"
                }

                if ($_.Exception.Response) {
                    $LogMesg += "$($LogDateTime)`t| e |`tHTTP Status: $($_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)`n"
                    try {
                        $errorReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                        $errorBody = $errorReader.ReadToEnd()
                        $errorReader.Close()
                        if ($errorBody) {
                            $LogMesg += "$($LogDateTime)`t| e |`tResponse Body: $($errorBody)`n"
                        }
                    } catch {}
                }

                $LogMesg += "$($LogDateTime)`t| e |`tLine: $($_.InvocationInfo.ScriptLineNumber)`n"
                $LogMesg += "-------------------------------------------------------------`n"
                $LogMesg = $LogMesg.Trim()

                Add-Log -Message $LogMesg -LogFile $LogFile
                $Script:Errors += "$($LogMesg)`n"

                Write-Warning $LogMesg
            }
        }

        #
		Function Get_portalsHash{
			[CmdletBinding(PositionalBinding=$false)]
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Get the Outputs Object IDs"
            $uriPath = "/nbws/configinfo/portalgroups"
           try { 
             $output = Step-GetJsonURL -uriPath $uriPath -UserFrendlyName $UserFrendlyName -LogFile $LogFile
             Foreach ($node in $output.rows){
                if(!$Script:PortalsHash.ContainsKey($node.name))
                   {            
                        $Script:PortalsHash.add($node.name, $node)
                        $LogMesg = "$($LogDateTime)`t| i |`t$($UserFrendlyName) Url: $($uriPath) :: $($node.name),$($node.id)"
			            $LogMesg = $LogMesg.Trim()
		                Add-Log -Message $LogMesg -LogFile $LogFile
			            Write-Output $LogMesg  
                    }
                }

            
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName) ::  $($PSItem.toString()) "
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		    }
		}
		#
        Function Step-Validate{
        [CmdletBinding(PositionalBinding=$false)]
        Param (
			[Parameter(Mandatory)][string] $LogFile
        )
            [string]$LogDateTime = Get-Date -format "yyyy-MM-dd`tHH:m:ss"
		    $UserFrendlyName = "Validate Accces Level Groups"
            try {
                #Write-Output $Script:TimeSpecGroupFiltered
                foreach ($object in $Script:RawData ){
                     if($object.name -ne $null -and !$S2AccessLevelGroupHash.ContainsKey($object.name)){
                        $LogMesg = "$($LogDateTime)`t| e |`tError $($UserFrendlyName) :: $($object.name) is NOT in the S2 System.`n"
				        $LogMesg = $LogMesg.trim()
				        Add-Log -Message $LogMesg -LogFile $LogFile
				        Write-Warning $LogMesg 
                     } else {
                        if($object.AccessLevel -ne $null -and  !$($S2AccessLevelGroupHash[$object.name].accessLevelIds).Contains($Script:AccessLevelHash[$object.AccessLevel].id)){
                            $LogMesg = "$($LogDateTime)`t| e |`tError $($UserFrendlyName) :: Asscess level $($object.AccessLevel),#$($Script:AccessLevelHash[$object.AccessLevel].id) is NOT assigened to $($object.name) is NOT in the S2 System. ($($S2AccessLevelGroupHash[$object.name].accessLevelIds))`n"
				            $LogMesg = $LogMesg.trim()
				            Add-Log -Message $LogMesg -LogFile $LogFile
				            Write-Warning $LogMesg
                        }
                     }
                }
            } catch {
				$LogMesg = "$($LogDateTime)`t| e |`t$($PSItem.InvocationInfo.InvocationName) :: Error $($UserFrendlyName)"
				$LogMesg += "`n$($PSItem.InvocationInfo.InvocationName) @ $($PSItem.InvocationInfo.Script.PSCommandPath) line $($PSItem.InvocationInfo.ScriptLineNumber)`n" 
				$LogMesg = $LogMesg.trim()
				Add-Log -Message $LogMesg -LogFile $LogFile
				$Script:Errors += $PSItem.Exception.ToString()
				Write-Warning $LogMesg 
		    }
        }
       
    #endregion File Cmdlets
#endregion Main Cmdlets

#------------------------------------------------------------------------------#
#MAIN UI
#------------------------------------------------------------------------------#
#region Main UI
	if(!$silent) {
		Write-Output "$($LogFile)"
		Write-host "-------------------------------------------------------------" -ForegroundColor Yellow
		Step-Login -User $($Script:S2Credentials.GetNetworkCredential().username) -Password $($Script:S2Credentials.GetNetworkCredential().password) -LogFile $Script:LogFile
        Get-CSRFToken -LogFile $Script:LogFile
		InputCSV -filename $inputFile -LogFile $Script:LogFile
        #region File Logic
            Get_NetworkNodeHash -LogFile $Script:LogFile
            Get_ReaderHash -LogFile $Script:LogFile
			Get_OutputsHash -LogFile $Script:LogFile
			Get_InputeHash -LogFile $Script:LogFile
            Step-paresFile -LogFile $Script:LogFile

            Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
            #Step-Validate -LogFile $Script:LogFile
        #endregion File Logic
		Step-Logout -LogFile $Script:LogFile
		Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
		if ($Script:Errors -ne $null ){
			$LogMesg = "`n$($Script:datetime)`t| e |`tErrors : "
			Add-Log -Message $LogMesg -LogFile $LogFile
			Write-Error $LogMesg
			Add-Log -Message $($Script:Errors -join " ") -LogFile $LogFile
            Write-Error "`n$($Script:Errors -join "`n")"
            #$Script:Errors |Format-List
			Write-host "-------------------------------------------------------------"  -ForegroundColor Yellow
		}
	}
	#Write-host $Script:datetime "| v | Verbose Output : " 
#endregion Main UI