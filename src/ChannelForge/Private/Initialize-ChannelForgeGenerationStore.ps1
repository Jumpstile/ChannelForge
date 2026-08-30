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
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace ChannelForge
{
    public sealed class FileIdentity
    {
        public uint VolumeSerial { get; }
        public string FileId { get; }
        public ulong ByteLength { get; }
        public long LastWriteUtcTicks { get; }
        public uint NumberOfLinks { get; }
        public bool IsReparsePoint { get; }

        public FileIdentity(uint volumeSerial, string fileId, ulong byteLength, long lastWriteUtcTicks, uint numberOfLinks = 1, bool isReparsePoint = false)
        {
            VolumeSerial = volumeSerial;
            FileId = fileId ?? throw new ArgumentNullException(nameof(fileId));
            ByteLength = byteLength;
            LastWriteUtcTicks = lastWriteUtcTicks;
            NumberOfLinks = numberOfLinks;
            IsReparsePoint = isReparsePoint;
        }

        public override string ToString() =>
            $"{VolumeSerial}:{FileId}:{ByteLength}:{LastWriteUtcTicks}:{NumberOfLinks}:{IsReparsePoint}";
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
        private const uint GenericRead = 0x80000000;
        private const uint GenericWrite = 0x40000000;
        private const uint FileReadAttributes = 0x00000080;
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint FileShareDelete = 0x00000004;
        private const uint OpenExisting = 3;
        private const uint CreateNew = 1;
        private const uint FileFlagWriteThrough = 0x80000000;
        private const uint FileFlagBackupSemantics = 0x02000000;
        private const uint FileFlagOpenReparsePoint = 0x00200000;
        private const uint OpenAlways = 4;

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

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            IntPtr hFile,
            out ByHandleFileInformation lpFileInformation);
        private static FileStream OpenNative(string path, uint access, uint share, uint disposition, uint flags, FileAccess fileAccess)
        {
            var handle = CreateFile(path, access, share, IntPtr.Zero, disposition, flags, IntPtr.Zero);
            if (handle.IsInvalid)
            {
                var error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, $"CreateFile failed for '{path}'.");
            }
            return new FileStream(handle, fileAccess, 4096, false);
        }

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
            if (OperatingSystem.IsWindows())
            {
                return OpenNative(path, GenericRead, FileShareRead, OpenExisting, FileFlagOpenReparsePoint, FileAccess.Read);
            }
            return new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.SequentialScan);
        }

        private static FileIdentity ReadIdentityCore(FileStream stream)
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
                ulong length = 0;
                try { length = checked((ulong)stream.Length); } catch (NotSupportedException) { }
                return new FileIdentity(info.VolumeSerialNumber, fileId, length, ticks, info.NumberOfLinks, (info.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0);
            }

            var fallback = System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(Path.GetFullPath(stream.Name)));
            return new FileIdentity(0, Convert.ToHexString(fallback).ToLowerInvariant(), checked((ulong)stream.Length), File.GetLastWriteTimeUtc(stream.Name).Ticks);
        }

        public static FileIdentity ReadIdentity(FileStream stream) => ReadIdentityCore(stream);

        public static FileIdentity ReadIdentity(string path)
        {
            using var stream = OpenRead(path);
            return ReadIdentityCore(stream);
        }

        public static FileIdentity ReadPathIdentity(string path)
        {
            if (!OperatingSystem.IsWindows()) return ReadIdentity(path);
            using var stream = OpenNative(path, FileReadAttributes, FileShareRead | FileShareWrite | FileShareDelete, OpenExisting, FileFlagBackupSemantics | FileFlagOpenReparsePoint, FileAccess.Read);
            return ReadIdentityCore(stream);
        }

        public static bool IsSameVolume(string firstPath, string secondPath) =>
            ReadPathIdentity(firstPath).VolumeSerial == ReadPathIdentity(secondPath).VolumeSerial;

        public static FileStream CreateExclusive(string path)
        {
            if (OperatingSystem.IsWindows())
            {
                return OpenNative(path, GenericWrite, 0, CreateNew, FileFlagWriteThrough | FileFlagOpenReparsePoint, FileAccess.Write);
            }
            return new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough | FileOptions.SequentialScan);
        }

        public static LockLease AcquireLock(string path)
        {
            FileStream stream;
            if (OperatingSystem.IsWindows())
            {
                stream = OpenNative(path, GenericRead | GenericWrite, 0, OpenAlways, FileFlagWriteThrough | FileFlagOpenReparsePoint, FileAccess.ReadWrite);
                var identity = ReadIdentityCore(stream);
                if (identity.IsReparsePoint || identity.NumberOfLinks != 1)
                {
                    stream.Dispose();
                    throw new IOException("Lock path is a reparse point or has multiple hard links.");
                }
            }
            else
            {
                stream = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 4096, FileOptions.WriteThrough | FileOptions.SequentialScan);
            }
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
