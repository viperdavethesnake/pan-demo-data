using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ComponentModel;

namespace PanzuraDemo.Native {

    /// <summary>
    /// Direct-kernel owner set via SetNamedSecurityInfoW with
    /// OWNER_SECURITY_INFORMATION. Skips both Get-Acl (no ACL read) and
    /// Set-Acl (no PowerShell cmdlet overhead), and takes a pre-resolved
    /// SID byte array so there is no LSA round-trip per file.
    ///
    /// Caller must pre-resolve an NTAccount to its SID bytes once (use
    /// <see cref="GetSidBytesFromAccount"/>) and cache the byte[] for the
    /// full run. Cost model: one DeviceIoControl-shaped kernel call per
    /// file, no managed allocations, no PS pipeline overhead.
    /// </summary>
    public static class SecurityNative {

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint SetNamedSecurityInfoW(
            string pObjectName,
            int ObjectType,
            uint SecurityInfo,
            IntPtr psidOwner,
            IntPtr psidGroup,
            IntPtr pDacl,
            IntPtr pSacl);

        private const int  SE_FILE_OBJECT              = 1;
        private const uint OWNER_SECURITY_INFORMATION  = 0x00000001;

        /// <summary>Set only the owner section of a file's security descriptor.</summary>
        public static void SetOwner(string path, byte[] sidBytes) {
            if (string.IsNullOrEmpty(path))
                throw new ArgumentException("path is null/empty");
            if (sidBytes == null || sidBytes.Length == 0)
                throw new ArgumentException("sidBytes is null/empty");

            GCHandle pin = GCHandle.Alloc(sidBytes, GCHandleType.Pinned);
            try {
                IntPtr pSid = pin.AddrOfPinnedObject();
                uint rc = SetNamedSecurityInfoW(
                    path,
                    SE_FILE_OBJECT,
                    OWNER_SECURITY_INFORMATION,
                    pSid,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    IntPtr.Zero);
                if (rc != 0) {
                    throw new Win32Exception((int)rc,
                        "SetNamedSecurityInfoW failed (" + rc + ") on path: " + path);
                }
            } finally {
                pin.Free();
            }
        }

        /// <summary>Resolve DOMAIN\name to a SID byte array (one LSA call).</summary>
        public static byte[] GetSidBytesFromAccount(string account) {
            var nt = new NTAccount(account);
            var sid = (SecurityIdentifier)nt.Translate(typeof(SecurityIdentifier));
            var bytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(bytes, 0);
            return bytes;
        }
    }
}
