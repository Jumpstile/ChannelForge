using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;

namespace ChannelForge.Private.Transport
{
    public sealed class ChannelForgePinnedHttpTransportException : Exception
    {
        public string Category { get; }

        internal ChannelForgePinnedHttpTransportException(string category, string detail)
            : base(detail)
        {
            Category = category;
        }
    }

    public sealed class ChannelForgeValidatedEndpoint
    {
        public Uri RequestUri { get; }
        public string TlsHostName { get; }
        public int Port { get; }
        public bool IsLiteralAddress { get; }
        public IReadOnlyList<IPAddress> Candidates { get; }

        internal ChannelForgeValidatedEndpoint(
            Uri requestUri,
            string tlsHostName,
            int port,
            bool isLiteralAddress,
            IReadOnlyList<IPAddress> candidates)
        {
            RequestUri = requestUri;
            TlsHostName = tlsHostName;
            Port = port;
            IsLiteralAddress = isLiteralAddress;
            Candidates = candidates;
        }
    }

    public static class ChannelForgePinnedHttpTransport
    {
        public const string ContractName = "ChannelForgePinnedHttpTransport";
        public const int ContractVersion = 2;

        public const string InvalidEndpointCategory = "InvalidEndpoint";
        public const string DnsFailureCategory = "DnsFailure";
        public const string BlockedDestinationCategory = "BlockedDestination";
        public const string CancelledCategory = "Cancelled";

        private static readonly AddressPrefix[] Ipv4DenyPrefixes =
        {
            AddressPrefix.Parse("0.0.0.0/8"),
            AddressPrefix.Parse("10.0.0.0/8"),
            AddressPrefix.Parse("100.64.0.0/10"),
            AddressPrefix.Parse("127.0.0.0/8"),
            AddressPrefix.Parse("169.254.0.0/16"),
            AddressPrefix.Parse("172.16.0.0/12"),
            AddressPrefix.Parse("192.0.0.0/24"),
            AddressPrefix.Parse("192.0.2.0/24"),
            AddressPrefix.Parse("192.31.196.0/24"),
            AddressPrefix.Parse("192.52.193.0/24"),
            AddressPrefix.Parse("192.88.99.0/24"),
            AddressPrefix.Parse("192.168.0.0/16"),
            AddressPrefix.Parse("192.175.48.0/24"),
            AddressPrefix.Parse("198.18.0.0/15"),
            AddressPrefix.Parse("198.51.100.0/24"),
            AddressPrefix.Parse("203.0.113.0/24"),
            AddressPrefix.Parse("224.0.0.0/4"),
            AddressPrefix.Parse("240.0.0.0/4")
        };

        private static readonly AddressPrefix[] Ipv6DenyPrefixes =
        {
            AddressPrefix.Parse("::/128"),
            AddressPrefix.Parse("::1/128"),
            AddressPrefix.Parse("64:ff9b::/96"),
            AddressPrefix.Parse("64:ff9b:1::/48"),
            AddressPrefix.Parse("100::/64"),
            AddressPrefix.Parse("100:0:0:1::/64"),
            AddressPrefix.Parse("2001::/23"),
            AddressPrefix.Parse("2001:db8::/32"),
            AddressPrefix.Parse("2002::/16"),
            AddressPrefix.Parse("2620:4f:8000::/48"),
            AddressPrefix.Parse("3fff::/20"),
            AddressPrefix.Parse("5f00::/16"),
            AddressPrefix.Parse("fc00::/7"),
            AddressPrefix.Parse("fe80::/10"),
            AddressPrefix.Parse("fec0::/10"),
            AddressPrefix.Parse("ff00::/8"),
            AddressPrefix.Parse("3ffe::/16")
        };

        private static readonly AddressPrefix Ipv6GlobalUnicastPrefix =
            AddressPrefix.Parse("2000::/3");

        public static bool HasRequiredCapabilities()
        {
            if (Environment.Version.Major < 10)
            {
                return false;
            }

            var handlerType = Type.GetType(
                "System.Net.Http.SocketsHttpHandler, System.Net.Http",
                throwOnError: false,
                ignoreCase: false);

            if (handlerType == null)
            {
                return false;
            }

            return handlerType.GetProperty(
                       "ConnectCallback",
                       BindingFlags.Instance | BindingFlags.Public) != null;
        }

        public static async Task<ChannelForgeValidatedEndpoint> ValidateEndpointAsync(
            string endpointText,
            CancellationToken cancellationToken)
        {
            var parsed = ParseEndpoint(endpointText);
            if (parsed.IsLiteralAddress)
            {
                return BuildValidatedEndpoint(parsed, new[] { parsed.LiteralAddress });
            }

            IPAddress[] addresses;
            try
            {
                addresses = await Dns.GetHostAddressesAsync(
                    parsed.TlsHostName,
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw Failure(CancelledCategory, "endpoint resolution was cancelled.");
            }
            catch
            {
                throw Failure(DnsFailureCategory, "endpoint name resolution failed.");
            }

            return BuildValidatedEndpoint(parsed, addresses);
        }

        internal static ChannelForgeValidatedEndpoint ValidateEndpointWithResolver(
            string endpointText,
            Func<string, IPAddress[]> resolver)
        {
            var parsed = ParseEndpoint(endpointText);
            if (parsed.IsLiteralAddress)
            {
                return BuildValidatedEndpoint(parsed, new[] { parsed.LiteralAddress });
            }

            if (resolver == null)
            {
                throw Failure(DnsFailureCategory, "endpoint name resolution failed.");
            }

            IPAddress[] addresses;
            try
            {
                addresses = resolver(parsed.TlsHostName);
            }
            catch
            {
                throw Failure(DnsFailureCategory, "endpoint name resolution failed.");
            }

            return BuildValidatedEndpoint(parsed, addresses);
        }

        private static ParsedEndpoint ParseEndpoint(string endpointText)
        {
            if (string.IsNullOrWhiteSpace(endpointText) ||
                !Uri.TryCreate(endpointText, UriKind.Absolute, out var requestUri))
            {
                throw Failure(InvalidEndpointCategory, "the endpoint URI is malformed or not absolute.");
            }

            if (!string.Equals(requestUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            {
                throw Failure(InvalidEndpointCategory, "the endpoint URI must use HTTPS.");
            }

            if (requestUri.Port != 443)
            {
                throw Failure(InvalidEndpointCategory, "the endpoint URI must use port 443.");
            }

            if (!string.IsNullOrEmpty(requestUri.UserInfo))
            {
                throw Failure(InvalidEndpointCategory, "endpoint URI user information is not permitted.");
            }

            if (string.IsNullOrWhiteSpace(requestUri.Host) ||
                requestUri.Host.IndexOf('%') >= 0 ||
                requestUri.DnsSafeHost.IndexOf('%') >= 0)
            {
                throw Failure(InvalidEndpointCategory, "the endpoint host is malformed or scoped.");
            }

            var hostNameType = Uri.CheckHostName(requestUri.Host);
            if (hostNameType != UriHostNameType.Dns &&
                hostNameType != UriHostNameType.IPv4 &&
                hostNameType != UriHostNameType.IPv6)
            {
                throw Failure(InvalidEndpointCategory, "the endpoint host type is unsupported.");
            }

            string canonicalHost;
            try
            {
                canonicalHost = requestUri.IdnHost;
            }
            catch
            {
                throw Failure(InvalidEndpointCategory, "the endpoint host cannot be canonicalized.");
            }

            if (string.IsNullOrWhiteSpace(canonicalHost))
            {
                throw Failure(InvalidEndpointCategory, "the endpoint host is empty.");
            }

            if (hostNameType == UriHostNameType.Dns)
            {
                var comparisonHost = canonicalHost.TrimEnd('.');
                if (string.Equals(comparisonHost, "localhost", StringComparison.OrdinalIgnoreCase))
                {
                    throw Failure(InvalidEndpointCategory, "localhost is not an allowed endpoint host.");
                }

                return new ParsedEndpoint(requestUri, canonicalHost, false, null);
            }

            if (!IPAddress.TryParse(requestUri.Host.Trim('[', ']'), out var literalAddress))
            {
                throw Failure(InvalidEndpointCategory, "the literal endpoint host is malformed.");
            }

            if (literalAddress.AddressFamily == AddressFamily.InterNetworkV6 &&
                literalAddress.ScopeId != 0)
            {
                throw Failure(InvalidEndpointCategory, "scoped IPv6 endpoint hosts are not permitted.");
            }

            return new ParsedEndpoint(requestUri, canonicalHost, true, literalAddress);
        }

        private static ChannelForgeValidatedEndpoint BuildValidatedEndpoint(
            ParsedEndpoint parsed,
            IEnumerable<IPAddress> rawAddresses)
        {
            if (rawAddresses == null)
            {
                throw Failure(DnsFailureCategory, "endpoint name resolution returned no addresses.");
            }

            var rawList = rawAddresses.ToArray();
            if (rawList.Length == 0)
            {
                throw Failure(DnsFailureCategory, "endpoint name resolution returned no addresses.");
            }

            var normalized = new List<IPAddress>(rawList.Length);
            var blocked = false;

            foreach (var rawAddress in rawList)
            {
                if (rawAddress == null)
                {
                    blocked = true;
                    continue;
                }

                var normalizedAddress = NormalizeAddress(rawAddress);
                if (normalizedAddress == null || IsBlockedAddress(normalizedAddress))
                {
                    blocked = true;
                    continue;
                }

                normalized.Add(normalizedAddress);
            }

            if (blocked)
            {
                throw Failure(BlockedDestinationCategory, "the endpoint resolution included a blocked destination.");
            }

            var unique = new Dictionary<string, IPAddress>(StringComparer.Ordinal);
            foreach (var address in normalized)
            {
                var key = GetAddressKey(address);
                if (!unique.ContainsKey(key))
                {
                    unique.Add(key, address);
                }
            }

            var candidates = unique.Values.ToList();
            candidates.Sort(AddressComparer.Instance);
            return new ChannelForgeValidatedEndpoint(
                parsed.RequestUri,
                parsed.TlsHostName,
                parsed.RequestUri.Port,
                parsed.IsLiteralAddress,
                new ReadOnlyCollection<IPAddress>(candidates));
        }

        private static IPAddress NormalizeAddress(IPAddress address)
        {
            if (address.AddressFamily == AddressFamily.InterNetworkV6)
            {
                if (address.ScopeId != 0)
                {
                    return null;
                }

                if (address.IsIPv4MappedToIPv6)
                {
                    return address.MapToIPv4();
                }

                return new IPAddress(address.GetAddressBytes());
            }

            if (address.AddressFamily == AddressFamily.InterNetwork)
            {
                return new IPAddress(address.GetAddressBytes());
            }

            return null;
        }

        private static bool IsBlockedAddress(IPAddress address)
        {
            var prefixes = address.AddressFamily == AddressFamily.InterNetwork
                ? Ipv4DenyPrefixes
                : Ipv6DenyPrefixes;

            if (prefixes.Any(prefix => prefix.Contains(address)))
            {
                return true;
            }

            return address.AddressFamily == AddressFamily.InterNetworkV6 &&
                !Ipv6GlobalUnicastPrefix.Contains(address);
        }

        private static string GetAddressKey(IPAddress address)
        {
            var family = address.AddressFamily == AddressFamily.InterNetworkV6 ? "6" : "4";
            return family + ":" + Convert.ToHexString(address.GetAddressBytes());
        }

        private static ChannelForgePinnedHttpTransportException Failure(string category, string detail)
        {
            return new ChannelForgePinnedHttpTransportException(category, detail);
        }

        private sealed class ParsedEndpoint
        {
            public Uri RequestUri { get; }
            public string TlsHostName { get; }
            public bool IsLiteralAddress { get; }
            public IPAddress LiteralAddress { get; }

            public ParsedEndpoint(Uri requestUri, string tlsHostName, bool isLiteralAddress, IPAddress literalAddress)
            {
                RequestUri = requestUri;
                TlsHostName = tlsHostName;
                IsLiteralAddress = isLiteralAddress;
                LiteralAddress = literalAddress;
            }
        }

        private sealed class AddressComparer : IComparer<IPAddress>
        {
            public static readonly AddressComparer Instance = new AddressComparer();

            public int Compare(IPAddress left, IPAddress right)
            {
                var leftFamily = GetFamilyRank(left);
                var rightFamily = GetFamilyRank(right);
                var familyComparison = leftFamily.CompareTo(rightFamily);
                if (familyComparison != 0)
                {
                    return familyComparison;
                }

                var leftBytes = left.GetAddressBytes();
                var rightBytes = right.GetAddressBytes();
                for (var index = 0; index < leftBytes.Length; index++)
                {
                    var byteComparison = leftBytes[index].CompareTo(rightBytes[index]);
                    if (byteComparison != 0)
                    {
                        return byteComparison;
                    }
                }

                return 0;
            }

            private static int GetFamilyRank(IPAddress address)
            {
                return address.AddressFamily == AddressFamily.InterNetworkV6 ? 0 : 1;
            }
        }

        private sealed class AddressPrefix
        {
            private readonly byte[] networkBytes;
            private readonly int prefixLength;

            private AddressPrefix(byte[] networkBytes, int prefixLength)
            {
                this.networkBytes = networkBytes;
                this.prefixLength = prefixLength;
            }

            public static AddressPrefix Parse(string value)
            {
                var parts = value.Split('/');
                var address = IPAddress.Parse(parts[0]);
                var prefixLength = int.Parse(parts[1], System.Globalization.CultureInfo.InvariantCulture);
                var maxLength = address.AddressFamily == AddressFamily.InterNetwork ? 32 : 128;
                if (prefixLength < 0 || prefixLength > maxLength)
                {
                    throw new InvalidOperationException("Invalid transport address prefix.");
                }

                return new AddressPrefix(address.GetAddressBytes(), prefixLength);
            }

            public bool Contains(IPAddress address)
            {
                if (address.AddressFamily != (networkBytes.Length == 4
                        ? AddressFamily.InterNetwork
                        : AddressFamily.InterNetworkV6))
                {
                    return false;
                }

                var addressBytes = address.GetAddressBytes();
                var fullBytes = prefixLength / 8;
                var remainingBits = prefixLength % 8;
                for (var index = 0; index < fullBytes; index++)
                {
                    if (networkBytes[index] != addressBytes[index])
                    {
                        return false;
                    }
                }

                if (remainingBits == 0)
                {
                    return true;
                }

                var mask = (byte)(0xFF << (8 - remainingBits));
                return (networkBytes[fullBytes] & mask) == (addressBytes[fullBytes] & mask);
            }
        }
    }
}
