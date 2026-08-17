using System.Buffers;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Net.Sockets;
using System.Reflection;
using System.Diagnostics;
using System.IO;
using System.Security.Authentication;
using System.Threading;
using System.Threading.Tasks;

namespace ChannelForge.Private.Transport
{
    public sealed class ChannelForgePinnedHttpTransportException : Exception
    {
        public string Category { get; }
        public string Phase { get; }
        public int? StatusCode { get; }

        internal ChannelForgePinnedHttpTransportException(
            string category,
            string detail,
            string phase = null,
            int? statusCode = null)
            : base(detail)
        {
            Category = category;
            Phase = phase;
            StatusCode = statusCode;
        }
    }

    public enum ChannelForgeHttpStatusPolicy
    {
        Require200 = 0,
        Allow304MetadataOnly = 1
    }

    public enum ChannelForgeHttpStatusDisposition
    {
        Payload = 0,
        MetadataOnly = 1
    }

    public sealed class ChannelForgeHttpAcquisitionOptions
    {
        public const long HardMaximumRawResponseBytes = 256L * 1024L * 1024L;
        public const int MaximumSourceIdLength = 128;

        public string SourceId { get; }
        public IReadOnlyList<string> AllowedContentTypes { get; }
        public bool AllowMissingContentType { get; }
        public long MaxRawResponseBytes { get; }
        public ChannelForgeHttpStatusPolicy StatusPolicy { get; }

        public ChannelForgeHttpAcquisitionOptions(
            string sourceId,
            IEnumerable<string> allowedContentTypes,
            bool allowMissingContentType,
            long maxRawResponseBytes,
            ChannelForgeHttpStatusPolicy statusPolicy)
        {
            SourceId = NormalizeSourceId(sourceId);
            AllowedContentTypes = NormalizeContentTypes(allowedContentTypes);
            AllowMissingContentType = allowMissingContentType;

            if (maxRawResponseBytes <= 0 || maxRawResponseBytes > HardMaximumRawResponseBytes)
            {
                throw new ArgumentOutOfRangeException(nameof(maxRawResponseBytes));
            }

            if (statusPolicy != ChannelForgeHttpStatusPolicy.Require200 &&
                statusPolicy != ChannelForgeHttpStatusPolicy.Allow304MetadataOnly)
            {
                throw new ArgumentOutOfRangeException(nameof(statusPolicy));
            }

            MaxRawResponseBytes = maxRawResponseBytes;
            StatusPolicy = statusPolicy;
        }

        private static string NormalizeSourceId(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException("SourceId must be non-empty.", nameof(value));
            }

            var normalized = value.Trim();
            if (normalized.Length > MaximumSourceIdLength ||
                normalized.IndexOfAny(new[] { '\r', '\n', '\t', '/', '\\', '?', '#', '@' }) >= 0 ||
                normalized.Contains("://", StringComparison.Ordinal))
            {
                throw new ArgumentException("SourceId contains unsupported metadata characters.", nameof(value));
            }

            foreach (var character in normalized)
            {
                if (char.IsControl(character))
                {
                    throw new ArgumentException("SourceId contains control characters.", nameof(value));
                }
            }

            return normalized;
        }

        private static IReadOnlyList<string> NormalizeContentTypes(IEnumerable<string> values)
        {
            var result = new List<string>();
            if (values != null)
            {
                foreach (var value in values)
                {
                    if (string.IsNullOrWhiteSpace(value))
                    {
                        throw new ArgumentException("Allowed content types must be non-empty.", nameof(values));
                    }

                    if (!MediaTypeHeaderValue.TryParse(value.Trim(), out var parsed) ||
                        string.IsNullOrWhiteSpace(parsed.MediaType))
                    {
                        throw new ArgumentException("Allowed content types must be valid media types.", nameof(values));
                    }

                    var mediaType = parsed.MediaType.Trim().ToLowerInvariant();
                    if (!result.Contains(mediaType, StringComparer.Ordinal))
                    {
                        result.Add(mediaType);
                    }
                }
            }

            return new ReadOnlyCollection<string>(result);
        }
    }

    public sealed class ChannelForgeHttpsPayload : IDisposable
    {
        private ChannelForgeAcquisitionLease lease;

        public string SourceId { get; }
        public int StatusCode { get; }
        public ChannelForgeHttpStatusDisposition StatusDisposition { get; }
        public string ContentType { get; }
        public IReadOnlyList<string> ContentEncodings { get; }
        public long? ContentLength { get; }
        public bool HasPayload { get; }
        public Stream ResponseStream { get; }

        internal ChannelForgeHttpsPayload(
            string sourceId,
            int statusCode,
            ChannelForgeHttpStatusDisposition statusDisposition,
            string contentType,
            IReadOnlyList<string> contentEncodings,
            long? contentLength,
            bool hasPayload,
            Stream responseStream,
            ChannelForgeAcquisitionLease acquisitionLease)
        {
            SourceId = sourceId;
            StatusCode = statusCode;
            StatusDisposition = statusDisposition;
            ContentType = contentType;
            ContentEncodings = contentEncodings ?? new ReadOnlyCollection<string>(Array.Empty<string>());
            ContentLength = contentLength;
            HasPayload = hasPayload;
            ResponseStream = responseStream;
            lease = acquisitionLease;
        }

        public void Dispose()
        {
            var currentLease = Interlocked.Exchange(ref lease, null);
            if (ResponseStream != null)
            {
                ResponseStream.Dispose();
            }

            currentLease?.Dispose();
        }
    }
    internal sealed class ChannelForgeDeadlineState : IDisposable
    {
        private int disposed;

        public CancellationTokenSource TotalCancellation { get; }
        public CancellationTokenSource DisposalCancellation { get; }
        public long DeadlineTimestamp { get; }
        public bool IsDisposed => Volatile.Read(ref disposed) != 0;

        public ChannelForgeDeadlineState(TimeSpan totalTimeout)
        {
            if (totalTimeout <= TimeSpan.Zero || totalTimeout == Timeout.InfiniteTimeSpan)
            {
                throw new ArgumentOutOfRangeException(nameof(totalTimeout));
            }

            DeadlineTimestamp = GetDeadlineTimestamp(totalTimeout);
            TotalCancellation = new CancellationTokenSource();
            DisposalCancellation = new CancellationTokenSource();
            TotalCancellation.CancelAfter(totalTimeout);
        }

        public TimeSpan GetRemaining()
        {
            var remainingTicks = DeadlineTimestamp - Stopwatch.GetTimestamp();
            if (remainingTicks <= 0)
            {
                return TimeSpan.Zero;
            }

            return TimeSpan.FromSeconds(remainingTicks / (double)Stopwatch.Frequency);
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) != 0)
            {
                return;
            }

            try
            {
                DisposalCancellation.Cancel();
                TotalCancellation.Cancel();
            }
            finally
            {
                DisposalCancellation.Dispose();
                TotalCancellation.Dispose();
            }
        }

        private static long GetDeadlineTimestamp(TimeSpan timeout)
        {
            var timeoutTicks = checked((long)(timeout.TotalSeconds * Stopwatch.Frequency));
            return checked(Stopwatch.GetTimestamp() + timeoutTicks);
        }
    }

    internal sealed class ChannelForgeAcquisitionLease : IDisposable
    {
        private readonly HttpClient client;
        private readonly HttpResponseMessage response;
        private readonly ChannelForgeDeadlineState deadline;
        private int disposed;

        public ChannelForgeDeadlineState Deadline => deadline;
        public CancellationToken TotalToken => deadline.TotalCancellation.Token;
        public CancellationToken DisposalToken => deadline.DisposalCancellation.Token;
        public bool IsDisposed => Volatile.Read(ref disposed) != 0 || deadline.IsDisposed;

        public ChannelForgeAcquisitionLease(
            HttpClient client,
            HttpResponseMessage response,
            ChannelForgeDeadlineState deadline)
        {
            this.client = client ?? throw new ArgumentNullException(nameof(client));
            this.response = response ?? throw new ArgumentNullException(nameof(response));
            this.deadline = deadline ?? throw new ArgumentNullException(nameof(deadline));
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) != 0)
            {
                return;
            }

            deadline.Dispose();
            response.Dispose();
            client.Dispose();
        }
    }

    internal sealed class ChannelForgeBoundedResponseStream : Stream
    {
        private readonly Stream inner;
        private readonly ChannelForgeAcquisitionLease lease;
        private readonly long maximumBytes;
        private readonly long? declaredLength;
        private readonly TimeSpan inactivityTimeout;
        private long bytesRead;
        private long inactivityDeadlineTimestamp;
        private int disposed;

        public ChannelForgeBoundedResponseStream(
            Stream inner,
            ChannelForgeAcquisitionLease lease,
            long maximumBytes,
            long? declaredLength,
            TimeSpan inactivityTimeout)
        {
            this.inner = inner ?? throw new ArgumentNullException(nameof(inner));
            this.lease = lease ?? throw new ArgumentNullException(nameof(lease));
            this.maximumBytes = maximumBytes;
            this.declaredLength = declaredLength;
            this.inactivityTimeout = inactivityTimeout;
        }

        public override bool CanRead => Volatile.Read(ref disposed) == 0 && inner.CanRead;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => bytesRead;
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            if (buffer == null)
            {
                throw new ArgumentNullException(nameof(buffer));
            }

            return ReadCoreAsync(buffer.AsMemory(offset, count), CancellationToken.None)
                .GetAwaiter()
                .GetResult();
        }

        public override ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            return ReadCoreAsync(buffer, cancellationToken);
        }

        public override Task<int> ReadAsync(
            byte[] buffer,
            int offset,
            int count,
            CancellationToken cancellationToken)
        {
            if (buffer == null)
            {
                throw new ArgumentNullException(nameof(buffer));
            }

            return ReadCoreAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();
        }

        private async ValueTask<int> ReadCoreAsync(
            Memory<byte> buffer,
            CancellationToken callerCancellationToken)
        {
            if (Volatile.Read(ref disposed) != 0)
            {
                throw new ObjectDisposedException(nameof(ChannelForgeBoundedResponseStream));
            }

            if (buffer.Length == 0)
            {
                return 0;
            }

            if (declaredLength.HasValue && bytesRead >= declaredLength.Value)
            {
                return 0;
            }

            var remaining = maximumBytes - bytesRead;
            if (remaining < 0)
            {
                throw ResponseTooLarge();
            }

            var totalRemaining = lease.Deadline.GetRemaining();
            if (totalRemaining <= TimeSpan.Zero)
            {
                throw Timeout("Total");
            }

            using var inactivitySource = new CancellationTokenSource();
            var inactivityRemaining = GetInactivityRemaining();
            if (inactivityRemaining <= TimeSpan.Zero)
            {
                throw Timeout("BodyInactivity");
            }

            var inactivityWindow = totalRemaining < inactivityRemaining
                ? totalRemaining
                : inactivityRemaining;
            inactivitySource.CancelAfter(inactivityWindow);

            using var linkedSource = CancellationTokenSource.CreateLinkedTokenSource(
                callerCancellationToken,
                lease.TotalToken,
                lease.DisposalToken,
                inactivitySource.Token);

            try
            {
                int read;
                var useTemporaryBuffer = remaining < buffer.Length;
                if (!useTemporaryBuffer)
                {
                    read = await inner.ReadAsync(buffer, linkedSource.Token).ConfigureAwait(false);
                }
                else
                {
                    var requested = (int)Math.Min((long)buffer.Length, remaining + 1L);
                    var temporary = ArrayPool<byte>.Shared.Rent(requested);
                    try
                    {
                        read = await inner.ReadAsync(
                            temporary.AsMemory(0, requested),
                            linkedSource.Token).ConfigureAwait(false);

                        if (read <= remaining)
                        {
                            temporary.AsSpan(0, read).CopyTo(buffer.Span);
                        }
                    }
                    finally
                    {
                        ArrayPool<byte>.Shared.Return(temporary);
                    }
                }

                if (read > remaining)
                {
                    Dispose();
                    throw ResponseTooLarge();
                }

                if (read > 0)
                {
                    bytesRead += read;
                    Interlocked.Exchange(
                        ref inactivityDeadlineTimestamp,
                        ChannelForgePinnedHttpTransport.GetDeadlineTimestamp(inactivityTimeout));
                }

                return read;
            }
            catch (ChannelForgePinnedHttpTransportException)
            {
                throw;
            }
            catch (OperationCanceledException)
            {
                throw MapCancellation(
                    callerCancellationToken,
                    inactivitySource,
                    "BodyInactivity");
            }
            catch
            {
                Dispose();
                throw new ChannelForgePinnedHttpTransportException(
                    ChannelForgePinnedHttpTransport.ConnectionFailureCategory,
                    "the response body could not be read.",
                    "Body");
            }
        }

        private ChannelForgePinnedHttpTransportException MapCancellation(
            CancellationToken callerCancellationToken,
            CancellationTokenSource inactivitySource,
            string inactivityPhase)
        {
            if (lease.IsDisposed ||
                callerCancellationToken.IsCancellationRequested)
            {
                return new ChannelForgePinnedHttpTransportException(
                    ChannelForgePinnedHttpTransport.CancelledCategory,
                    "the response body read was cancelled.",
                    "Body");
            }

            if (lease.TotalToken.IsCancellationRequested ||
                lease.Deadline.GetRemaining() <= TimeSpan.Zero)
            {
                return Timeout("Total");
            }

            if (inactivitySource.IsCancellationRequested)
            {
                return Timeout(inactivityPhase);
            }

            return new ChannelForgePinnedHttpTransportException(
                ChannelForgePinnedHttpTransport.CancelledCategory,
                "the response body read was cancelled.",
                "Body");
        }

        private TimeSpan GetInactivityRemaining()
        {
            var currentDeadline = Volatile.Read(ref inactivityDeadlineTimestamp);
            if (currentDeadline == 0)
            {
                var initialDeadline = ChannelForgePinnedHttpTransport.GetDeadlineTimestamp(inactivityTimeout);
                Interlocked.CompareExchange(ref inactivityDeadlineTimestamp, initialDeadline, 0);
                currentDeadline = Volatile.Read(ref inactivityDeadlineTimestamp);
            }

            return ChannelForgePinnedHttpTransport.GetRemaining(currentDeadline);
        }

        private ChannelForgePinnedHttpTransportException ResponseTooLarge()
        {
            return new ChannelForgePinnedHttpTransportException(
                ChannelForgePinnedHttpTransport.ResponseTooLargeCategory,
                "the response exceeded the configured byte limit.",
                "Body");
        }

        private ChannelForgePinnedHttpTransportException Timeout(string phase)
        {
            return new ChannelForgePinnedHttpTransportException(
                ChannelForgePinnedHttpTransport.TimeoutCategory,
                "the response acquisition timed out.",
                phase);
        }

        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (Interlocked.Exchange(ref disposed, 1) != 0)
            {
                return;
            }

            if (disposing)
            {
                try
                {
                    inner.Dispose();
                }
                finally
                {
                    lease.Dispose();
                }
            }

            base.Dispose(disposing);
        }

        public override ValueTask DisposeAsync()
        {
            Dispose();
            return ValueTask.CompletedTask;
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
            if (requestUri == null ||
                string.IsNullOrWhiteSpace(tlsHostName) ||
                candidates == null)
            {
                throw new ArgumentNullException();
            }

            var snapshot = candidates
                .Select(address =>
                {
                    if (address == null)
                    {
                        throw new ArgumentException("The validated endpoint contains a null candidate.", nameof(candidates));
                    }

                    return new IPAddress(address.GetAddressBytes());
                })
                .ToArray();

            RequestUri = requestUri;
            TlsHostName = tlsHostName;
            Port = port;
            IsLiteralAddress = isLiteralAddress;
            Candidates = new ReadOnlyCollection<IPAddress>(snapshot);
        }
    }

    public static class ChannelForgePinnedHttpTransport
    {
        public const string ContractName = "ChannelForgePinnedHttpTransport";
        public const int ContractVersion = 4;

        public const string InvalidEndpointCategory = "InvalidEndpoint";
        public const string DnsFailureCategory = "DnsFailure";
        public const string BlockedDestinationCategory = "BlockedDestination";
        public const string CancelledCategory = "Cancelled";
        public const string TimeoutCategory = "Timeout";
        public const string ConnectionFailureCategory = "ConnectionFailure";
        public const string RedirectRejectedCategory = "RedirectRejected";
        public const string ResponseTooLargeCategory = "ResponseTooLarge";
        public const string NonSuccessHttpStatusCategory = "NonSuccessHttpStatus";
        public const string UnsupportedContentTypeCategory = "UnsupportedContentType";

        private const long HardMaximumRawResponseBytes = 256L * 1024L * 1024L;
        private static readonly TimeSpan HeaderTimeout = TimeSpan.FromSeconds(30);
        private static readonly TimeSpan BodyInactivityTimeout = TimeSpan.FromSeconds(30);
        private static readonly TimeSpan TotalAcquisitionTimeout = TimeSpan.FromSeconds(120);
        private static readonly TimeSpan PinnedConnectionTimeout = TimeSpan.FromSeconds(10);



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

        internal static SocketsHttpHandler CreatePinnedHandler(ChannelForgeValidatedEndpoint endpoint)
        {
            return CreatePinnedHandlerCore(SnapshotEndpoint(endpoint, enforceDestinationPolicy: true));
        }

        // This internal reflection-only seam is used only by isolated tests that
        // must bind a local loopback listener. It is not returned by the loader
        // and is not reachable through a module command.
        internal static SocketsHttpHandler CreatePinnedHandlerForTest(ChannelForgeValidatedEndpoint endpoint)
        {
            return CreatePinnedHandlerCore(SnapshotEndpoint(endpoint, enforceDestinationPolicy: false));
        }

        private static SocketsHttpHandler CreatePinnedHandlerCore(
            ChannelForgeEndpointSnapshot endpoint)
        {
            var handler = new SocketsHttpHandler
            {
                UseProxy = false,
                AllowAutoRedirect = false,
                UseCookies = false,
                AutomaticDecompression = DecompressionMethods.None,
            };

            // The callback owns the single bounded TCP connection deadline. Do not
            // configure SocketsHttpHandler.ConnectTimeout with a competing policy.
            handler.ConnectCallback = (context, cancellationToken) =>
                ConnectPinnedAsync(endpoint, context, cancellationToken);

            // Future request code must use endpoint.RequestUri as the request URI
            // and must not override HttpRequestMessage.Headers.Host or
            // HttpClient.DefaultRequestHeaders.Host.
            return handler;
        }

        // This is an internal reflection-only test seam. It is not returned by the
        // PowerShell loader and is not reachable through a module command.
        internal static Task<ChannelForgeHttpsPayload> AcquireGetAsync(
            ChannelForgeValidatedEndpoint endpoint,
            ChannelForgeHttpAcquisitionOptions options,
            CancellationToken cancellationToken)
        {
            var snapshot = SnapshotEndpoint(endpoint, enforceDestinationPolicy: true);
            var handler = CreatePinnedHandlerCore(snapshot);
            return AcquireGetCoreAsync(
                snapshot,
                options,
                handler,
                HeaderTimeout,
                BodyInactivityTimeout,
                TotalAcquisitionTimeout,
                cancellationToken);
        }

        // Internal reflection-only seam for local deterministic tests. It accepts
        // only a caller-created SocketsHttpHandler and still validates the endpoint
        // shape; production destination policy is not weakened by this method.
        internal static Task<ChannelForgeHttpsPayload> AcquireGetForTestAsync(
            ChannelForgeValidatedEndpoint endpoint,
            ChannelForgeHttpAcquisitionOptions options,
            SocketsHttpHandler handler,
            TimeSpan headerTimeout,
            TimeSpan bodyInactivityTimeout,
            TimeSpan totalTimeout,
            CancellationToken cancellationToken)
        {
            var snapshot = SnapshotEndpoint(endpoint, enforceDestinationPolicy: false);
            if (handler == null)
            {
                throw Failure(InvalidEndpointCategory, "the test handler is not available.");
            }

            ValidateTimeoutProfile(headerTimeout, bodyInactivityTimeout, totalTimeout);
            return AcquireGetCoreAsync(
                snapshot,
                options,
                handler,
                headerTimeout,
                bodyInactivityTimeout,
                totalTimeout,
                cancellationToken);
        }

        private static async Task<ChannelForgeHttpsPayload> AcquireGetCoreAsync(
            ChannelForgeEndpointSnapshot endpoint,
            ChannelForgeHttpAcquisitionOptions options,
            SocketsHttpHandler handler,
            TimeSpan headerTimeout,
            TimeSpan bodyInactivityTimeout,
            TimeSpan totalTimeout,
            CancellationToken cancellationToken)
        {
            if (options == null)
            {
                throw Failure(InvalidEndpointCategory, "the acquisition options are missing.");
            }

            ValidateTimeoutProfile(headerTimeout, bodyInactivityTimeout, totalTimeout);

            ChannelForgeDeadlineState deadline = null;
            HttpClient client = null;
            HttpResponseMessage response = null;
            var transferred = false;

            try
            {
                deadline = new ChannelForgeDeadlineState(totalTimeout);
                client = new HttpClient(handler, disposeHandler: true)
                {
                    Timeout = Timeout.InfiniteTimeSpan
                };

                using var headerTimeoutSource = new CancellationTokenSource();
                var headerWindow = GetMinimumTimeout(headerTimeout, deadline.GetRemaining());
                if (headerWindow <= TimeSpan.Zero)
                {
                    throw Failure(TimeoutCategory, "the response acquisition timed out.", "Total");
                }

                headerTimeoutSource.CancelAfter(headerWindow);
                using var headerLinkedSource = CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken,
                    deadline.TotalCancellation.Token,
                    deadline.DisposalCancellation.Token,
                    headerTimeoutSource.Token);

                using (var request = new HttpRequestMessage(HttpMethod.Get, endpoint.RequestUri))
                {
                    response = await client.SendAsync(
                            request,
                            HttpCompletionOption.ResponseHeadersRead,
                            headerLinkedSource.Token)
                        .ConfigureAwait(false);
                }

                ThrowIfAcquisitionCancellation(
                    cancellationToken,
                    deadline,
                    headerTimeoutSource,
                    "Headers");

                var statusCode = (int)response.StatusCode;
                if (statusCode == 304)
                {
                    if (options.StatusPolicy != ChannelForgeHttpStatusPolicy.Allow304MetadataOnly)
                    {
                        throw Failure(
                            RedirectRejectedCategory,
                            "the response status was not authorized for this acquisition.",
                            "Headers",
                            statusCode);
                    }

                    response.Dispose();
                    response = null;
                    client.Dispose();
                    client = null;
                    deadline.Dispose();
                    deadline = null;
                    return new ChannelForgeHttpsPayload(
                        options.SourceId,
                        statusCode,
                        ChannelForgeHttpStatusDisposition.MetadataOnly,
                        null,
                        new ReadOnlyCollection<string>(Array.Empty<string>()),
                        null,
                        false,
                        null,
                        null);
                }

                if (statusCode != 200)
                {
                    if (statusCode >= 300 && statusCode <= 399)
                    {
                        throw Failure(
                            RedirectRejectedCategory,
                            "redirect responses are not accepted.",
                            "Headers",
                            statusCode);
                    }

                    throw Failure(
                        NonSuccessHttpStatusCategory,
                        "the HTTP response status was not successful.",
                        "Headers",
                        statusCode);
                }

                var contentType = GetContentType(response, options);
                var contentEncodings = GetContentEncodings(response);
                var contentLength = response.Content.Headers.ContentLength;
                if (contentLength.HasValue && contentLength.Value > options.MaxRawResponseBytes)
                {
                    throw Failure(
                        ResponseTooLargeCategory,
                        "the response exceeded the configured byte limit.",
                        "Headers");
                }

                var responseStream = await response.Content
                    .ReadAsStreamAsync(headerLinkedSource.Token)
                    .ConfigureAwait(false);
                var lease = new ChannelForgeAcquisitionLease(client, response, deadline);
                var boundedStream = new ChannelForgeBoundedResponseStream(
                    responseStream,
                    lease,
                    options.MaxRawResponseBytes,
                    contentLength,
                    bodyInactivityTimeout);

                client = null;
                response = null;
                deadline = null;
                transferred = true;
                return new ChannelForgeHttpsPayload(
                    options.SourceId,
                    statusCode,
                    ChannelForgeHttpStatusDisposition.Payload,
                    contentType,
                    contentEncodings,
                    contentLength,
                    true,
                    boundedStream,
                    lease);
            }
            catch (ChannelForgePinnedHttpTransportException)
            {
                throw;
            }
            catch (OperationCanceledException)
            {
                throw MapAcquisitionCancellation(
                    cancellationToken,
                    deadline,
                    null,
                    "Headers");
            }
            catch (Exception exception)
            {
                if (ContainsAuthenticationFailure(exception))
                {
                    throw Failure(
                        "TlsFailure",
                        "the TLS connection could not be established.",
                        "Headers");
                }

                throw Failure(
                    ConnectionFailureCategory,
                    "the HTTPS response could not be acquired.",
                    "Headers");
            }
            finally
            {
                if (!transferred)
                {
                    response?.Dispose();
                    client?.Dispose();
                    deadline?.Dispose();
                }
            }
        }

        private static void ValidateTimeoutProfile(
            TimeSpan headerTimeout,
            TimeSpan bodyInactivityTimeout,
            TimeSpan totalTimeout)
        {
            if (headerTimeout <= TimeSpan.Zero ||
                bodyInactivityTimeout <= TimeSpan.Zero ||
                totalTimeout <= TimeSpan.Zero ||
                headerTimeout == Timeout.InfiniteTimeSpan ||
                bodyInactivityTimeout == Timeout.InfiniteTimeSpan ||
                totalTimeout == Timeout.InfiniteTimeSpan ||
                headerTimeout > totalTimeout ||
                bodyInactivityTimeout > totalTimeout)
            {
                throw Failure(InvalidEndpointCategory, "the acquisition timeout profile is invalid.");
            }
        }

        private static TimeSpan GetMinimumTimeout(TimeSpan first, TimeSpan second)
        {
            return first < second ? first : second;
        }

        private static void ThrowIfAcquisitionCancellation(
            CancellationToken callerCancellationToken,
            ChannelForgeDeadlineState deadline,
            CancellationTokenSource phaseCancellation,
            string phase)
        {
            if (callerCancellationToken.IsCancellationRequested)
            {
                throw Failure(CancelledCategory, "the response acquisition was cancelled.", phase);
            }

            if (deadline.IsDisposed ||
                deadline.TotalCancellation.IsCancellationRequested ||
                deadline.GetRemaining() <= TimeSpan.Zero)
            {
                throw Failure(TimeoutCategory, "the response acquisition timed out.", "Total");
            }

            if (phaseCancellation != null && phaseCancellation.IsCancellationRequested)
            {
                throw Failure(TimeoutCategory, "the response acquisition timed out.", phase);
            }
        }

        private static ChannelForgePinnedHttpTransportException MapAcquisitionCancellation(
            CancellationToken callerCancellationToken,
            ChannelForgeDeadlineState deadline,
            CancellationTokenSource phaseCancellation,
            string phase)
        {
            if (callerCancellationToken.IsCancellationRequested)
            {
                return Failure(CancelledCategory, "the response acquisition was cancelled.", phase);
            }

            if (deadline == null ||
                deadline.IsDisposed ||
                deadline.TotalCancellation.IsCancellationRequested ||
                deadline.GetRemaining() <= TimeSpan.Zero)
            {
                return Failure(TimeoutCategory, "the response acquisition timed out.", "Total");
            }

            if (phaseCancellation != null && phaseCancellation.IsCancellationRequested)
            {
                return Failure(TimeoutCategory, "the response acquisition timed out.", phase);
            }

            return Failure(TimeoutCategory, "the response acquisition timed out.", phase);
        }

        private static string GetContentType(
            HttpResponseMessage response,
            ChannelForgeHttpAcquisitionOptions options)
        {
            var mediaType = response.Content.Headers.ContentType?.MediaType;
            if (string.IsNullOrWhiteSpace(mediaType))
            {
                if (options.AllowMissingContentType)
                {
                    return null;
                }

                throw Failure(
                    UnsupportedContentTypeCategory,
                    "the response content type is missing or unsupported.",
                    "Headers");
            }

            var normalized = mediaType.Trim().ToLowerInvariant();
            if (options.AllowedContentTypes.Count > 0 &&
                !options.AllowedContentTypes.Contains(normalized, StringComparer.Ordinal))
            {
                throw Failure(
                    UnsupportedContentTypeCategory,
                    "the response content type is not allowed.",
                    "Headers");
            }

            return normalized;
        }

        private static IReadOnlyList<string> GetContentEncodings(HttpResponseMessage response)
        {
            var values = response.Content.Headers.ContentEncoding
                .Select(value => value == null ? string.Empty : value.Trim().ToLowerInvariant())
                .ToArray();

            if (values.Any(string.IsNullOrWhiteSpace))
            {
                throw Failure(
                    ConnectionFailureCategory,
                    "the response content encoding metadata is invalid.",
                    "Headers");
            }

            return new ReadOnlyCollection<string>(values);
        }

        private static bool ContainsAuthenticationFailure(Exception exception)
        {
            for (var current = exception; current != null; current = current.InnerException)
            {
                if (current is AuthenticationException)
                {
                    return true;
                }
            }

            return false;
        }

        internal static ValueTask<Stream> ConnectPinnedForTest(
            ChannelForgeValidatedEndpoint endpoint,
            string contextHost,
            int contextPort,
            CancellationToken cancellationToken,
            TimeSpan connectionTimeout,
            Func<IPAddress, CancellationToken, ValueTask<Stream>> connector)
        {
            if (connector == null)
            {
                throw Failure(InvalidEndpointCategory, "the test connector is not available.");
            }

            var snapshot = SnapshotEndpoint(endpoint, enforceDestinationPolicy: false);
            return ConnectPinnedCoreAsync(
                snapshot,
                contextHost,
                contextPort,
                cancellationToken,
                connectionTimeout,
                connector);
        }

        private static ValueTask<Stream> ConnectPinnedAsync(
            ChannelForgeEndpointSnapshot endpoint,
            SocketsHttpConnectionContext context,
            CancellationToken cancellationToken)
        {
            if (context == null || context.DnsEndPoint == null)
            {
                throw Failure(InvalidEndpointCategory, "the connection context is missing its endpoint.");
            }

            return ConnectPinnedCoreAsync(
                endpoint,
                context.DnsEndPoint.Host,
                context.DnsEndPoint.Port,
                cancellationToken,
                PinnedConnectionTimeout,
                null);
        }

        private static async ValueTask<Stream> ConnectPinnedCoreAsync(
            ChannelForgeEndpointSnapshot endpoint,
            string contextHost,
            int contextPort,
            CancellationToken cancellationToken,
            TimeSpan connectionTimeout,
            Func<IPAddress, CancellationToken, ValueTask<Stream>> connector)
        {

            if (string.IsNullOrWhiteSpace(contextHost) ||
                !string.Equals(contextHost, endpoint.TlsHostName, StringComparison.OrdinalIgnoreCase) ||
                contextPort != endpoint.Port)
            {
                throw Failure(InvalidEndpointCategory, "the connection context does not match the validated endpoint.");
            }

            if (connectionTimeout <= TimeSpan.Zero || connectionTimeout == Timeout.InfiniteTimeSpan)
            {
                throw Failure(InvalidEndpointCategory, "the pinned connection timeout is invalid.");
            }

            var deadline = GetDeadlineTimestamp(connectionTimeout);
            var timedOut = false;

            foreach (var candidate in endpoint.Candidates)
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    throw Failure(CancelledCategory, "the pinned connection was cancelled.");
                }

                var remaining = GetRemaining(deadline);
                if (remaining <= TimeSpan.Zero)
                {
                    timedOut = true;
                    break;
                }

                using (var timeoutSource = new CancellationTokenSource())
                using (var linkedSource = CancellationTokenSource.CreateLinkedTokenSource(
                           cancellationToken,
                           timeoutSource.Token))
                {
                    timeoutSource.CancelAfter(remaining);

                    try
                    {
                        var operation = connector == null
                            ? ConnectSocketAsync(candidate, endpoint.Port, linkedSource.Token)
                            : connector(candidate, linkedSource.Token);
                        var stream = await operation.AsTask()
                            .WaitAsync(linkedSource.Token)
                            .ConfigureAwait(false);

                        if (stream != null)
                        {
                            return stream;
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        if (cancellationToken.IsCancellationRequested)
                        {
                            throw Failure(CancelledCategory, "the pinned connection was cancelled.");
                        }

                        if (timeoutSource.IsCancellationRequested)
                        {
                            timedOut = true;
                            break;
                        }
                    }
                    catch
                    {
                        // Candidate-specific failures are intentionally opaque and
                        // do not expose socket, address, or provider details.
                    }
                }
            }

            if (cancellationToken.IsCancellationRequested)
            {
                throw Failure(CancelledCategory, "the pinned connection was cancelled.");
            }

            if (timedOut || GetRemaining(deadline) <= TimeSpan.Zero)
            {
                throw Failure(TimeoutCategory, "the pinned connection deadline expired.");
            }

            throw Failure(ConnectionFailureCategory, "all validated connection candidates failed.");
        }

        private static async ValueTask<Stream> ConnectSocketAsync(
            IPAddress candidate,
            int port,
            CancellationToken cancellationToken)
        {
            Socket socket = null;
            try
            {
                socket = new Socket(candidate.AddressFamily, SocketType.Stream, ProtocolType.Tcp)
                {
                    NoDelay = true
                };

                await socket.ConnectAsync(
                    new IPEndPoint(candidate, port),
                    cancellationToken).ConfigureAwait(false);

                var stream = new NetworkStream(socket, ownsSocket: true);
                socket = null;
                return stream;
            }
            catch
            {
                socket?.Dispose();
                throw;
            }
        }

        internal static long GetDeadlineTimestamp(TimeSpan timeout)
        {
            var timeoutTicks = checked((long)(timeout.TotalSeconds * Stopwatch.Frequency));
            return checked(Stopwatch.GetTimestamp() + timeoutTicks);
        }

        internal static TimeSpan GetRemaining(long deadline)
        {
            var remainingTicks = deadline - Stopwatch.GetTimestamp();
            if (remainingTicks <= 0)
            {
                return TimeSpan.Zero;
            }

            var seconds = remainingTicks / (double)Stopwatch.Frequency;
            return TimeSpan.FromSeconds(seconds);
        }

        private static void ValidateHandlerEndpoint(ChannelForgeValidatedEndpoint endpoint, bool enforceDestinationPolicy)
        {
            if (endpoint == null ||
                endpoint.RequestUri == null ||
                !string.Equals(endpoint.RequestUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
                endpoint.RequestUri.Port != 443 ||
                endpoint.Port != 443 ||
                string.IsNullOrWhiteSpace(endpoint.TlsHostName) ||
                !string.Equals(endpoint.RequestUri.IdnHost, endpoint.TlsHostName, StringComparison.OrdinalIgnoreCase) ||
                endpoint.Candidates == null ||
                endpoint.Candidates.Count == 0 ||
                endpoint.Candidates.Any(address => address == null ||
                    (address.AddressFamily != AddressFamily.InterNetwork &&
                     address.AddressFamily != AddressFamily.InterNetworkV6)))
            {
                throw Failure(InvalidEndpointCategory, "the validated endpoint cannot be used for a pinned connection.");
            }

            if (enforceDestinationPolicy && endpoint.Candidates.Any(IsBlockedAddress))
            {
                throw Failure(BlockedDestinationCategory, "the validated endpoint contains a blocked destination.");
            }
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

        private static ChannelForgeEndpointSnapshot SnapshotEndpoint(
            ChannelForgeValidatedEndpoint endpoint,
            bool enforceDestinationPolicy)
        {
            ValidateHandlerEndpoint(endpoint, enforceDestinationPolicy);
            return new ChannelForgeEndpointSnapshot(
                new Uri(endpoint.RequestUri.AbsoluteUri, UriKind.Absolute),
                endpoint.TlsHostName,
                endpoint.Port,
                endpoint.IsLiteralAddress,
                endpoint.Candidates);
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

        private static ChannelForgePinnedHttpTransportException Failure(
            string category,
            string detail,
            string phase,
            int? statusCode = null)
        {
            return new ChannelForgePinnedHttpTransportException(category, detail, phase, statusCode);
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

        private sealed class ChannelForgeEndpointSnapshot
        {
            public Uri RequestUri { get; }
            public string TlsHostName { get; }
            public int Port { get; }
            public bool IsLiteralAddress { get; }
            public IReadOnlyList<IPAddress> Candidates { get; }

            public ChannelForgeEndpointSnapshot(
                Uri requestUri,
                string tlsHostName,
                int port,
                bool isLiteralAddress,
                IEnumerable<IPAddress> candidates)
            {
                RequestUri = requestUri;
                TlsHostName = tlsHostName;
                Port = port;
                IsLiteralAddress = isLiteralAddress;
                Candidates = new ReadOnlyCollection<IPAddress>(
                    candidates.Select(address => new IPAddress(address.GetAddressBytes())).ToArray());
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
