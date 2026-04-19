using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.IO;
using System.ComponentModel;

namespace PanzuraDemo.Native {

    /// <summary>
    /// DeviceIoControl P/Invoke for FSCTL_SET_SPARSE.
    /// Called once per file on an open FileStream handle — eliminates
    /// per-file cmd.exe process forks used by fsutil.
    /// </summary>
    public static class Sparse {

        private const uint FSCTL_SET_SPARSE = 0x000900C4;

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeviceIoControl(
            SafeFileHandle hDevice,
            uint dwIoControlCode,
            IntPtr lpInBuffer,
            uint nInBufferSize,
            IntPtr lpOutBuffer,
            uint nOutBufferSize,
            out uint lpBytesReturned,
            IntPtr lpOverlapped);

        public static void SetSparse(SafeFileHandle handle) {
            if (handle == null || handle.IsInvalid || handle.IsClosed)
                throw new ArgumentException("SafeFileHandle is invalid or closed.", "handle");
            uint bytesReturned;
            bool ok = DeviceIoControl(handle, FSCTL_SET_SPARSE,
                                      IntPtr.Zero, 0,
                                      IntPtr.Zero, 0,
                                      out bytesReturned, IntPtr.Zero);
            if (!ok) {
                int err = Marshal.GetLastWin32Error();
                throw new Win32Exception(err, "DeviceIoControl(FSCTL_SET_SPARSE) failed: " + err);
            }
        }

        /// <summary>
        /// Query whether a path has the FILE_ATTRIBUTE_SPARSE_FILE bit set.
        /// Convenience for verification tests.
        /// </summary>
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint GetFileAttributesW(string lpFileName);

        private const uint FILE_ATTRIBUTE_SPARSE_FILE = 0x00000200;
        private const uint INVALID_FILE_ATTRIBUTES   = 0xFFFFFFFF;

        public static bool IsSparse(string path) {
            uint attrs = GetFileAttributesW(path);
            if (attrs == INVALID_FILE_ATTRIBUTES) return false;
            return (attrs & FILE_ATTRIBUTE_SPARSE_FILE) != 0;
        }
    }
}
