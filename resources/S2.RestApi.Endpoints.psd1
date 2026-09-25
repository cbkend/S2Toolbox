<#
.SYNOPSIS
    Defines published LenelS2 NetBox REST endpoint metadata.

.DESCRIPTION
    Contains data-only endpoint definitions consumed by S2.RestApi.psm1.

    This file contains documented read-only endpoints under:

        /nbws/api/
        /nbws/ref/

    Internal Web API and Mercury endpoints are intentionally excluded.

.NOTES
    FileName   : S2.RestApi.Endpoints.psd1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Extracted published REST endpoint metadata from S2.RestApi.psm1
#>

@{
    NetworkNode          = @{
        Path         = '/nbws/api/networknode/'
        Method       = 'Get'
        Category     = 'Network Node'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured network nodes.'
    }

    Input                = @{
        Path         = '/nbws/api/input/'
        Method       = 'Get'
        Category     = 'Input'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured inputs.'
    }

    InputDetail          = @{
        Path         = '/nbws/api/inputdetail/{id}'
        Method       = 'Get'
        Category     = 'Input'
        Action       = 'Read'
        ResponseType = 'Detail'
        Description  = 'Returns detailed configuration for a specific input.'
    }

    Output               = @{
        Path         = '/nbws/api/output/'
        Method       = 'Get'
        Category     = 'Output'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured outputs.'
    }

    OutputDetail         = @{
        Path         = '/nbws/api/outputdetail/{id}'
        Method       = 'Get'
        Category     = 'Output'
        Action       = 'Read'
        ResponseType = 'Detail'
        Description  = 'Returns detailed configuration for a specific output.'
    }

    ReaderSummary        = @{
        Path         = '/nbws/api/readersummary/'
        Method       = 'Get'
        Category     = 'Reader'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns summary information for configured readers.'
    }

    ReaderDetail         = @{
        Path         = '/nbws/api/readerdetail/{id}'
        Method       = 'Get'
        Category     = 'Reader'
        Action       = 'Read'
        ResponseType = 'Detail'
        Description  = 'Returns detailed configuration for a specific reader.'
    }

    ReaderLimited        = @{
        Path         = '/nbws/api/allreaderlimited/'
        Method       = 'Get'
        Category     = 'Reader'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns a lightweight inventory of readers.'
    }

    ReaderGroup          = @{
        Path         = '/nbws/api/readergroup/'
        Method       = 'Get'
        Category     = 'Reader Group'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured reader groups.'
    }

    AccessLevel          = @{
        Path         = '/nbws/api/accesslevel/'
        Method       = 'Get'
        Category     = 'Access Level'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured access levels.'
    }

    AccessLevelGroup     = @{
        Path         = '/nbws/api/accesslevelgroup/'
        Method       = 'Get'
        Category     = 'Access Level Group'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured access level groups.'
    }

    ThreatLevelGroup     = @{
        Path         = '/nbws/api/threatlevelgroup/'
        Method       = 'Get'
        Category     = 'Threat Level Group'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured threat level groups.'
    }

    TimeSpec             = @{
        Path         = '/nbws/api/timespec/'
        Method       = 'Get'
        Category     = 'Time Specification'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured time specifications.'
    }

    TimeSpecGroup        = @{
        Path         = '/nbws/ref/timespecgrps/'
        Method       = 'Get'
        Category     = 'Time Specification Group'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns available time specification groups.'
    }

    InputSupervisionType = @{
        Path         = '/nbws/api/inputsupervisiontype/'
        Method       = 'Get'
        Category     = 'Input Reference'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns supported input supervision types.'
    }

    ReaderType           = @{
        Path         = '/nbws/ref/readertype/'
        Method       = 'Get'
        Category     = 'Reader Reference'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns supported reader types.'
    }

    Event                = @{
        Path         = '/nbws/ref/event/'
        Method       = 'Get'
        Category     = 'Event Reference'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns configured events.'
    }

    NetworkNodeType      = @{
        Path         = '/nbws/ref/networknodetypes/'
        Method       = 'Get'
        Category     = 'Network Node Reference'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns supported network node models.'
    }

    NetworkNodeBoardType = @{
        Path         = '/nbws/api/networkNodeBoardType/'
        Method       = 'Get'
        Category     = 'Network Node Reference'
        Action       = 'Read'
        ResponseType = 'Collection'
        Description  = 'Returns supported controller board layouts.'
    }
}
