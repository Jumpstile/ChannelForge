function Initialize-ChannelForgeProcessJob {
    [CmdletBinding()]
    param()

    if (-not [OperatingSystem]::IsWindows()) {
        throw 'Process job isolation is only implemented for Windows hosts.'
    }

    $typeName = 'ChannelForge.ProcessJob'
    $existing = [AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object { $_.GetType($typeName, $false, $false) } |
        Where-Object { $null -ne $_ } |
        Select-Object -First 1
    if ($null -ne $existing) {
        return [Activator]::CreateInstance($existing)
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ChannelForge
{
    public sealed class ProcessJob : IDisposable
    {
        private const int JobObjectExtendedLimitInformationClass = 9;
        private const uint JobObjectLimitKillOnJobClose = 0x00002000;
        private IntPtr _handle;

        [StructLayout(LayoutKind.Sequential)]
        private struct JobObjectBasicLimitInformation
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JobObjectExtendedLimitInformation
        {
            public JobObjectBasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr jobAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int jobObjectInformationClass,
            IntPtr jobObjectInformation,
            uint jobObjectInformationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public ProcessJob()
        {
            _handle = CreateJobObject(IntPtr.Zero, null);
            if (_handle == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed.");
            }

            var limits = new JobObjectExtendedLimitInformation();
            limits.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
            var pointer = Marshal.AllocHGlobal(Marshal.SizeOf<JobObjectExtendedLimitInformation>());
            try
            {
                Marshal.StructureToPtr(limits, pointer, false);
                if (!SetInformationJobObject(
                        _handle,
                        JobObjectExtendedLimitInformationClass,
                        pointer,
                        checked((uint)Marshal.SizeOf<JobObjectExtendedLimitInformation>())))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "SetInformationJobObject failed.");
                }
            }
            catch
            {
                Dispose();
                throw;
            }
            finally
            {
                Marshal.FreeHGlobal(pointer);
            }
        }

        public void Assign(IntPtr processHandle)
        {
            if (_handle == IntPtr.Zero) throw new ObjectDisposedException(nameof(ProcessJob));
            if (!AssignProcessToJobObject(_handle, processHandle))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject failed.");
            }
        }

        public void Dispose()
        {
            var handle = System.Threading.Interlocked.Exchange(ref _handle, IntPtr.Zero);
            if (handle != IntPtr.Zero) CloseHandle(handle);
        }
    }
}
'@ -Language CSharp -ErrorAction Stop | Out-Null

    return [ChannelForge.ProcessJob]::new()
}
