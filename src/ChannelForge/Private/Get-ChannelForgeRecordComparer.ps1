function Get-ChannelForgeRecordComparer {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.IComparer[object]])]
    param(
        # One entry per sort key, most important first: 'string:Name', 'long:Name' or 'bool:Name'.
        [Parameter(Mandatory)]
        [ValidatePattern('^(string|long|bool):[A-Za-z]+$')]
        [string[]]$Key
    )

    # Sorting tens of thousands of programme records with a script block costs seconds; this compares the
    # same properties in the same order with the same rules, so List.Sort gives the same order, ties included.
    # string: ordinal compare, null counts as empty. long: numeric compare. bool: false before true.
    $typeName = 'ChannelForge.RecordComparer'
    if ($null -eq ($typeName -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace ChannelForge
{
    public sealed class RecordComparer : IComparer<object>
    {
        private readonly string[] names;
        private readonly char[] kinds;

        public RecordComparer(string[] keys)
        {
            names = new string[keys.Length];
            kinds = new char[keys.Length];
            for (int index = 0; index < keys.Length; index++)
            {
                kinds[index] = keys[index][0];
                names[index] = keys[index].Substring(keys[index].IndexOf(':') + 1);
            }
        }

        private static string AsString(object value)
        {
            if (value == null) { return string.Empty; }
            string text = value as string;
            return text != null ? text : LanguagePrimitives.ConvertTo<string>(value);
        }

        public int Compare(object left, object right)
        {
            PSObject leftRecord = PSObject.AsPSObject(left);
            PSObject rightRecord = PSObject.AsPSObject(right);
            for (int index = 0; index < names.Length; index++)
            {
                object leftValue = leftRecord.Properties[names[index]].Value;
                object rightValue = rightRecord.Properties[names[index]].Value;
                int result;
                switch (kinds[index])
                {
                    case 's': result = string.CompareOrdinal(AsString(leftValue), AsString(rightValue)); break;
                    case 'l': result = Convert.ToInt64(leftValue).CompareTo(Convert.ToInt64(rightValue)); break;
                    default: result = Convert.ToInt32(leftValue) - Convert.ToInt32(rightValue); break;
                }
                if (result != 0) { return result; }
            }
            return 0;
        }
    }
}
'@
    }

    return [ChannelForge.RecordComparer]::new($Key)
}
