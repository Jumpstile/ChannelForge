function Get-ChannelForgeRawXmltvProjection {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Programme,
        [ValidateSet('blocker-2-contract/v7','blocker-2-contract/v8','blocker-2-contract/v10')]
        [string]$CandidateContractVersion = 'blocker-2-contract/v7'
    )

    # Each programme needs one digest and about twenty property reads; as function calls these cost seconds on a large
    # guide, so they run in compiled code. Digest copies every projection property except the three ordinal/digest
    # fields, writes them with the canonical JSON writer and hashes the domain, a zero byte and the UTF-8 JSON, exactly
    # as Get-ChannelForgeDomainHash does. Property and ArrayValue return what Get-PropertyValue and Get-ArrayValue
    # leave in a projection after PowerShell unrolls their output: nothing for empty, the item for one, an array for more.
    $null = ConvertTo-ChannelForgeCanonicalJson -InputObject $null
    if ($null -eq ('ChannelForge.RawXmltvHelper' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Management.Automation;
using System.Security.Cryptography;
using System.Text;

namespace ChannelForge
{
    public static class RawXmltvHelper
    {
        private static readonly Func<object, string> WriteJson = FindWriter();

        private static Func<object, string> FindWriter()
        {
            foreach (System.Reflection.Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type writer = assembly.GetType("ChannelForge.CanonicalJsonWriter", false);
                if (writer != null) { return (Func<object, string>)Delegate.CreateDelegate(typeof(Func<object, string>), writer.GetMethod("Write")); }
            }
            throw new InvalidOperationException("The canonical JSON writer is not loaded.");
        }

        private static readonly object AutomationNullValue = typeof(PSObject).Assembly
            .GetType("System.Management.Automation.Internal.AutomationNull")
            .GetProperty("Value", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic)
            .GetValue(null);

        private static List<object> Items(object value)
        {
            PSObject wrapper = value as PSObject;
            if (wrapper != null && !(wrapper.BaseObject is PSCustomObject)) { value = wrapper.BaseObject; }
            List<object> items = new List<object>();
            IEnumerable sequence = value as IEnumerable;
            if (value == null || value is string || value is IDictionary || sequence == null) { items.Add(value); return items; }
            foreach (object item in sequence) { items.Add(item); }
            return items;
        }

        private static object Unrolled(List<object> items)
        {
            if (items.Count == 0) { return AutomationNullValue; }
            return items.Count == 1 ? items[0] : items.ToArray();
        }

        private static object Unroll(object value)
        {
            if (value == null || object.ReferenceEquals(value, AutomationNullValue)) { return value; }
            return Unrolled(Items(value));
        }

        public static object Property(object source, string name, object fallback)
        {
            PSPropertyInfo property = (source == null || object.ReferenceEquals(source, AutomationNullValue)) ? null : PSObject.AsPSObject(source).Properties[name];
            return Unroll(property != null ? property.Value : fallback);
        }

        public static object ArrayValue(object source, string name)
        {
            object value = Property(source, name, new object[0]);
            if (value == null || object.ReferenceEquals(value, AutomationNullValue)) { return AutomationNullValue; }
            return Unrolled(Items(value));
        }

        public static string Compute(PSObject projection, string domain)
        {
            OrderedDictionary values = new OrderedDictionary();
            foreach (PSPropertyInfo property in projection.Properties)
            {
                if (property.Name.Equals("StructuralOccurrenceOrdinal", StringComparison.OrdinalIgnoreCase) ||
                    property.Name.Equals("RawXMLTVOccurrenceDigest", StringComparison.OrdinalIgnoreCase) ||
                    property.Name.Equals("RawProgrammeDigest", StringComparison.OrdinalIgnoreCase)) { continue; }
                values[property.Name] = property.Value;
            }
            UTF8Encoding utf8 = new UTF8Encoding(false);
            string json = WriteJson(values);
            int domainLength = utf8.GetByteCount(domain);
            byte[] buffer = new byte[domainLength + 1 + utf8.GetByteCount(json)];
            utf8.GetBytes(domain, 0, domain.Length, buffer, 0);
            utf8.GetBytes(json, 0, json.Length, buffer, domainLength + 1);
            return Convert.ToHexString(SHA256.HashData(buffer)).ToLowerInvariant();
        }
    }
}
'@
    }

    function Get-PropertyValue {
        param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Default = $null)
        $property = if ($null -ne $Object) { $Object.PSObject.Properties[$Name] }
        if ($null -ne $property) {
            return $property.Value
        }
        return $Default
    }
    $logicalSourceIdBySource = @{}
    function Get-LogicalSourceId {
        param([AllowNull()][object]$Occurrence, [AllowNull()][object]$Evidence)
        $value = Get-PropertyValue $Occurrence 'LogicalSourceId'
        if ($null -ne $value -and -not [string]::IsNullOrEmpty([string]$value)) { return [string]$value }
        $sourceId = [string](Get-PropertyValue $Evidence 'SourceId' '')
        if ([string]::IsNullOrEmpty($sourceId)) { $sourceId = [string](Get-PropertyValue $Occurrence 'SourceId' '') }
        # One guide repeats one source id for every channel and programme; hash it once.
        if (-not $logicalSourceIdBySource.ContainsKey($sourceId)) {
            $logicalSourceIdBySource[$sourceId] = Get-ChannelForgeDomainHash -Domain 'logical-source-id/v2' -InputObject ([ordered]@{
                    Version = 'lineup-history-v1'
                    SourceId = $sourceId
                })
        }
        return $logicalSourceIdBySource[$sourceId]
    }
    function Get-ArrayValue {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return @() }
        return @($Value)
    }
    function Get-Digest {
        param([Parameter(Mandatory)][object]$Projection, [Parameter(Mandatory)][string]$Domain)
        try { return [ChannelForge.RawXmltvHelper]::Compute([System.Management.Automation.PSObject]::AsPSObject($Projection), $Domain) }
        catch [System.Management.Automation.MethodInvocationException] { throw $_.Exception.InnerException.Message }
    }
    function Get-ChannelSortKey {
        param([Parameter(Mandatory)][object]$Projection)
        $presenceRank = if ([string]$Projection.RawChannelIdPresence -eq 'Missing') { '0' } else { '1' }
        return @(
            $presenceRank
            [string]$Projection.RawChannelId
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.DisplayNameNodes))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.IconNodes))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.RawChannelExtensions))
            [string]$Projection.RawXMLTVOccurrenceDigest
        ) -join [char]31
    }
    function Get-ProgrammeSortKey {
        param([Parameter(Mandatory)][object]$Projection)
        $presenceRank = if ([string]$Projection.RawProgrammeChannelIdPresence -eq 'Missing') { '0' } else { '1' }
        return @(
            $presenceRank
            [string]$Projection.RawProgrammeChannelId
            [string]$Projection.StartRaw
            [string]$Projection.StopRaw
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.TitleNodes))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.SubTitleNodes))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.DescNodes))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.CategoryNodes))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.EpisodeNumbers))
            [ChannelForge.CanonicalJsonWriter]::Write(@($Projection.RawProgrammeExtensions))
            [string]$Projection.RawProgrammeDigest
        ) -join [char]31
    }

    $channelRecords = [System.Collections.Generic.List[object]]::new()
    $programmeRecords = [System.Collections.Generic.List[object]]::new()
    $seenEvidence = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in @($Programme)) {
        if ($null -eq $value -or $value -isnot [Programme]) { continue }
        $evidence = $value.Evidence
        $evidenceKey = if ($null -eq $evidence) {
            "fallback`u{001f}$([string]$value.SourceId)"
        }
        else {
            @(
                [string](Get-PropertyValue $evidence 'SourceId' '')
                [string](Get-PropertyValue $evidence 'SourcePath' '')
                [string](Get-PropertyValue $evidence 'SourceReference' '')
                [string](Get-PropertyValue $evidence 'DocumentBytes' '')
            ) -join [char]31
        }
        if ($null -ne $evidence -and $seenEvidence.Add($evidenceKey)) {
            foreach ($occurrence in @(Get-PropertyValue $evidence 'RawChannelOccurrences' @())) {
                if ($null -eq $occurrence) { continue }
                $rawId = Get-PropertyValue $occurrence 'RawChannelId'
                $presence = [string](Get-PropertyValue $occurrence 'RawChannelIdPresence' $(if ($null -eq $rawId) { 'Missing' } else { 'Present' }))
                if ($presence -eq 'Missing') { $rawId = $null }
                $projection = [pscustomobject][ordered]@{
                    Version = $CandidateContractVersion
                    LogicalSourceId = Get-LogicalSourceId $occurrence $evidence
                    StructuralOccurrenceOrdinal = 0
                    RawChannelIdPresence = $presence
                    RawChannelId = $rawId
                    DisplayNameNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'DisplayNameNodes' @())
                    IconNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'IconNodes' @())
                    RawChannelExtensions = Get-ArrayValue (Get-PropertyValue $occurrence 'RawChannelExtensions' @())
                }
                [void]$channelRecords.Add([pscustomobject][ordered]@{
                        Projection = $projection
                        Digest = Get-Digest $projection 'raw-xmltv-occurrence/v2'
                    })
                $projection | Add-Member -NotePropertyName RawXMLTVOccurrenceDigest -NotePropertyValue $channelRecords[$channelRecords.Count - 1].Digest -Force
            }
            foreach ($occurrence in @(Get-PropertyValue $evidence 'RawProgrammeOccurrences' @())) {
                if ($null -eq $occurrence) { continue }
                $rawId = Get-PropertyValue $occurrence 'RawProgrammeChannelId'
                $presence = [string](Get-PropertyValue $occurrence 'RawProgrammeChannelIdPresence' $(if ($null -eq $rawId) { 'Missing' } else { 'Present' }))
                if ($presence -eq 'Missing') { $rawId = $null }
                $projection = [pscustomobject][ordered]@{
                    Version = $CandidateContractVersion
                    LogicalSourceId = Get-LogicalSourceId $occurrence $evidence
                    StructuralOccurrenceOrdinal = 0
                    RawProgrammeChannelIdPresence = $presence
                    RawProgrammeChannelId = $rawId
                    StartRaw = [string][ChannelForge.RawXmltvHelper]::Property($occurrence, 'StartRaw', '')
                    StopRaw = [string][ChannelForge.RawXmltvHelper]::Property($occurrence, 'StopRaw', '')
                    TitleNodes = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'TitleNodes')
                    SubTitleNodes = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'SubTitleNodes')
                    DescNodes = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'DescNodes')
                    CategoryNodes = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'CategoryNodes')
                    EpisodeNumbers = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'EpisodeNumbers')
                    Rating = [ChannelForge.RawXmltvHelper]::Property($occurrence, 'Rating', $null)
                    StarRating = [ChannelForge.RawXmltvHelper]::Property($occurrence, 'StarRating', $null)
                    PreviouslyShown = [ChannelForge.RawXmltvHelper]::Property($occurrence, 'PreviouslyShown', $false)
                    Premiere = [ChannelForge.RawXmltvHelper]::Property($occurrence, 'Premiere', [ChannelForge.RawXmltvHelper]::Property($occurrence, 'IsPremiere', $false))
                    LastChance = [ChannelForge.RawXmltvHelper]::Property($occurrence, 'LastChance', $false)
                    Credits = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'Credits')
                    Date = [ChannelForge.RawXmltvHelper]::Property($occurrence, 'Date', $null)
                    IconNodes = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'IconNodes')
                    RawProgrammeExtensions = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, 'RawProgrammeExtensions')
                }
                $record = [pscustomobject][ordered]@{
                    Projection = $projection
                    Digest = Get-Digest $projection 'raw-programme/v2'
                }
                [void]$programmeRecords.Add($record)
                $projection | Add-Member -NotePropertyName RawProgrammeDigest -NotePropertyValue $record.Digest -Force
            }
        }
        if ($null -eq $evidence) {
            $rawId = Get-PropertyValue $value 'RawChannelId' $value.ChannelId
            $projection = [pscustomobject][ordered]@{
                Version = $CandidateContractVersion
                LogicalSourceId = Get-LogicalSourceId $value $null
                StructuralOccurrenceOrdinal = 0
                RawProgrammeChannelIdPresence = if ($null -eq $rawId) { 'Missing' } else { 'Present' }
                RawProgrammeChannelId = if ($null -eq $rawId) { $null } else { [string]$rawId }
                StartRaw = $value.Start.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                StopRaw = $value.End.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                TitleNodes = @([string]$value.Title)
                SubTitleNodes = @([string]$value.Subtitle)
                DescNodes = @([string]$value.Description)
                CategoryNodes = @($value.Categories)
                EpisodeNumbers = @([string]$value.EpisodeNumber)
                Rating = $null
                StarRating = $null
                PreviouslyShown = $false
                Premiere = [bool]$value.IsPremiere
                LastChance = $false
                Credits = @()
                Date = $null
                IconNodes = @()
                RawProgrammeExtensions = @()
            }
            $record = [pscustomobject][ordered]@{
                    Projection = $projection
                    Digest = Get-Digest $projection 'raw-programme/v2'
                }
            [void]$programmeRecords.Add($record)
            $projection | Add-Member -NotePropertyName RawProgrammeDigest -NotePropertyValue $record.Digest -Force
        }
    }

    foreach ($group in @($channelRecords | Group-Object { [string]$_.Projection.LogicalSourceId })) {
        $ordered = @($group.Group | Sort-Object @{ Expression = { Get-ChannelSortKey $_.Projection } })
        for ($index = 0; $index -lt $ordered.Count; $index++) {
            $ordered[$index].Projection.StructuralOccurrenceOrdinal = $index
            $ordered[$index].Projection | Add-Member -NotePropertyName RawXMLTVOccurrenceDigest -NotePropertyValue $ordered[$index].Digest -Force
        }
    }
    foreach ($group in @($programmeRecords | Group-Object { [string]$_.Projection.LogicalSourceId })) {
        $ordered = @($group.Group | Sort-Object @{ Expression = { Get-ProgrammeSortKey $_.Projection } })
        for ($index = 0; $index -lt $ordered.Count; $index++) {
            $ordered[$index].Projection.StructuralOccurrenceOrdinal = $index
            $ordered[$index].Projection | Add-Member -NotePropertyName RawProgrammeDigest -NotePropertyValue $ordered[$index].Digest -Force
        }
    }

    $output = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($channelRecords | Sort-Object `
                @{ Expression = { [string]$_.Projection.LogicalSourceId } }, `
                @{ Expression = { [int]$_.Projection.StructuralOccurrenceOrdinal } })) {
        $projection = [ordered]@{}
        foreach ($property in @($record.Projection.PSObject.Properties)) { $projection[$property.Name] = $property.Value }
        $projection.RawXMLTVOccurrenceDigest = [string]$record.Digest
        [void]$output.Add([pscustomobject]$projection)
    }
    foreach ($record in @($programmeRecords | Sort-Object `
                @{ Expression = { [string]$_.Projection.LogicalSourceId } }, `
                @{ Expression = { [int]$_.Projection.StructuralOccurrenceOrdinal } })) {
        $projection = [ordered]@{}
        foreach ($property in @($record.Projection.PSObject.Properties)) { $projection[$property.Name] = $property.Value }
        $projection.RawProgrammeDigest = [string]$record.Digest
        [void]$output.Add([pscustomobject]$projection)
    }
    return @($output.ToArray())
}
