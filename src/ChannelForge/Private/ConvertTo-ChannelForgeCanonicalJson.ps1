function ConvertTo-ChannelForgeCanonicalJson {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject)

    # One build serializes hundreds of thousands of values; a compiled writer keeps that to seconds.
    # The rules are unchanged: ordered dictionaries and plain objects only, no floats or negative integers,
    # lowercase \uXXXX escapes for anything outside printable ASCII, and no unpaired surrogates.
    $typeName = 'ChannelForge.CanonicalJsonWriter'
    if ($null -eq ($typeName -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;
using System.Numerics;
using System.Text;

namespace ChannelForge
{
    public static class CanonicalJsonWriter
    {
        // PowerShell hands an empty function result over as this marker, which its own -eq $null treats as null.
        private static readonly object AutomationNullValue = typeof(PSObject).Assembly
            .GetType("System.Management.Automation.Internal.AutomationNull")
            .GetProperty("Value", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic)
            .GetValue(null);

        public static string Write(object value)
        {
            StringBuilder builder = new StringBuilder();
            WriteValue(builder, value);
            return builder.ToString();
        }

        private static void WriteString(StringBuilder builder, string value)
        {
            if (value == null) { builder.Append("null"); return; }
            builder.Append('"');
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                int code = character;
                switch (code)
                {
                    case 8: builder.Append("\\b"); continue;
                    case 9: builder.Append("\\t"); continue;
                    case 10: builder.Append("\\n"); continue;
                    case 12: builder.Append("\\f"); continue;
                    case 13: builder.Append("\\r"); continue;
                    case 34: builder.Append("\\\""); continue;
                    case 92: builder.Append("\\\\"); continue;
                }
                if (code < 0x20 || code > 0x7e)
                {
                    if (code >= 0xd800 && code <= 0xdbff)
                    {
                        if (index + 1 >= value.Length) { throw new InvalidOperationException("Canonical JSON does not allow an unpaired UTF-16 surrogate."); }
                        int next = value[index + 1];
                        if (next < 0xdc00 || next > 0xdfff) { throw new InvalidOperationException("Canonical JSON does not allow an unpaired UTF-16 surrogate."); }
                        builder.Append("\\u").Append(code.ToString("x4", CultureInfo.InvariantCulture));
                        index++;
                        builder.Append("\\u").Append(next.ToString("x4", CultureInfo.InvariantCulture));
                        continue;
                    }
                    if (code >= 0xdc00 && code <= 0xdfff) { throw new InvalidOperationException("Canonical JSON does not allow an unpaired UTF-16 surrogate."); }
                    builder.Append("\\u").Append(code.ToString("x4", CultureInfo.InvariantCulture));
                }
                else { builder.Append(character); }
            }
            builder.Append('"');
        }

        private static void WriteValue(StringBuilder builder, object value)
        {
            if (value == null || object.ReferenceEquals(value, AutomationNullValue)) { builder.Append("null"); return; }
            PSObject wrapper = value as PSObject;
            if (wrapper != null)
            {
                object inner = wrapper.BaseObject;
                if (inner != null && inner.GetType().FullName == "System.Management.Automation.PSCustomObject") { WriteObject(builder, wrapper); return; }
                value = inner;
            }
            if (value == null) { builder.Append("null"); return; }
            if (value is string || value is char) { WriteString(builder, value.ToString()); return; }
            if (value is bool) { builder.Append((bool)value ? "true" : "false"); return; }
            if (value is sbyte || value is short || value is int || value is long)
            {
                if (Convert.ToInt64(value, CultureInfo.InvariantCulture) < 0) { throw new InvalidOperationException("Canonical JSON does not allow negative integers."); }
                builder.Append(Convert.ToString(value, CultureInfo.InvariantCulture)); return;
            }
            if (value is BigInteger)
            {
                if ((BigInteger)value < BigInteger.Zero) { throw new InvalidOperationException("Canonical JSON does not allow negative integers."); }
                builder.Append(((BigInteger)value).ToString(CultureInfo.InvariantCulture)); return;
            }
            if (value is byte || value is ushort || value is uint || value is ulong)
            {
                builder.Append(Convert.ToString(value, CultureInfo.InvariantCulture)); return;
            }
            if (value is decimal || value is double || value is float) { throw new InvalidOperationException("Canonical JSON does not allow floating-point values."); }
            IDictionary dictionary = value as IDictionary;
            if (dictionary != null)
            {
                if (!(value is OrderedDictionary)) { throw new InvalidOperationException("Canonical JSON requires ordered dictionaries."); }
                builder.Append('{'); bool firstEntry = true;
                foreach (DictionaryEntry entry in dictionary)
                {
                    if (!firstEntry) { builder.Append(','); }
                    firstEntry = false;
                    WriteString(builder, LanguagePrimitives.ConvertTo<string>(entry.Key)); builder.Append(':'); WriteValue(builder, entry.Value);
                }
                builder.Append('}'); return;
            }
            IEnumerable sequence = value as IEnumerable;
            if (sequence != null)
            {
                builder.Append('['); bool firstItem = true;
                foreach (object item in sequence)
                {
                    if (!firstItem) { builder.Append(','); }
                    firstItem = false; WriteValue(builder, item);
                }
                builder.Append(']'); return;
            }
            throw new InvalidOperationException("Canonical JSON does not support value type '" + value.GetType().FullName + "'.");
        }

        private static void WriteObject(StringBuilder builder, PSObject value)
        {
            builder.Append('{'); bool firstProperty = true;
            foreach (PSPropertyInfo property in value.Properties)
            {
                if (!firstProperty) { builder.Append(','); }
                firstProperty = false;
                WriteString(builder, property.Name); builder.Append(':'); WriteValue(builder, property.Value);
            }
            builder.Append('}');
        }
    }
}
'@
    }

    try { return [ChannelForge.CanonicalJsonWriter]::Write($InputObject) }
    catch [System.Management.Automation.MethodInvocationException] { throw $_.Exception.InnerException.Message }
}
