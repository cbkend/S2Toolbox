<#
.SYNOPSIS
    Launches the S2 Toolbox graphical user interface.

.DESCRIPTION
    Validates the required UI module, XAML view, and Bin directory; imports the
    UI module; and starts the WPF-based S2 Toolbox launcher.

.NOTES
    FileName: Start-S2Toolbox.ps1
    Version: 4.2.0
    Author: Brian Kendrick
    Requires: Windows PowerShell 5.1
    
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#>

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


$modulePath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath 'bin\modules\S2.Toolbox.UI.psm1'
$xamlPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath 'resources\S2.Toolbox.xaml'
$binPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath 'bin'

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Required UI module was not found: $modulePath"
}
if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
    throw "Required XAML view was not found: $xamlPath"
}
if (-not (Test-Path -LiteralPath $binPath -PathType Container)) {
    throw "Required Bin directory was not found: $binPath"
}

Import-Module `
    -Name $modulePath `
    -Force `
    -ErrorAction Stop

Start-S2Toolbox `
    -BinPath $binPath `
    -XamlPath $xamlPath
