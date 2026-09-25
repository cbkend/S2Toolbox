<#
.SYNOPSIS
 Defines published LenelS2 NetBox Web endpoint metadata.

.DESCRIPTION
    Contains data-only endpoint definitions consumed by S2.webApi.psm1.

    Internal Web API and Mercury endpoints are intentionally excluded.
.NOTES
    FileName   : S2.WebApi.Endpoints.psd1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Version    : 1.0.0

.CHANGELOG
    1.0.0
     - Extracted published web endpoint metadata from S2.WebApi.psm1
#>


@{

    PortalConfiguration = @{
        Path        = '/nbws/configinfo/portalgroups/'
        Method      = 'Get'
        Category    = 'Configuration'
        Action      = 'Read'
        Description = 'Returns portal-related configuration options.'
    }

    NodeSummary         = @{
        Path        = '/nbws/view/nodesummary/'
        Method      = 'Get'
        Category    = 'Monitoring'
        Action      = 'Read'
        Description = 'Returns current node status information.'
    }

}