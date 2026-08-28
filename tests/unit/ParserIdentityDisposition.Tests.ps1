BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function Get-TerminationLayer {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord
        )

        # ScriptStackTrace is the executable evidence for the frame that
        # terminated parsing. InvocationInfo is intentionally not used: a
        # re-thrown PowerShell error may have no command name there.
        $frame = @(
            ([string]$ErrorRecord.ScriptStackTrace -split '\r?\n') |
                Where-Object { $_ -match '^\s*at\s+' }
        )[0]
        if ($frame -match '^\s*at\s+([^,]+),') {
            return $Matches[1].Trim()
        }

        return 'Unresolved'
    }

    function Invoke-ParserCapture {
        param(
            [Parameter(Mandatory)]
            [scriptblock]$ScriptBlock,

            [Parameter(Mandatory)]
            [ValidateSet('M3U', 'XMLTV')]
            [string]$Parser
        )

        try {
            $value = @(& $ScriptBlock)
            return [pscustomobject][ordered]@{
                Parser             = $Parser
                Outcome            = 'Returned'
                TerminationLayer   = "$Parser parser return"
                ErrorMessage       = $null
                ErrorType          = $null
                Value              = $value
            }
        }
        catch {
            return [pscustomobject][ordered]@{
                Parser             = $Parser
                Outcome            = 'Rejected'
                TerminationLayer   = Get-TerminationLayer -ErrorRecord $_
                ErrorMessage       = [string]$_.Exception.Message
                ErrorType          = $_.Exception.GetType().FullName
                Value              = @()
            }
        }
    }

    function New-M3UIdentityCase {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [AllowNull()]
            [AllowEmptyString()]
            [object]$Attribute
        )

        $attributeText = if ($null -eq $Attribute) { '' } else { ' tvg-id="{0}"' -f $Attribute }
        return [pscustomobject][ordered]@{
            Name          = $Name
            RawId         = $Attribute
            ExpectedPresence = if ($null -eq $Attribute) { 'Missing' } else { 'Present' }
            Text          = "#EXTM3U`n#EXTINF:-1$attributeText tvg-name=`"$Name`",$Name`nhttps://example.invalid/live/$Name`n"
        }
    }

    function New-XMLTVIdentityCase {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [AllowNull()]
            [AllowEmptyString()]
            [object]$Attribute
        )

        $attributeText = if ($null -eq $Attribute) { '' } else { ' id="{0}"' -f $Attribute }
        return [pscustomobject][ordered]@{
            Name    = $Name
            RawId   = $Attribute
            Text    = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><tv><channel$attributeText><display-name>$Name</display-name></channel></tv>"
        }
    }
}

Describe 'Parser identity presence and termination disposition' {
    It 'preserves distinct M3U missing, empty, and whitespace tvg-id representations' {
        $cases = @(
            (New-M3UIdentityCase -Name 'missing-id' -Attribute $null)
            (New-M3UIdentityCase -Name 'empty-id' -Attribute '')
            (New-M3UIdentityCase -Name 'whitespace-id' -Attribute '   ')
        )

        $observed = foreach ($case in $cases) {
            $path = Join-Path $TestDrive "$($case.Name).m3u"
            [IO.File]::WriteAllText($path, $case.Text, [Text.UTF8Encoding]::new($false))
            $capture = Invoke-ParserCapture -Parser M3U -ScriptBlock {
                Import-ChannelForgeM3UPlaylist `
                    -Path $path `
                    -Provider 'parser-disposition-fixture' `
                    -Playlist 'identity-presence'
            }

            $capture.Outcome | Should -Be 'Returned' -Because $case.Name
            $capture.TerminationLayer | Should -Be 'M3U parser return' -Because $case.Name
            $capture.ErrorMessage | Should -BeNullOrEmpty -Because $case.Name
            @($capture.Value).Count | Should -Be 1 -Because $case.Name
            $channel = @($capture.Value)[0]
            $channel.RawTvgIdPresence | Should -Be $case.ExpectedPresence -Because $case.Name
            if ($null -eq $case.RawId) {
                $channel.RawTvgId | Should -BeNullOrEmpty -Because $case.Name
                $channel.TvgId | Should -Be '' -Because $case.Name
            }
            else {
                $channel.RawTvgId | Should -Be $case.RawId -Because $case.Name
                $channel.TvgId | Should -Be $case.RawId -Because $case.Name
            }

            [pscustomobject][ordered]@{
                Representation    = $case.Name
                RawTvgIdPresence  = [string]$channel.RawTvgIdPresence
                RawTvgId          = $channel.RawTvgId
                Outcome           = $capture.Outcome
                TerminationLayer = $capture.TerminationLayer
            }
        }

        @($observed).Count | Should -Be 3
        @($observed.RawTvgIdPresence) | Should -Be @('Missing', 'Present', 'Present')
        $observed[1].RawTvgId | Should -Be ''
        $observed[2].RawTvgId | Should -Be '   '
    }

    It 'rejects XMLTV missing, empty, and whitespace channel IDs at the XMLTV parser' {
        $cases = @(
            (New-XMLTVIdentityCase -Name 'missing-id' -Attribute $null)
            (New-XMLTVIdentityCase -Name 'empty-id' -Attribute '')
            (New-XMLTVIdentityCase -Name 'whitespace-id' -Attribute '   ')
        )

        $observed = foreach ($case in $cases) {
            $path = Join-Path $TestDrive "$($case.Name).xml"
            [IO.File]::WriteAllText($path, $case.Text, [Text.UTF8Encoding]::new($false))
            $capture = Invoke-ParserCapture -Parser XMLTV -ScriptBlock {
                Import-ChannelForgeXmltvSource -Path $path -SourceId 'parser-disposition-fixture'
            }

            $capture.Outcome | Should -Be 'Rejected' -Because $case.Name
            # This is extracted from the actual terminating frame, rather than
            # assigned from the expected fixture outcome.
            $capture.TerminationLayer | Should -Be 'Read-ChannelForgeXmltvDocument' -Because $case.Name
            $capture.ErrorMessage | Should -Be 'XMLTV channel elements require a non-empty id attribute.' -Because $case.Name
            $capture.ErrorType | Should -Be 'System.Management.Automation.RuntimeException' -Because $case.Name
            @($capture.Value).Count | Should -Be 0 -Because $case.Name
            $capture.PSObject.Properties['BindingKind'] | Should -BeNullOrEmpty -Because $case.Name
            $capture.PSObject.Properties['Status'] | Should -BeNullOrEmpty -Because $case.Name

            [pscustomobject][ordered]@{
                Representation    = $case.Name
                RawId             = $case.RawId
                Outcome           = $capture.Outcome
                TerminationLayer = $capture.TerminationLayer
                ErrorMessage      = $capture.ErrorMessage
                DownstreamClaims  = @($capture.PSObject.Properties.Name | Where-Object { $_ -in @('BindingKind', 'Status') })
            }
        }

        @($observed).Count | Should -Be 3
        @($observed.Outcome) | Should -Be @('Rejected', 'Rejected', 'Rejected')
        @($observed.TerminationLayer | Select-Object -Unique) | Should -Be @('Read-ChannelForgeXmltvDocument')
        @($observed.DownstreamClaims | Where-Object { $_ }) | Should -BeNullOrEmpty
    }
}
