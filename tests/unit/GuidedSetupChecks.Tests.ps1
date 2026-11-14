BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function Get-TestChecksProposal {
        param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Playlist)
        $rules = Join-Path $Root 'data\rules'
        $lineup = Join-Path $Root 'data\lineup'
        New-Item -ItemType Directory -Force -Path $rules, $lineup | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination $rules
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination $lineup
        $item = [ordered]@{ sourceKey = 'p1'; label = 'p1'; priority = 100; contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Playlist)) }
        $payload = [ordered]@{ schemaVersion = 2; playlists = @([pscustomobject]$item); guides = @(); bindings = @() }
        $body = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 10 -Compress))
        $response = & (Get-Module ChannelForge) {
            param($RequestRoot, $RequestBody)
            Get-ChannelForgeWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $RequestRoot -StaticRoot '' -BodyBytes $RequestBody -ContentType 'application/json' -ContentLength $RequestBody.Length
        } $Root $body
        $response.StatusCode | Should -Be 200
        return ($response.Body | ConvertFrom-Json)
    }
}

Describe 'Guided setup checks before accepting' {
    BeforeAll {
        $script:NoLogo = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
    }

    It 'shows a logo check that needs attention for a channel with no logo' {
        $payload = Get-TestChecksProposal -Root (Join-Path $TestDrive 'logo') -Playlist $script:NoLogo
        $logos = @($payload.Checks | Where-Object { $_.Kind -eq 'logos' })
        $logos.Count | Should -Be 1
        $logos[0].Status | Should -Be 'attention'
        $logos[0].Headline | Should -Not -Match 'Set-ChannelForge'
        $payload.Proposal.CanAccept | Should -BeTrue
        @($payload.Checks | Where-Object { $_.Kind -eq 'categories' })[0].Status | Should -BeIn 'ok', 'attention'
    }

    It 'still returns a ready proposal when the category report fails' {
        Mock -ModuleName ChannelForge Get-ChannelForgeCategoryReport { throw 'C:\secret\place failed' }
        $payload = Get-TestChecksProposal -Root (Join-Path $TestDrive 'cat-fail') -Playlist $script:NoLogo
        $payload.Status | Should -Be 'PROPOSAL_READY'
        $payload.Proposal.CanAccept | Should -BeTrue
        $categories = @($payload.Checks | Where-Object { $_.Kind -eq 'categories' })
        $categories[0].Status | Should -Be 'unavailable'
        $categories[0].Headline | Should -Be 'Category check could not run. You can still accept.'
        ($categories[0] | ConvertTo-Json -Depth 5) | Should -Not -Match 'secret'
    }

    It 'keeps the candidate hash and accept state the same and names no staging path' {
        $rootA = Join-Path $TestDrive 'same-a'
        $rootB = Join-Path $TestDrive 'same-b'
        $a = Get-TestChecksProposal -Root $rootA -Playlist $script:NoLogo
        Mock -ModuleName ChannelForge Get-ChannelForgeGuidedSetupChecks { @() }
        $b = Get-TestChecksProposal -Root $rootB -Playlist $script:NoLogo
        $hashOf = {
            param($Root, $Payload)
            (Get-Content -Raw -LiteralPath (Join-Path $Root "output\.web-guided-setup\proposals\$($Payload.Proposal.ProposalId)\session.json") | ConvertFrom-Json).CandidateManifestHash
        }
        (& $hashOf $rootA $a) | Should -Be (& $hashOf $rootB $b)
        $a.Proposal.CanAccept | Should -Be $b.Proposal.CanAccept
        $text = ($a.Checks | ConvertTo-Json -Depth 6)
        $text | Should -Not -Match 'web-guided-setup'
        $text | Should -Not -Match ([regex]::Escape($rootA))
    }
}
