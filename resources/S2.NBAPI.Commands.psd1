<#
.SYNOPSIS
    LenelS2 NetBox NBAPI command catalog.

.DESCRIPTION
    Defines NBAPI command metadata used by S2.NBAPI.psm1.

    This file is intentionally data-only and is loaded with
    Import-PowerShellDataFile.

.NOTES
    FileName   : S2.NBAPI.Commands.psd1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Version    : 1.0.0
#>

@{

    # Authentication

    Login                  = @{
        DocumentationPage = 218
        Category          = 'Authentication'
        Action            = 'Login'
        Description       = 'Creates authenticated session'
    }

    Logout                 = @{
        DocumentationPage = 220
        Category          = 'Authentication'
        Action            = 'Logout'
        Description       = 'Terminates authenticated session'
    }

    # Access Levels

    AddAccessLevel         = @{
        DocumentationPage = 76
        Category          = 'Access Level'
        Action            = 'Create'
        Description       = 'Creates Access Level'
    }

    ModifyAccessLevel      = @{
        DocumentationPage = 221
        Category          = 'Access Level'
        Action            = 'Modify'
        Description       = 'Modifies Access Level'
    }

    DeleteAccessLevel      = @{
        DocumentationPage = 110
        Category          = 'Access Level'
        Action            = 'Delete'
        Description       = 'Deletes Access Level'
    }

    # Access Level Groups

    AddAccessLevelGroup    = @{
        DocumentationPage = 78
        Category          = 'Access Level Group'
        Action            = 'Create'
        Description       = 'Creates Access Level Group'
    }

    ModifyAccessLevelGroup = @{
        DocumentationPage = 224
        Category          = 'Access Level Group'
        Action            = 'Modify'
        Description       = 'Modifies Access Level Group'
    }

    DeleteAccessLevelGroup = @{
        DocumentationPage = 111
        Category          = 'Access Level Group'
        Action            = 'Delete'
        Description       = 'Deletes Access Level Group'
    }

    # Holidays

    AddHoliday             = @{
        DocumentationPage = 83
        Category          = 'Holiday'
        Action            = 'Create'
        Description       = 'Creates Holiday'
    }

    ModifyHoliday          = @{
        DocumentationPage = 229
        Category          = 'Holiday'
        Action            = 'Modify'
        Description       = 'Modifies Holiday'
    }

    DeleteHoliday          = @{
        DocumentationPage = 112
        Category          = 'Holiday'
        Action            = 'Delete'
        Description       = 'Deletes Holiday'
    }

    # Portal Groups

    AddPortalGroup         = @{
        DocumentationPage = 94
        Category          = 'Portal Group'
        Action            = 'Create'
        Description       = 'Creates Portal Group'
    }

    ModifyPortalGroup      = @{
        DocumentationPage = 241
        Category          = 'Portal Group'
        Action            = 'Modify'
        Description       = 'Modifies Portal Group'
    }

    DeletePortalGroup      = @{
        DocumentationPage = 115
        Category          = 'Portal Group'
        Action            = 'Delete'
        Description       = 'Deletes Portal Group'
    }

    # Reader Groups

    AddReaderGroup         = @{
        DocumentationPage = 95
        Category          = 'Reader Group'
        Action            = 'Create'
        Description       = 'Creates Reader Group'
    }

    ModifyReaderGroup      = @{
        DocumentationPage = 243
        Category          = 'Reader Group'
        Action            = 'Modify'
        Description       = 'Modifies Reader Group'
    }

    DeleteReaderGroup      = @{
        DocumentationPage = 116
        Category          = 'Reader Group'
        Action            = 'Delete'
        Description       = 'Deletes Reader Group'
    }

    # Time Specs

    AddTimeSpec            = @{
        DocumentationPage = 102
        Category          = 'Time Spec'
        Action            = 'Create'
        Description       = 'Creates Time Spec'
    }

    ModifyTimeSpec         = @{
        DocumentationPage = 248
        Category          = 'Time Spec'
        Action            = 'Modify'
        Description       = 'Modifies Time Spec'
    }

    DeleteTimeSpec         = @{
        DocumentationPage = 118
        Category          = 'Time Spec'
        Action            = 'Delete'
        Description       = 'Deletes Time Spec'
    }

    # Time Spec Groups

    AddTimeSpecGroup       = @{
        DocumentationPage = 103
        Category          = 'Time Spec Group'
        Action            = 'Create'
        Description       = 'Creates Time Spec Group'
    }

    ModifyTimeSpecGroup    = @{
        DocumentationPage = 250
        Category          = 'Time Spec Group'
        Action            = 'Modify'
        Description       = 'Modifies Time Spec Group'
    }

    DeleteTimeSpecGroup    = @{
        DocumentationPage = 119
        Category          = 'Time Spec Group'
        Action            = 'Delete'
        Description       = 'Deletes Time Spec Group'
    }

    # Person

    AddPerson              = @{
        DocumentationPage = 89
        Category          = 'Person'
        Action            = 'Create'
        Description       = 'Creates Person'
    }

    ModifyPerson           = @{
        DocumentationPage = 235
        Category          = 'Person'
        Action            = 'Modify'
        Description       = 'Modifies Person'
    }

    RemovePerson           = @{
        DocumentationPage = 258
        Category          = 'Person'
        Action            = 'Delete'
        Description       = 'Deletes Person'
    }

    # Credential

    AddCredential          = @{
        DocumentationPage = 80
        Category          = 'Credential'
        Action            = 'Create'
        Description       = 'Creates Credential'
    }

    ModifyCredential       = @{
        DocumentationPage = 226
        Category          = 'Credential'
        Action            = 'Modify'
        Description       = 'Modifies Credential'
    }

    RemoveCredential       = @{
        DocumentationPage = 256
        Category          = 'Credential'
        Action            = 'Delete'
        Description       = 'Deletes Credential'
    }

    # Network Nodes

    AddNetworkNode         = @{
        DocumentationPage = 86
        Category          = 'Node'
        Action            = 'Create'
        Description       = 'Creates Network Node'
    }

    ModifyNetworkNode      = @{
        DocumentationPage = 233
        Category          = 'Node'
        Action            = 'Modify'
        Description       = 'Modifies Network Node'
    }

    DeleteNetworkNode      = @{
        DocumentationPage = 114
        Category          = 'Node'
        Action            = 'Delete'
        Description       = 'Deletes Network Node'
    }

    GetAccessLevel         = @{ 
        DocumentationPage = 133
        Category          = 'Access Level'
        Action            = 'Read'
        Description       = 'Returns one access level' 
    }
    GetAccessLevels        = @{
        DocumentationPage = 0
        Category          = 'Access Level'
        Action            = 'Read'
        Description       = 'Returns access level names or keys' 
    }
    GetAccessLevelGroup    = @{ 
        DocumentationPage = 135
        Category          = 'Access Level Group'
        Action            = 'Read'
        Description       = 'Returns one access level group' 
    }
    GetAccessLevelGroups   = @{ 
        DocumentationPage = 137
        Category          = 'Access Level Group'
        Action            = 'Read'
        Description       = 'Returns access level groups' 
    }
    GetHoliday             = @{ 
        DocumentationPage = 162
        Category          = 'Holiday'
        Action            = 'Read'
        Description       = 'Returns one holiday' 
    }
    GetHolidays            = @{
        DocumentationPage = 164
        Category          = 'Holiday'
        Action            = 'Read'
        Description       = 'Returns holiday keys' 
    }
    GetPortalGroup         = @{
        DocumentationPage = 184
        Category          = 'Portal Group'
        Action            = 'Read'
        Description       = 'Returns one portal group' 
    }
    GetPortalGroups        = @{ 
        DocumentationPage = 186
        Category          = 'Portal Group'
        Action            = 'Read'
        Description       = 'Returns portal groups' 
    }
    GetReaderGroup         = @{
        DocumentationPage = 197
        Category          = 'Reader Group'
        Action            = 'Read'
        Description       = 'Returns one reader group' 
    }
    GetReaderGroups        = @{
        DocumentationPage = 199
        Category          = 'Reader Group'
        Action            = 'Read'
        Description       = 'Returns reader groups' 
    }
    GetTimeSpec            = @{
        DocumentationPage = 206
        Category          = 'Time Spec'
        Action            = 'Read'
        Description       = 'Returns one time spec' 
    }
    GetTimeSpecs           = @{ 
        DocumentationPage = 208
        Category          = 'Time Spec'
        Action            = 'Read'
        Description       = 'Returns time specs' 
    }
    GetTimeSpecGroup       = @{ 
        DocumentationPage = 210
        Category          = 'Time Spec Group'
        Action            = 'Read'
        Description       = 'Returns one time spec group' 
    }
    GetTimeSpecGroups      = @{ 
        DocumentationPage = 212
        Category          = 'Time Spec Group'
        Action            = 'Read'
        Description       = 'Returns time spec groups' 
    }
    GetNetworkNode         = @{
        DocumentationPage = 170
        Category          = 'Node'
        Action            = 'Read'
        Description       = 'Returns one network node' 
    }
    GetNetworkNodes        = @{
        DocumentationPage = 172
        Category          = 'Node'
        Action            = 'Read'
        Description       = 'Returns network nodes' 
    }
}