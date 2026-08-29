BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $proposal = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/PART-B-entry-output-slice.md') -Raw
}
Describe 'Issue 109 EntryOutputSlice erratum' {
    It 'defines the dedicated domain and exact byte projection' {
        $proposal | Should -Match 'candidate-entry-content/v1'
        $proposal | Should -Match 'exact slice bytes'
        $proposal | Should -Match 'without path, offset, length, JSON'
        $proposal | Should -Match 'same bytes retain the same hash'
        $proposal | Should -Not -Match 'active-m3u/v2.*slice'
    }
    It 'defines bounds, path, positive length, and fail-closed rules' {
        $proposal | Should -Match '(?s)ByteLength.*MUST be positive'
        $proposal | Should -Match 'overflow-safe'
        $proposal | Should -Match 'less than or equal'
        $proposal | Should -Match 'merged.m3u'
        $proposal | Should -Match 'fail closed'
    }
    It 'preserves v8 acceptance semantics and advances candidate version' {
        $readme = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/README.md') -Raw
        $readme | Should -Match 'blocker-2-contract/v9'
        $readme | Should -Match 'blocker-2-contract/v8`\.'
        $readme | Should -Match 'blocker-2-contract/v8-acceptance'
        $readme | Should -Match 'semantics are unchanged'
    }
}
