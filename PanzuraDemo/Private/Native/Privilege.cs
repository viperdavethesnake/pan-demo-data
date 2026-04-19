using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.ComponentModel;

namespace PanzuraDemo.Native {

    /// <summary>
    /// Enable a named token privilege (e.g. SeRestorePrivilege,
    /// SeTakeOwnershipPrivilege). Called once at module load for the
    /// whole process so ownership operations don't thrash privileges
    /// per file.
    /// </summary>
    public static class Privilege {

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES {
            public uint PrivilegeCount;
            public LUID_AND_ATTRIBUTES Privileges;
        }

        private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        private const uint TOKEN_QUERY             = 0x0008;
        private const uint SE_PRIVILEGE_ENABLED    = 0x00000002;

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(
            IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool LookupPrivilegeValue(
            string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AdjustTokenPrivileges(
            IntPtr TokenHandle,
            [MarshalAs(UnmanagedType.Bool)] bool DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState,
            uint BufferLength,
            IntPtr PreviousState,
            IntPtr ReturnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr hObject);

        public static bool EnablePrivilege(string privilegeName) {
            IntPtr hToken = IntPtr.Zero;
            try {
                if (!OpenProcessToken(Process.GetCurrentProcess().Handle,
                                      TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
                                      out hToken)) {
                    return false;
                }
                LUID luid;
                if (!LookupPrivilegeValue(null, privilegeName, out luid)) {
                    return false;
                }
                TOKEN_PRIVILEGES tp;
                tp.PrivilegeCount = 1;
                tp.Privileges.Luid = luid;
                tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;
                if (!AdjustTokenPrivileges(hToken, false, ref tp,
                                           (uint)Marshal.SizeOf(typeof(TOKEN_PRIVILEGES)),
                                           IntPtr.Zero, IntPtr.Zero)) {
                    return false;
                }
                // AdjustTokenPrivileges can return true even when the privilege
                // wasn't assigned — check GetLastError for ERROR_NOT_ALL_ASSIGNED (1300).
                int err = Marshal.GetLastWin32Error();
                return err == 0;
            } finally {
                if (hToken != IntPtr.Zero) CloseHandle(hToken);
            }
        }
    }
}
