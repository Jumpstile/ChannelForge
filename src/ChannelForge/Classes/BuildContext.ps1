class BuildContext {
    # Unique ID for this build run.
    [string]$BuildId

    # When this build context was created.
    [datetime]$BuildTime

    # ChannelForge version used for this build.
    [string]$Version

    # Root folder of the ChannelForge project.
    [string]$SourceDirectory

    # Imported provider definitions.
    [System.Collections.ArrayList]$Providers

    # Imported playlist definitions.
    [System.Collections.ArrayList]$Playlists

    # Parsed channel objects.
    [System.Collections.ArrayList]$Channels

    # Imported EPG source definitions.
    [System.Collections.ArrayList]$GuideSources

    # Parsed programme/guide entries.
    [System.Collections.ArrayList]$Programmes

    # Build warnings.
    [System.Collections.ArrayList]$Warnings

    # Build errors.
    [System.Collections.ArrayList]$Errors

    # Informational build messages.
    [System.Collections.ArrayList]$Information

    # Build statistics.
    [hashtable]$Statistics

    # Generated output metadata.
    [hashtable]$Outputs

    BuildContext() {
        $this.BuildId = [guid]::NewGuid().ToString()
        $this.BuildTime = Get-Date
        $this.Version = '0.1.0-alpha'
        $this.SourceDirectory = ''
        $this.Providers = [System.Collections.ArrayList]::new()
        $this.Playlists = [System.Collections.ArrayList]::new()
        $this.Channels = [System.Collections.ArrayList]::new()
        $this.GuideSources = [System.Collections.ArrayList]::new()
        $this.Programmes = [System.Collections.ArrayList]::new()
        $this.Warnings = [System.Collections.ArrayList]::new()
        $this.Errors = [System.Collections.ArrayList]::new()
        $this.Information = [System.Collections.ArrayList]::new()
        $this.Statistics = @{}
        $this.Outputs = @{}
    }
}