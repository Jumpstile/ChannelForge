function Initialize-ChannelForgeGenerationStore {
    $typeName = 'ChannelForge.GenerationStore'
    $existing = [AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object { $_.GetType($typeName, $false, $false) } |
        Where-Object { $null -ne $_ } |
        Select-Object -First 1
    if ($null -ne $existing) {
        return $existing
    }

    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;

namespace ChannelForge
{
    public sealed class FileIdentity
    {
        public uint VolumeSerial { get; }
        public string FileId { get; }
        public ulong ByteLength { get; }
        public long LastWriteUtcTicks { get; }

        public FileIdentity(uint volumeSerial, string fileId, ulong byteLength, long lastWriteUtcTicks)
        {
            VolumeSerial = volumeSerial;
            FileId = fileId ?? throw new ArgumentNullException(nameof(fileId));
            ByteLength = byteLength;
            LastWriteUtcTicks = lastWriteUtcTicks;
        }

        public override string ToString() =>
            $"{VolumeSerial}:{FileId}:{ByteLength}:{LastWriteUtcTicks}";
    }

    public sealed class LockLease : IDisposable
    {
        private FileStream _stream;
        public string Path { get; }

        internal LockLease(string path, FileStream stream)
        {
            Path = path;
            _stream = stream;
        }

        public void Flush() => _stream.Flush(true);
        public void WriteMetadata(byte[] bytes)
        {
            if (bytes == null) throw new ArgumentNullException(nameof(bytes));
            _stream.SetLength(0);
            _stream.Position = 0;
            _stream.Write(bytes, 0, bytes.Length);
            _stream.Flush(true);
        }

        public void Dispose()
        {
            var stream = System.Threading.Interlocked.Exchange(ref _stream, null);
            stream?.Dispose();
        }
    }

    public static class GenerationStore
    {
        private const int ErrorAlreadyExists = 183;

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation
        {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            IntPtr hFile,
            out ByHandleFileInformation lpFileInformation);

        public static bool IsReparsePoint(string path)
        {
            try
            {
                return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
            }
            catch (FileNotFoundException) { return false; }
            catch (DirectoryNotFoundException) { return false; }
        }

        public static FileStream OpenRead(string path)
        {
            return new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                4096,
                FileOptions.SequentialScan);
        }

        public static FileIdentity ReadIdentity(FileStream stream)
        {
            if (stream == null) throw new ArgumentNullException(nameof(stream));
            if (stream.SafeFileHandle.IsInvalid) throw new IOException("The file handle is invalid.");

            if (OperatingSystem.IsWindows())
            {
                if (!GetFileInformationByHandle(stream.SafeFileHandle.DangerousGetHandle(), out var info))
                {
                    throw new IOException($"GetFileInformationByHandle failed: {Marshal.GetLastWin32Error()}.");
                }

                var fileIndex = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow;
                var fileId = $"{info.VolumeSerialNumber:x8}{fileIndex:x16}".PadLeft(64, '0');
                var writeTime = ((long)info.LastWriteTime.dwHighDateTime << 32) |
                    (uint)info.LastWriteTime.dwLowDateTime;
                var ticks = DateTime.FromFileTimeUtc(writeTime).Ticks;
                return new FileIdentity(info.VolumeSerialNumber, fileId, checked((ulong)stream.Length), ticks);
            }

            var fallback = System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(Path.GetFullPath(stream.Name)));
            return new FileIdentity(0, Convert.ToHexString(fallback).ToLowerInvariant(), checked((ulong)stream.Length), File.GetLastWriteTimeUtc(stream.Name).Ticks);
        }

        public static FileIdentity ReadIdentity(string path)
        {
            using var stream = OpenRead(path);
            return ReadIdentity(stream);
        }

        public static FileStream CreateExclusive(string path)
        {
            return new FileStream(
                path,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.WriteThrough | FileOptions.SequentialScan);
        }

        public static LockLease AcquireLock(string path)
        {
            var stream = new FileStream(
                path,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None,
                4096,
                FileOptions.WriteThrough | FileOptions.SequentialScan);
            return new LockLease(path, stream);
        }

        public static void Flush(FileStream stream) => stream.Flush(true);

        public static void MoveDirectory(string source, string destination)
        {
            Directory.Move(source, destination);
        }

        public static void MoveFile(string source, string destination)
        {
            File.Move(source, destination);
        }

        public static void ReplaceFile(string source, string destination, string backup)
        {
            File.Replace(source, destination, backup, false);
        }

        public static void DeleteFile(string path)
        {
            File.Delete(path);
        }

        public static void DeleteDirectory(string path)
        {
            Directory.Delete(path, true);
        }

        public static bool Exists(string path) => File.Exists(path) || Directory.Exists(path);
    }
}
'@ -Language CSharp -ErrorAction Stop | Out-Null
    return [AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object { $_.GetType($typeName, $false, $false) } |
        Where-Object { $null -ne $_ } |
        Select-Object -First 1
}
