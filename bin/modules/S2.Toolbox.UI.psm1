<#
.SYNOPSIS
    Provides console helpers and the functional WPF launcher for S2 Toolbox.

.DESCRIPTION
    Loads the S2 Toolbox XAML view, discovers executable scripts, creates
    accessible launch buttons, filters scripts, and starts selected scripts in
    a separate Windows PowerShell process.

    Credentials are never placed on a process command line. When both username
    and password are entered, a PSCredential is exported to a temporary CLIXML
    file protected for the current Windows user. The child process imports and
    deletes the file. If connection values are omitted, they are not passed;
    the selected script is responsible for prompting interactively.

.NOTES
    FileName: S2.Toolbox.UI.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1 and WPF
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Initial release.

#>

#requires -Version 5.1
Set-StrictMode -Version Latest
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH_mm_ss_fff'
[string]  $LogFile = "S2.Toolbox.$timestamp.log"

#region Bootstrap
$bootstrapPath = Join-Path --Path $PSScriptRoot -ChildPath 'S2.ToolboxBootStrap.psm1'

if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    # The logging module is not available when the bootstrap file itself is missing.
    throw "Required S2 Toolbox bootstrap loader was not found: $bootstrapPath"
}

. $bootstrapPath
#endregion Bootstrap

#region WPF Initialization

function Initialize-S2Wpf {
    [CmdletBinding()]
    param()

    $Message = "Initialize Windows Forms."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    foreach ($assemblyName in @(
            'PresentationFramework',
            'PresentationCore',
            'WindowsBase'
        )) {
        Add-Type -AssemblyName $assemblyName -ErrorAction Stop
    }
}

#endregion WPF Initialization

#region Console UI

function Show-S2Banner {
    [CmdletBinding()]
    param(
        [string] $Title = 'S2 Toolbox',
        [string] $Version = '4.2.0'
    )

    Clear-Host
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host (' {0} Version {1}' -f $Title, $Version) -ForegroundColor Green
    Write-Host ('=' * 60) -ForegroundColor Cyan
}

function Write-S2Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string] $Level = 'Info'
    )

    $configuration = @{
        Info    = @{ Tag = 'INFO'; Color = 'White' }
        Success = @{ Tag = ' OK '; Color = 'Green' }
        Warning = @{ Tag = 'WARN'; Color = 'Yellow' }
        Error   = @{ Tag = 'FAIL'; Color = 'Red' }
    }

    Write-Host `
    ('[{0}] {1}' -f $configuration[$Level].Tag, $Message) `
        -ForegroundColor $configuration[$Level].Color
}

function Show-S2Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Hashtable
    )

    $Hashtable.GetEnumerator() |
    Sort-Object Key |
    Format-Table Key, Value -AutoSize
}

function Show-S2Object {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject
    )

    process {
        $InputObject | Format-List *
    }
}

function Show-S2Divider {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int] $Length = 70,

        [char] $Character = '='
    )

    Write-Host ([string] $Character * $Length)
}

function Confirm-S2Action {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message
    )

    $answer = Read-Host "$Message (Y/N)"
    return (
        -not [string]::IsNullOrWhiteSpace($answer) -and
        $answer.Trim() -match '^(?i:y|yes)$'
    )
}

function Show-S2Progress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Activity,

        [int] $Current,

        [int] $Total,

        [int] $Id = 0
    )

    $percent = if ($Total -le 0) {
        0
    }
    else {
        [Math]::Min(
            100,
            [Math]::Max(0, [Math]::Round((100.0 * $Current) / $Total, 0))
        )
    }

    Write-Progress `
        -Id $Id `
        -Activity $Activity `
        -Status "$Current / $Total" `
        -PercentComplete $percent
}

function Complete-S2Progress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Activity,

        [int] $Id = 0
    )

    Write-Progress -Id $Id -Activity $Activity -Completed
}

#endregion Console UI

#region Private WPF Helpers

function Write-S2GuiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $LogBox,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogBox.AppendText("$timestamp - $Message`r`n")
    $LogBox.ScrollToEnd()
}

function Get-S2ScriptCategory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    foreach ($category in @('Add', 'Modify', 'Delete')) {
        if ($Name -match "(?i)(?:^|[._-])$category(?:[._-]|$)") {
            return $category.ToUpperInvariant()
        }
    }

    return $null
}

function Get-S2ScriptDisplayName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FileName
    )

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $name = $name -replace '(?i)^S2[._-]?', ''
    $name = $name -replace '(?i)_v\d+(?:\.\d+){2}$', ''
    $name = $name -replace '[._-]+', ' '
    return $name.Trim()
}

function Get-S2ScriptParameterNames {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $ScriptPath
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath,
        [ref] $tokens,
        [ref] $parseErrors
    )

    if (@($parseErrors).Count -gt 0) {
        throw (
            "Unable to inspect script parameters for '$ScriptPath': {0}" -f
            (($parseErrors | ForEach-Object Message) -join '; ')
        )
    }

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    if ($null -ne $ast.ParamBlock) {
        foreach ($parameter in $ast.ParamBlock.Parameters) {
            [void] $names.Add($parameter.Name.VariablePath.UserPath)
        }
    }

    return , $names
}

function Get-S2PreferredParameterName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]] $AvailableNames,

        [Parameter(Mandatory)]
        [string[]] $Candidates
    )

    foreach ($candidate in $Candidates) {
        if ($AvailableNames.Contains($candidate)) {
            return $candidate
        }
    }

    return $null
}

function ConvertTo-S2SingleQuotedLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    return "'{0}'" -f ($Value -replace "'", "''")
}

function New-S2ChildCommand {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]] $ParameterNames,

        [AllowEmptyString()]
        [string] $HostValue,

        [AllowEmptyString()]
        [string] $Username,

        [AllowEmptyString()]
        [string] $Protocol,

        [AllowEmptyString()]
        [string] $CredentialPath
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    [void] $lines.Add("`$ErrorActionPreference = 'Stop'")
    [void] $lines.Add('$invokeArguments = @{}')
    [void] $lines.Add('$credential = $null')
    [void] $lines.Add('try {')

    if (-not [string]::IsNullOrWhiteSpace($CredentialPath)) {
        $credentialLiteral = ConvertTo-S2SingleQuotedLiteral $CredentialPath
        [void] $lines.Add(
            "    `$credential = Import-Clixml -LiteralPath $credentialLiteral"
        )
    }

    $hostParameter = Get-S2PreferredParameterName `
        -AvailableNames $ParameterNames `
        -Candidates @('HostValue', 'HostName', 'Host')
    if (-not [string]::IsNullOrWhiteSpace($HostValue) -and $hostParameter) {
        $hostLiteral = ConvertTo-S2SingleQuotedLiteral $HostValue
        [void] $lines.Add(
            "    `$invokeArguments['$hostParameter'] = $hostLiteral"
        )
    }

    $protocolParameter = Get-S2PreferredParameterName `
        -AvailableNames $ParameterNames `
        -Candidates @('Protocol')
    if (-not [string]::IsNullOrWhiteSpace($Protocol) -and $protocolParameter) {
        $protocolLiteral = ConvertTo-S2SingleQuotedLiteral $Protocol
        [void] $lines.Add(
            "    `$invokeArguments['$protocolParameter'] = $protocolLiteral"
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($CredentialPath)) {
        $credentialParameter = Get-S2PreferredParameterName `
            -AvailableNames $ParameterNames `
            -Candidates @('Credential')

        if ($credentialParameter) {
            [void] $lines.Add(
                "    `$invokeArguments['$credentialParameter'] = `$credential"
            )
        }
        else {
            $usernameParameter = Get-S2PreferredParameterName `
                -AvailableNames $ParameterNames `
                -Candidates @('S2User', 'Username')
            $passwordParameter = Get-S2PreferredParameterName `
                -AvailableNames $ParameterNames `
                -Candidates @('S2Password', 'Password')

            if ($usernameParameter) {
                [void] $lines.Add(
                    "    `$invokeArguments['$usernameParameter'] = `$credential.UserName"
                )
            }
            if ($passwordParameter) {
                [void] $lines.Add(
                    "    `$invokeArguments['$passwordParameter'] = `$credential.Password"
                )
            }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Username)) {
        $usernameParameter = Get-S2PreferredParameterName `
            -AvailableNames $ParameterNames `
            -Candidates @('S2User', 'Username')
        if ($usernameParameter) {
            $usernameLiteral = ConvertTo-S2SingleQuotedLiteral $Username
            [void] $lines.Add(
                "    `$invokeArguments['$usernameParameter'] = $usernameLiteral"
            )
        }
    }

    $scriptLiteral = ConvertTo-S2SingleQuotedLiteral $ScriptPath
    [void] $lines.Add("    & $scriptLiteral @invokeArguments")
    [void] $lines.Add('}')
    [void] $lines.Add('finally {')

    if (-not [string]::IsNullOrWhiteSpace($CredentialPath)) {
        $credentialLiteral = ConvertTo-S2SingleQuotedLiteral $CredentialPath
        [void] $lines.Add(
            "    Remove-Item -LiteralPath $credentialLiteral -Force -ErrorAction SilentlyContinue"
        )
    }

    [void] $lines.Add('}')
    return ($lines -join [Environment]::NewLine)
}

function Start-S2ToolScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [AllowEmptyString()]
        [string] $HostValue,

        [AllowEmptyString()]
        [string] $Username,

        [System.Security.SecureString] $SecurePassword,

        [AllowEmptyString()]
        [string] $Protocol = 'https'
    )

    $parameterNames = Get-S2ScriptParameterNames -ScriptPath $ScriptPath
    $credentialPath = ''

    try {
        if (-not [string]::IsNullOrWhiteSpace($Username) -and
            $null -ne $SecurePassword -and
            $SecurePassword.Length -gt 0) {
            $credential = [System.Management.Automation.PSCredential]::new(
                $Username.Trim(),
                $SecurePassword
            )
            $credentialPath = Join-Path `
                -Path ([System.IO.Path]::GetTempPath()) `
                -ChildPath ('S2Toolbox_{0}.credential.clixml' -f [guid]::NewGuid())
            $credential | Export-Clixml -LiteralPath $credentialPath -Force
        }

        $childCommand = New-S2ChildCommand `
            -ScriptPath $ScriptPath `
            -ParameterNames $parameterNames `
            -HostValue $HostValue `
            -Username $Username `
            -Protocol $Protocol `
            -CredentialPath $credentialPath

        $encodedCommand = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($childCommand)
        )

        Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @(
            '-NoLogo',
            '-NoProfile',
            '-NoExit',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            $encodedCommand
        ) `
            -ErrorAction Stop | Out-Null
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($credentialPath)) {
            Remove-Item `
                -LiteralPath $credentialPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        throw
    }
}

function New-S2ToolboxButton {
    [CmdletBinding()]
    [OutputType([System.Windows.Controls.Button])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel] $Container,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock] $StatusControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $LogBox,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $HostControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $UsernameControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.PasswordBox] $PasswordControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.ComboBox] $ProtocolControl,

        [int] $TabIndex = 10
    )

    $button = [System.Windows.Controls.Button]::new()
    $button.Content = $Name
    $button.Height = 40
    $button.Margin = '2'
    $button.FontSize = 13
    $button.HorizontalContentAlignment = 'Left'
    $button.IsTabStop = $true
    $button.TabIndex = $TabIndex
    $button.ToolTip = $ScriptPath
    [System.Windows.Automation.AutomationProperties]::SetName(
        $button,
        "Launch $Name"
    )
    [System.Windows.Automation.AutomationProperties]::SetHelpText(
        $button,
        "Starts $Name in a separate Windows PowerShell window."
    )

    $button.Tag = @{
        ScriptPath      = $ScriptPath
        StatusControl   = $StatusControl
        LogBox          = $LogBox
        HostControl     = $HostControl
        UsernameControl = $UsernameControl
        PasswordControl = $PasswordControl
        ProtocolControl = $ProtocolControl
    }

    $button.Add_Click({
            $data = $this.Tag
            try {
                $hostValue = $data.HostControl.Text.Trim()
                $username = $data.UsernameControl.Text.Trim()
                $securePassword = $data.PasswordControl.SecurePassword.Copy()
                $protocol = if ($null -ne $data.ProtocolControl.SelectedItem) {
                    [string] $data.ProtocolControl.SelectedItem.Content
                }
                else {
                    [string] $data.ProtocolControl.Text
                }

                if ($securePassword.Length -gt 0 -and
                    [string]::IsNullOrWhiteSpace($username)) {
                    [System.Windows.MessageBox]::Show(
                        'Enter a username when a password is supplied, or clear the password and let the launched script prompt.',
                        'S2 Toolbox - Username Required',
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                    $data.UsernameControl.Focus() | Out-Null
                    return
                }

                $data.StatusControl.Text = 'Launching...'
                Write-S2GuiLog `
                    -LogBox $data.LogBox `
                    -Message ("Launching {0}" -f $data.ScriptPath)

                Start-S2ToolScript `
                    -ScriptPath $data.ScriptPath `
                    -HostValue $hostValue `
                    -Username $username `
                    -SecurePassword $securePassword `
                    -Protocol $protocol.ToLowerInvariant()

                $data.StatusControl.Text = 'Ready'
            }
            catch {
                $data.StatusControl.Text = 'Launch failed'
                Write-S2GuiLog `
                    -LogBox $data.LogBox `
                    -Message ("Launch failed: {0}" -f $_.Exception.Message)
                [System.Windows.MessageBox]::Show(
                    $_.Exception.Message,
                    'S2 Toolbox - Launch Error',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
            }
        })

    [void] $Container.Children.Add($button)
    return $button
}

#endregion Private WPF Helpers

#region Toolbox Launcher

function Start-S2Toolbox {
    <#
    .SYNOPSIS
        Loads the S2 Toolbox WPF view and starts the graphical launcher.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string] $BinPath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $XamlPath
    )

    Initialize-S2Wpf

    [xml] $xaml = Get-Content `
        -LiteralPath $XamlPath `
        -Raw `
        -ErrorAction Stop
    $reader = [System.Xml.XmlNodeReader]::new($xaml)

    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Dispose()
    }

    $controlNames = @(
        'spAdd', 'spModify', 'spDelete', 'txtSearch', 'txtStatus',
        'txtLog', 'txtHost', 'txtUsername', 'txtPassword', 'cmbProtocol'
    )
    $controls = @{}
    foreach ($controlName in $controlNames) {
        $controls[$controlName] = $window.FindName($controlName)
    }

    $missingControls = @(
        $controlNames | Where-Object { $null -eq $controls[$_] }
    )
    if ($missingControls.Count -gt 0) {
        throw (
            'The XAML is missing required named controls: {0}' -f
            ($missingControls -join ', ')
        )
    }

    if ($controls.cmbProtocol.SelectedIndex -lt 0) {
        $controls.cmbProtocol.SelectedIndex = 1
    }

    $buttons = [System.Collections.Generic.List[object]]::new()
    $tabIndex = 10
    $scripts = @(
        Get-ChildItem `
            -LiteralPath $BinPath `
            -Filter '*.ps1' `
            -File |
        Sort-Object Name
    )

    foreach ($script in $scripts) {
        $category = Get-S2ScriptCategory -Name $script.BaseName
        if ([string]::IsNullOrWhiteSpace($category)) {
            continue
        }

        $container = switch ($category) {
            'ADD' { $controls.spAdd }
            'MODIFY' { $controls.spModify }
            'DELETE' { $controls.spDelete }
        }

        $button = New-S2ToolboxButton `
            -Name (Get-S2ScriptDisplayName -FileName $script.Name) `
            -ScriptPath $script.FullName `
            -Container $container `
            -StatusControl $controls.txtStatus `
            -LogBox $controls.txtLog `
            -HostControl $controls.txtHost `
            -UsernameControl $controls.txtUsername `
            -PasswordControl $controls.txtPassword `
            -ProtocolControl $controls.cmbProtocol `
            -TabIndex $tabIndex
        [void] $buttons.Add($button)
        $tabIndex++
    }

    $controls.txtSearch.Add_GotFocus({
            if ($controls.txtSearch.Text -eq 'Quick Search') {
                $controls.txtSearch.Clear()
                $controls.txtSearch.Foreground = 'Black'
            }
        })

    $controls.txtSearch.Add_LostFocus({
            if ([string]::IsNullOrWhiteSpace($controls.txtSearch.Text)) {
                $controls.txtSearch.Text = 'Quick Search'
                $controls.txtSearch.Foreground = 'Gray'
            }
        })

    $controls.txtSearch.Add_TextChanged({
            $filter = $controls.txtSearch.Text
            if ($filter -eq 'Quick Search') {
                $filter = ''
            }

            foreach ($button in $buttons) {
                $isMatch = [string]::IsNullOrWhiteSpace($filter) -or
                $button.Content.ToString().IndexOf(
                    $filter,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -ge 0

                $button.Visibility = if ($isMatch) {
                    [System.Windows.Visibility]::Visible
                }
                else {
                    [System.Windows.Visibility]::Collapsed
                }
            }
        })

    Write-S2GuiLog -LogBox $controls.txtLog -Message 'S2 Toolbox started.'
    Write-S2GuiLog `
        -LogBox $controls.txtLog `
        -Message ("Discovered {0} launchable script(s)." -f $buttons.Count)
    $controls.txtHost.Focus() | Out-Null
    $window.ShowDialog() | Out-Null
}

#endregion Toolbox Launcher

Export-ModuleMember -Function @(
    'Show-S2Banner',
    'Write-S2Status',
    'Show-S2Hashtable',
    'Show-S2Object',
    'Show-S2Divider',
    'Confirm-S2Action',
    'Show-S2Progress',
    'Complete-S2Progress',
    'Start-S2Toolbox'
)
