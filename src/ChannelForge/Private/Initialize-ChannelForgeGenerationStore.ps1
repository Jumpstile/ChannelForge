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
        public FileIdentity Identity { get; }

        internal LockLease(string path, FileStream stream, FileIdentity identity)
        {
            Path = path;
            Identity = identity;
            _stream = stream;
        }

        public void Flush() => _stream.Flush(true);
        public FileIdentity SnapshotIdentity() => GenerationStore.ReadIdentity(_stream);
        public byte[] ReadMetadata()
        {
            if (_stream == null) throw new ObjectDisposedException(nameof(LockLease));
            _stream.Position = 0;
            using var memory = new MemoryStream();
            _stream.CopyTo(memory);
            return memory.ToArray();
        }
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
        private const uint DeleteAccess = 0x00010000;
        private const uint FileReadAttributes = 0x00000080;
        private const uint FileListDirectory = 0x00000001;
        private const uint FileAddFile = 0x00000002;
        private const uint FileTraverse = 0x00000020;
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint FileShareDelete = 0x00000004;
        private const uint OpenExisting = 3;
        private const uint CreateNew = 1;
        private const uint FileFlagWriteThrough = 0x80000000;
        private const uint FileFlagBackupSemantics = 0x02000000;
        private const uint FileFlagOpenReparsePoint = 0x00200000;
        private const uint OpenAlways = 4;
        private const int FileRenameInformation = 3;
        private const int NtFileRenameInformation = 10;
        private const int FileDispositionInformationEx = 21;
        private const uint FileDispositionDelete = 0x00000001;
        private const uint MoveFileWriteThrough = 0x00000008;

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

        [StructLayout(LayoutKind.Sequential)]
        private struct FileRenameInfoHeader
        {
            public uint ReplaceIfExists;
            public IntPtr RootDirectory;
            public uint FileNameLength;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileDispositionInfoEx
        {
            public uint Flags;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IoStatusBlock
        {
            public IntPtr Status;
            public IntPtr Information;
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
        [DllImport("ntdll.dll")]
        private static extern int NtSetInformationFile(
            SafeFileHandle fileHandle,
            out IoStatusBlock ioStatusBlock,
            IntPtr fileInformation,
            uint length,
            int fileInformationClass);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle hFile,
            int fileInformationClass,
            IntPtr fileInformation,
            uint bufferSize);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool ReplaceFile(
            string replacedFileName,
            string replacementFileName,
            string backupFileName,
            uint replaceFlags,
            IntPtr exclude,
            IntPtr reserved);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool MoveFileEx(
            string existingFileName,
            string newFileName,
            uint flags);
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
                ulong length = ((ulong)info.FileSizeHigh << 32) | info.FileSizeLow;
                if ((info.FileAttributes & (uint)FileAttributes.Directory) == 0)
                {
                    try { length = checked((ulong)stream.Length); } catch (NotSupportedException) { }
                }
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
            FileIdentity identity;
            if (OperatingSystem.IsWindows())
            {
                stream = OpenNative(path, GenericRead | GenericWrite, 0, OpenAlways, FileFlagWriteThrough | FileFlagOpenReparsePoint, FileAccess.ReadWrite);
                identity = ReadIdentityCore(stream);
                if (identity.IsReparsePoint || identity.NumberOfLinks != 1)
                {
                    stream.Dispose();
                    throw new IOException("Lock path is a reparse point or has multiple hard links.");
                }
            }
            else
            {
                stream = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 4096, FileOptions.WriteThrough | FileOptions.SequentialScan);
                identity = ReadIdentityCore(stream);
            }
            return new LockLease(path, stream, identity);
        }

        public static void Flush(FileStream stream) => stream.Flush(true);
        private static SafeFileHandle OpenBoundPath(string path, uint access, uint share, uint flags, string expectedIdentityKey = null)
        {
            var handle = CreateFile(path, access, share, IntPtr.Zero, OpenExisting, flags, IntPtr.Zero);
            if (handle.IsInvalid)
            {
                var error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, $"CreateFile failed for '{path}'.");
            }
            if (!GetFileInformationByHandle(handle.DangerousGetHandle(), out var info))
            {
                var error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, $"GetFileInformationByHandle failed for '{path}'.");
            }
            var isReparsePoint = (info.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0;
            if (isReparsePoint || info.NumberOfLinks != 1)
            {
                handle.Dispose();
                throw new IOException($"Bound mutation object is unsafe: '{path}'.");
            }
            var fileIndex = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow;
            var fileId = $"{info.VolumeSerialNumber:x8}{fileIndex:x16}".PadLeft(64, '0');
            var byteLength = ((ulong)info.FileSizeHigh << 32) | info.FileSizeLow;
            var writeTime = ((long)info.LastWriteTime.dwHighDateTime << 32) | (uint)info.LastWriteTime.dwLowDateTime;
            var lastWriteUtcTicks = DateTime.FromFileTimeUtc(writeTime).Ticks;
            if (!String.IsNullOrEmpty(expectedIdentityKey))
            {
                var expected = expectedIdentityKey.Split('|');
                if (expected.Length != 6 ||
                    UInt32.Parse(expected[0], System.Globalization.CultureInfo.InvariantCulture) != info.VolumeSerialNumber ||
                    !String.Equals(expected[1], fileId, StringComparison.OrdinalIgnoreCase) ||
                    UInt64.Parse(expected[2], System.Globalization.CultureInfo.InvariantCulture) != byteLength ||
                    Int64.Parse(expected[3], System.Globalization.CultureInfo.InvariantCulture) != lastWriteUtcTicks ||
                    UInt32.Parse(expected[4], System.Globalization.CultureInfo.InvariantCulture) != info.NumberOfLinks ||
                    Boolean.Parse(expected[5]) != isReparsePoint)
                {
                    handle.Dispose();
                    throw new IOException($"Bound mutation identity changed: '{path}' expected='{expectedIdentityKey}' actual='{info.VolumeSerialNumber}|{fileId}|{byteLength}|{lastWriteUtcTicks}|{info.NumberOfLinks}|{isReparsePoint}'.");
                }
            }
            return handle;
        }

        private static void RenameHandle(SafeFileHandle sourceHandle, SafeFileHandle parentHandle, string name, bool replace)
        {
            var bytes = System.Text.Encoding.Unicode.GetBytes(name + "\0");
            var nameBytes = checked((uint)(bytes.Length - sizeof(char)));
            var nameOffset = Marshal.OffsetOf<FileRenameInfoHeader>(nameof(FileRenameInfoHeader.FileNameLength)).ToInt32() + sizeof(uint);
            var bufferSize = checked(nameOffset + bytes.Length);
            var buffer = Marshal.AllocHGlobal(bufferSize);
            try
            {
                var header = new FileRenameInfoHeader { ReplaceIfExists = replace ? 1u : 0u, RootDirectory = parentHandle.DangerousGetHandle(), FileNameLength = nameBytes };
                Marshal.StructureToPtr(header, buffer, false);
                Marshal.Copy(bytes, 0, IntPtr.Add(buffer, nameOffset), bytes.Length);
                var ioStatus = new IoStatusBlock();
                var status = NtSetInformationFile(sourceHandle, out ioStatus, buffer, checked((uint)bufferSize), NtFileRenameInformation);
                if (status != 0)
                {
                    throw new IOException($"Handle-relative rename failed (NTSTATUS 0x{status:X8}).");
                }
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        private static void RenameBound(string source, string destination, bool replace, string sourceIdentityKey, string parentIdentityKey)
        {
            if (!OperatingSystem.IsWindows())
            {
                if (replace) File.Replace(source, destination, destination + ".previous", false);
                else File.Move(source, destination);
                return;
            }
            var parent = Path.GetDirectoryName(destination);
            var name = Path.GetFileName(destination);
            if (String.IsNullOrEmpty(parent) || String.IsNullOrEmpty(name)) throw new IOException("Bound rename path is invalid.");
            using var sourceHandle = OpenBoundPath(source, DeleteAccess | GenericRead, FileShareRead, FileFlagBackupSemantics | FileFlagOpenReparsePoint, sourceIdentityKey);
            using var parentHandle = OpenBoundPath(parent, DeleteAccess | FileReadAttributes | FileListDirectory | FileTraverse | FileAddFile, FileShareRead | FileShareWrite, FileFlagBackupSemantics | FileFlagOpenReparsePoint, parentIdentityKey);
            RenameHandle(sourceHandle, parentHandle, name, replace);
        }
        public static void MoveDirectory(string source, string destination) => RenameBound(source, destination, false, null, null);
        public static void MoveFile(string source, string destination) => RenameBound(source, destination, false, null, null);
        public static void MoveDirectoryBound(string source, string destination, string sourceIdentityKey, string parentIdentityKey) => RenameBound(source, destination, false, sourceIdentityKey, parentIdentityKey);
        public static void MoveFileBound(string source, string destination, string sourceIdentityKey, string parentIdentityKey) => RenameBound(source, destination, false, sourceIdentityKey, parentIdentityKey);

        public static void ReplaceFile(string source, string destination, string backup) => ReplaceFileBound(source, destination, backup, null, null, null);
        public static void ReplaceFileBound(string source, string destination, string backup, string sourceIdentityKey, string destinationIdentityKey, string parentIdentityKey)
        {
            if (!OperatingSystem.IsWindows()) { File.Replace(source, destination, backup, false); return; }
            var parent = Path.GetDirectoryName(destination);
            var name = Path.GetFileName(destination);
            var backupParent = Path.GetDirectoryName(backup);
            var backupName = Path.GetFileName(backup);
            if (String.IsNullOrEmpty(parent) || String.IsNullOrEmpty(name) || String.IsNullOrEmpty(backupParent) || String.IsNullOrEmpty(backupName) || !String.Equals(parent, backupParent, StringComparison.OrdinalIgnoreCase)) throw new IOException("Bound replace path is invalid.");
            using var parentHandle = OpenBoundPath(parent, DeleteAccess | FileReadAttributes | FileListDirectory | FileTraverse | FileAddFile, FileShareRead | FileShareWrite, FileFlagBackupSemantics | FileFlagOpenReparsePoint, parentIdentityKey);
            using var destinationHandle = OpenBoundPath(destination, DeleteAccess | GenericRead, FileShareRead, FileFlagOpenReparsePoint, destinationIdentityKey);
            using var sourceHandle = OpenBoundPath(source, DeleteAccess | GenericRead, FileShareRead, FileFlagOpenReparsePoint, sourceIdentityKey);
            RenameHandle(destinationHandle, parentHandle, backupName, false);
            RenameHandle(sourceHandle, parentHandle, name, false);
        }


        private static void DeleteHandle(SafeFileHandle handle, string path)
        {
            var info = new FileDispositionInfoEx { Flags = FileDispositionDelete };
            var buffer = Marshal.AllocHGlobal(Marshal.SizeOf<FileDispositionInfoEx>());
            try
            {
                Marshal.StructureToPtr(info, buffer, false);
                if (!SetFileInformationByHandle(handle, FileDispositionInformationEx, buffer, checked((uint)Marshal.SizeOf<FileDispositionInfoEx>())))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), $"Bound delete failed for '{path}'.");
                }
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        private static string GetPathIdentityKey(string path)
        {
            using var handle = OpenBoundPath(path, DeleteAccess | GenericRead, FileShareRead | FileShareWrite, FileFlagBackupSemantics | FileFlagOpenReparsePoint);
            if (!GetFileInformationByHandle(handle.DangerousGetHandle(), out var info)) throw new IOException($"Cannot inspect '{path}'.");
            var fileIndex = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow;
            var fileId = $"{info.VolumeSerialNumber:x8}{fileIndex:x16}".PadLeft(64, '0');
            var byteLength = ((ulong)info.FileSizeHigh << 32) | info.FileSizeLow;
            var writeTime = ((long)info.LastWriteTime.dwHighDateTime << 32) | (uint)info.LastWriteTime.dwLowDateTime;
            return $"{info.VolumeSerialNumber}|{fileId}|{byteLength}|{DateTime.FromFileTimeUtc(writeTime).Ticks}|{info.NumberOfLinks}|{(info.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0}";
        }

        private static void DeleteTreeBound(string path, string identityKey)
        {
            using var handle = OpenBoundPath(path, DeleteAccess | GenericRead, FileShareRead | FileShareWrite, FileFlagBackupSemantics | FileFlagOpenReparsePoint, identityKey);
            foreach (var child in Directory.GetFileSystemEntries(path))
            {
                var childKey = GetPathIdentityKey(child);
                if (Directory.Exists(child)) DeleteTreeBound(child, childKey);
                else DeleteFileBound(child, childKey);
            }
            DeleteHandle(handle, path);
        }

        public static void DeleteDirectoryTreeBound(string path, string identityKey)
        {
            if (!OperatingSystem.IsWindows()) { Directory.Delete(path, true); return; }
            DeleteTreeBound(path, identityKey);
        }

        public static void DeleteFile(string path) => DeleteFileBound(path, null);
        public static void DeleteFileBound(string path, string identityKey)
        {
            if (!OperatingSystem.IsWindows()) { File.Delete(path); return; }
            using var handle = OpenBoundPath(path, DeleteAccess | GenericRead, FileShareRead, FileFlagOpenReparsePoint, identityKey);
            DeleteHandle(handle, path);
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
