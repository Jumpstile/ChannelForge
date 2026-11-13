if (-not ('ChannelForge.KnowledgeNativeIO' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace ChannelForge
{
    public static class KnowledgeNativeIO
    {
        private const uint FileListDirectory = 0x00000001;
        private const uint FileAddFile = 0x00000002;
        private const uint FileDeleteChild = 0x00000040;
        private const uint FileReadAttributes = 0x00000080;
        private const uint FileWriteAttributes = 0x00000100;
        private const uint DeleteAccess = 0x00010000;
        private const uint Synchronize = 0x00100000;
        private const uint GenericRead = 0x80000000;
        private const uint GenericWrite = 0x40000000;
        private const uint ShareRead = 0x00000001;
        private const uint ShareWrite = 0x00000002;
        private const uint ObjectCaseInsensitive = 0x00000040;
        private const uint ObjectDontReparse = 0x00001000;
        private const uint FileOpen = 1;
        private const uint FileCreate = 2;
        private const uint FileOpenIf = 3;
        private const uint FileDirectoryFile = 0x00000001;
        private const uint FileSynchronousIoNonalert = 0x00000020;
        private const uint FileNonDirectoryFile = 0x00000040;
        private const uint FileOpenReparsePoint = 0x00200000;
        private const uint FileAttributeDirectory = 0x00000010;
        private const uint FileAttributeReparsePoint = 0x00000400;
        private const uint FileAttributeNormal = 0x00000080;
        private const uint FileFlagBackupSemantics = 0x02000000;
        private const uint FileFlagOpenReparsePoint = 0x00200000;
        private const int FileAttributeTagInfoClass = 9;
        private const int FileDispositionInfoClass = 4;
        private const int NtFileRenameInformation = 10;
        private const int StatusObjectNameNotFound = unchecked((int)0xC0000034);
        private const int StatusObjectPathNotFound = unchecked((int)0xC000003A);

        [StructLayout(LayoutKind.Sequential)]
        private struct UnicodeString
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ObjectAttributes
        {
            public uint Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoStatusBlock
        {
            public IntPtr Status;
            public IntPtr Information;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileAttributeTagInfo
        {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileRenameInfoHeader
        {
            public uint ReplaceIfExists;
            public IntPtr RootDirectory;
            public uint FileNameLength;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
        private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, out FileAttributeTagInfo info, uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, IntPtr info, uint size);

        [DllImport("ntdll.dll")]
        private static extern int NtCreateFile(out SafeFileHandle handle, uint access, ref ObjectAttributes attributes, out IoStatusBlock status, IntPtr allocationSize, uint fileAttributes, uint share, uint disposition, uint options, IntPtr eaBuffer, uint eaLength);

        [DllImport("ntdll.dll")]
        private static extern uint RtlNtStatusToDosError(int status);
        [DllImport("ntdll.dll")]
        private static extern int NtSetInformationFile(SafeFileHandle handle, out IoStatusBlock status, IntPtr info, uint length, int infoClass);

        public static SafeFileHandle[] OpenDirectoryChain(string fullPath)
        {
            if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Knowledge state requires Windows handle-relative filesystem operations.");
            string full = Path.GetFullPath(fullPath);
            string volume = Path.GetPathRoot(full);
            if (String.IsNullOrEmpty(volume) || volume.StartsWith("\\\\", StringComparison.Ordinal)) throw new IOException("UNC knowledge roots are not supported.");
            var handles = new List<SafeFileHandle>();
            try
            {
                SafeFileHandle current = CreateFile(volume, FileListDirectory | FileReadAttributes | Synchronize, ShareRead | ShareWrite, IntPtr.Zero, 3, FileFlagBackupSemantics | FileFlagOpenReparsePoint, IntPtr.Zero);
                ThrowIfInvalid(current, "Could not open knowledge volume root.");
                VerifyHandle(current, true);
                handles.Add(current);
                string relative = full.Substring(volume.Length);
                foreach (string part in relative.Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    SafeFileHandle child = OpenDirectory(current, part, false);
                    handles.Add(child);
                    current = child;
                }
                return handles.ToArray();
            }
            catch
            {
                foreach (SafeFileHandle handle in handles) handle.Dispose();
                throw;
            }
        }

        public static SafeFileHandle OpenOrCreateDirectory(SafeFileHandle parent, string name)
        {
            return OpenRelative(parent, name, FileListDirectory | FileAddFile | FileDeleteChild | FileReadAttributes | FileWriteAttributes | Synchronize, ShareRead | ShareWrite, FileOpenIf, FileDirectoryFile | FileSynchronousIoNonalert | FileOpenReparsePoint, FileAttributeDirectory, true);
        }
        public static SafeFileHandle OpenDirectoryIfExists(SafeFileHandle parent, string name)
        {
            return OpenRelative(parent, name, FileListDirectory | FileReadAttributes | Synchronize, ShareRead | ShareWrite, FileOpen, FileDirectoryFile | FileSynchronousIoNonalert | FileOpenReparsePoint, FileAttributeDirectory, true, true);
        }

        public static SafeFileHandle OpenFile(SafeFileHandle parent, string name, bool createNew, bool openOrCreate, bool writable, uint share, bool allowMissing)
        {
            uint disposition = createNew ? FileCreate : openOrCreate ? FileOpenIf : FileOpen;
            uint access = writable ? (GenericRead | GenericWrite | DeleteAccess | Synchronize) : (GenericRead | FileReadAttributes | Synchronize);
            uint options = FileNonDirectoryFile | FileSynchronousIoNonalert | FileOpenReparsePoint;
            return OpenRelative(parent, name, access, share, disposition, options, FileAttributeNormal, false, allowMissing);
        }
        public static void Rename(SafeFileHandle source, SafeFileHandle targetDirectory, string targetName, bool replace)
        {
            ValidateName(targetName);
            byte[] bytes = System.Text.Encoding.Unicode.GetBytes(targetName + "\0");
            uint nameLength = checked((uint)(bytes.Length - sizeof(char)));
            int nameOffset = Marshal.OffsetOf<FileRenameInfoHeader>(nameof(FileRenameInfoHeader.FileNameLength)).ToInt32() + sizeof(uint);
            IntPtr buffer = Marshal.AllocHGlobal(nameOffset + bytes.Length);
            try
            {
                var header = new FileRenameInfoHeader { ReplaceIfExists = replace ? 1u : 0u, RootDirectory = targetDirectory.DangerousGetHandle(), FileNameLength = nameLength };
                Marshal.StructureToPtr(header, buffer, false);
                Marshal.Copy(bytes, 0, IntPtr.Add(buffer, nameOffset), bytes.Length);
                int status = NtSetInformationFile(source, out IoStatusBlock ioStatus, buffer, checked((uint)(nameOffset + bytes.Length)), NtFileRenameInformation);
                if (status != 0) throw new IOException("Handle-relative knowledge rename failed (NTSTATUS 0x" + unchecked((uint)status).ToString("X8") + ").");
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }


        public static void Delete(SafeFileHandle file)
        {
            IntPtr buffer = Marshal.AllocHGlobal(1);
            try
            {
                Marshal.WriteByte(buffer, 1);
                if (!SetFileInformationByHandle(file, FileDispositionInfoClass, buffer, 1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not delete knowledge file by handle.");
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        private static SafeFileHandle OpenDirectory(SafeFileHandle parent, string name, bool create)
        {
            uint disposition = create ? FileOpenIf : FileOpen;
            return OpenRelative(parent, name, FileListDirectory | FileReadAttributes | Synchronize, ShareRead | ShareWrite, disposition, FileDirectoryFile | FileSynchronousIoNonalert | FileOpenReparsePoint, FileAttributeDirectory, true);
        }

        private static SafeFileHandle OpenRelative(SafeFileHandle parent, string name, uint access, uint share, uint disposition, uint options, uint attributes, bool directory, bool allowMissing = false)
        {
            ValidateName(name);
            IntPtr text = Marshal.StringToHGlobalUni(name);
            IntPtr unicodePointer = IntPtr.Zero;
            try
            {
                var unicode = new UnicodeString { Length = checked((ushort)(name.Length * 2)), MaximumLength = checked((ushort)(name.Length * 2 + 2)), Buffer = text };
                unicodePointer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
                Marshal.StructureToPtr(unicode, unicodePointer, false);
                var objectAttributes = new ObjectAttributes { Length = (uint)Marshal.SizeOf<ObjectAttributes>(), RootDirectory = parent.DangerousGetHandle(), ObjectName = unicodePointer, Attributes = ObjectCaseInsensitive | ObjectDontReparse };
                IoStatusBlock status;
                int result = NtCreateFile(out SafeFileHandle handle, access, ref objectAttributes, out status, IntPtr.Zero, attributes, share, disposition, options, IntPtr.Zero, 0);
                if (result < 0)
                {
                    if (allowMissing && (result == StatusObjectNameNotFound || result == StatusObjectPathNotFound)) return null;
                    throw new Win32Exception((int)RtlNtStatusToDosError(result), "Could not open knowledge path component '" + name + "' without following reparse points (NTSTATUS 0x" + unchecked((uint)result).ToString("X8") + ").");
                }
                try { VerifyHandle(handle, directory); return handle; }
                catch { handle.Dispose(); throw; }
            }
            finally
            {
                if (unicodePointer != IntPtr.Zero) Marshal.FreeHGlobal(unicodePointer);
                Marshal.FreeHGlobal(text);
            }
        }

        private static void VerifyHandle(SafeFileHandle handle, bool directory)
        {
            if (handle == null || handle.IsInvalid) throw new IOException("Knowledge path handle is invalid.");
            if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfoClass, out FileAttributeTagInfo info, (uint)Marshal.SizeOf<FileAttributeTagInfo>())) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not inspect knowledge path handle.");
            if ((info.FileAttributes & FileAttributeReparsePoint) != 0 || (((info.FileAttributes & FileAttributeDirectory) != 0) != directory)) throw new IOException("Knowledge path contains a reparse point or has the wrong file type.");
        }

        private static void ValidateName(string name)
        {
            if (String.IsNullOrWhiteSpace(name) || name == "." || name == ".." || name.IndexOfAny(new[] { '\\', '/', '\0' }) >= 0) throw new IOException("Knowledge handle-relative path component is invalid.");
        }

        private static void ThrowIfInvalid(SafeFileHandle handle, string message)
        {
            if (handle == null || handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), message);
        }
    }
}
'@ -ErrorAction Stop
}
