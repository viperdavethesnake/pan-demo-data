# Panzura Symphony Demo Environment

This repo of PowerShell scripts builds a **messy, realistic Windows file share** with
randomized AD users/groups, departmental folder trees, and randomized file contents.
It’s designed to mimic an enterprise share for scanning/analytics with **Panzura Symphony**.

---

## Scripts Overview

### 1. Active Directory
- **`ad-populator_v3.ps1`**
  - Creates OUs under `DemoCorp`.
  - Randomized number of users per department (`-UsersPerDeptMin / -UsersPerDeptMax`).
  - Creates groups:
    - `GG_AllEmployees`
    - `GG_<Dept>` for each department
    - Optional: `GG_<Dept>_{RO,RW,Owners}` with `-CreateAccessTiers`
    - Optional: `GG_<Dept>_Mgmt`, `GG_<Dept>_Leads`, `GG_<Dept>_Contractors`, `GG_<Dept>_Interns`, `GG_<Dept>_Auditors`
    - Optional: `DL_Share_<Dept>_{RO,RW,Owners}` with `-CreateAGDLP` (AGDLP pattern)
    - Optional: `PG_<Dept>_<ProjectCode>` with `-ProjectsPerDeptMin / -ProjectsPerDeptMax`
  - Users are assigned to realistic groups (RW, some RO/Owners, sprinkled into role/project groups).

### 2. Privilege Helpers
- **`set-privs.psm1`**
  - Enables `SeRestorePrivilege` and `SeTakeOwnershipPrivilege`.
  - `Set-OwnerAndGroup`: set file/folder owner + group.
  - `Grant-FsAccess`: apply NTFS ACEs with inheritance/break options.

### 3. Folders
- **`create-folders_v2.ps1`**
  - Ensures `S:\Shared` exists.
  - Creates/updates SMB share `\\<server>\Shared`.
    - `Domain Admins`: Full
    - `GG_AllEmployees`: Read
    - Removes `Everyone` if present
  - Creates departmental trees with subfolders (`Projects`, `Archive`, `Temp`, `Sensitive`, `Vendors`).
  - Prefers **Domain Local (DL_Share)** groups if present (`-UseDomainLocal`), else uses `GG_*` groups.
  - Randomly breaks inheritance, sprinkles Deny ACEs.

### 4. Files
- **`create-files_v3.ps1`**
  - Populates each folder with a **random number of files** (Normal distribution per folder type).
  - Random extensions, sizes (1 KB – 16 MB), timestamps (spread over 10 years).
  - ~20% of files get an **individual user** as owner (else dept group).
  - Sprinkles RO or Deny ACEs; prefers `DL_Share_<Dept>_RO` if present.
  - Adds extra random subfolders (`Q1-017`, `Backlog-302`, etc.) to mess up the tree.
  - Use `-MaxFiles` to cap total.

### 5. Reporting
- **`demo-report.ps1`**
  - Summarizes AD:
    - Users per department
    - Counts of GG*, DL*, PG* groups
  - Share check: verifies `S:\Shared` SMB share and permissions.
  - Filesystem counts: folders, files.
  - Optional ACL sample (`-Fast` to skip).
  - Shows sample folders and files.

---

## Usage Order

Run PowerShell **as Domain Admin**:

```powershell
# 1. Build randomized AD
.\ad-populator_v3.ps1 `
  -BaseOUName DemoCorp `
  -UsersPerDeptMin 8 -UsersPerDeptMax 75 `
  -CreateAccessTiers `
  -RoleGroups Mgmt,Leads,Contractors,Interns,Auditors `
  -CreateAGDLP `
  -ProjectsPerDeptMin 1 -ProjectsPerDeptMax 4 `
  -VerboseSummary

# 2. Import privilege helpers
Import-Module .\set-privs.psm1

# 3. Build folder/share structure
.\create-folders_v2.ps1 -UseDomainLocal

# 4. Populate messy files
.\create-files_v3.ps1 -MaxFiles 10000   # cap optional

# 5. Run report to validate/demo
.\demo-report.ps1 -Sample 15
```

---

## Customization

- **Departments**: pass `-Departments "Finance","HR","R&D"` to AD script.
- **Users**: adjust `-UsersPerDeptMin` / `-UsersPerDeptMax`.
- **Extra groups**:
  - `-CreateAccessTiers` → RW/RO/Owners groups.
  - `-RoleGroups ...` → add/remove role-based groups.
  - `-CreateAGDLP` → DL_Share groups for AGDLP best practice.
  - `-ProjectsPerDeptMin/Max` → per-dept project groups.
- **Folders**:
  - `-UseDomainLocal` to prefer DL groups if present.
  - Auto SMB share: `-CreateShare:$false` to skip share creation.
- **Files**:
  - Tuning knobs: `-FilesPerFolderMean`, `-FilesPerFolderStd`, `-MaxFiles`.
  - Adds extra nested subfolders randomly.

---

## Example Outputs

- **AD**: 8–75 users per dept; dozens of GG_/DL_/PG_ groups with cross-membership.
- **Folders**: `S:\Shared\<Dept>\{Projects,Archive,Temp,Sensitive,Vendors}` + random extras.
- **Files**: Thousands of files, messy timestamps, inconsistent owners, Deny ACEs sprinkled in.
- **Report**: Quick sanity check before Symphony scanning.

---

## Reset / Re-run

To re-run demos cleanly:
1. Remove `S:\Shared` contents and the `Shared` SMB share.
2. Rerun `create-folders_v2.ps1` and `create-files_v3.ps1`.
3. AD objects are idempotent — rerunning `ad-populator_v3.ps1` reuses existing OUs/groups/users.

---
