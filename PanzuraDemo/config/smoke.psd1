# PanzuraDemo v4 — smoke configuration.
# Reduced-scale overrides merged over default.psd1 for smoke validation.
# Keeps full mess injection semantics but runs in minutes.

@{
  Metadata = @{
    Version     = '4.0.0-smoke'
    Description = 'Reduced-scale smoke configuration.'
  }

  AD = @{
    BaseOUName = 'DemoCorp'
  }

  # Subset of departments, smaller user counts.
  # Keeping the full extension and subfolder sets so mess injection
  # still exercises all codepaths.
  Departments = @(
    @{
      Name = 'Finance'; SamPrefix = 'fin'
      UsersPerDept = @{ Min = 5; Max = 10 }
      SubFolders   = @('AP','AR','Budget','Tax','Audit')
      Extensions = @{
        '.xlsx'=30; '.pdf'=20; '.csv'=15; '.docx'=12
        '.xlsm'=5;  '.pptx'=3; '.xls'=5;  '.doc'=2
        '.msg'=3;   '.txt'=3;  '.bak'=1;  '.zip'=1
      }
    }
    @{
      Name = 'HR'; SamPrefix = 'hr'
      UsersPerDept = @{ Min = 4; Max = 8 }
      SubFolders   = @('Employees','Benefits','Onboarding','Policies')
      Extensions = @{
        '.docx'=30; '.pdf'=35; '.xlsx'=10; '.pptx'=5
        '.msg'=8;   '.txt'=5;  '.jpg'=3;   '.png'=2; '.zip'=2
      }
    }
    @{
      Name = 'Engineering'; SamPrefix = 'eng'
      UsersPerDept = @{ Min = 8; Max = 15 }
      SubFolders   = @('Source','Builds','Releases','Specs')
      Extensions = @{
        '.txt'=10; '.log'=20; '.json'=10; '.yaml'=5
        '.ps1'=10; '.cs'=8;   '.js'=6;    '.ts'=4
        '.xml'=5;  '.zip'=5;  '.pdf'=3;   '.md'=5
        '.py'=5;   '.sql'=2;  '.cfg'=2
      }
    }
    @{
      Name = 'IT'; SamPrefix = 'it'
      UsersPerDept = @{ Min = 5; Max = 10 }
      SubFolders   = @('Configs','Scripts','Logs','Backups','Credentials')
      Extensions = @{
        '.log'=25; '.cfg'=10; '.ini'=8;  '.ps1'=10
        '.bat'=5;  '.xml'=8;  '.json'=8; '.zip'=10
        '.exe'=3;  '.msi'=2;  '.bak'=5;  '.trn'=3
        '.sql'=2;  '.txt'=1
      }
    }
  )

  FolderTree = @{
    ArchiveYearRange = @{ Start = 2019; End = 2023 }
    UserHomeDirs = @{
      DeptScoped   = $true
      RootScoped   = $true
      DeptUserCount = 5
      RootFraction  = 0.4
    }
    MaxDepth        = 7
    CleanNamesOnly  = $true
    ProjectsPerDept = @{ Min = 1; Max = 2 }
    LegacyFolderChance = @{ DeptLevel = 0.30; SubDuplicate = 0.25 }
    CrossDeptFolders = @('Shared','Public','Board','__OLD__','_install_files')
  }

  Files = @{
    DefaultCount      = 2000
    DefaultDatePreset = 'RecentSkew'
    DefaultRecentBias = 70
    FolderCoherence   = $true
    FolderEraWindowDays = 90
    ArchiveYearOverrides  = $true
    ArchiveYearWindowDays = 180
    LegacyFossilRate  = 0.08
    HeavyTailDistribution = @(
      @{ Name='Empty'; Pct=1;  Min=0;    Max=0    }
      @{ Name='Small'; Pct=50; Min=1;    Max=20   }
      @{ Name='Med';   Pct=30; Min=21;   Max=100  }
      @{ Name='Large'; Pct=15; Min=101;  Max=500  }
      @{ Name='Mega';  Pct=4;  Min=501;  Max=2000 }
      # no Ultra in smoke
    )
    Attributes = @{
      ReadOnlyChance = 0.05
      HiddenChance   = 0.02
      AdsChance      = 0.15
    }
    Ownership = @{
      DeptGroup      = 0.55
      User           = 0.25
      ServiceAccount = 0.05
      OrphanSid      = 0.10
      BuiltinAdmin   = 0.05
    }
    FileLevelAcl = @{
      PureInheritance   = 0.97
      ExplicitUserAce   = 0.01
      ExplicitOrphanAce = 0.005
      DetachedAcl       = 0.005
      ExplicitDenyAce   = 0.01
    }
  }

  Mess = @{
    OrphanSidCount = 5
    ServiceAccounts = @(
      @{ Name='svc_backup';    Description='Backup service account'; PathPatterns=@('*Archive*','*Backups*') }
      @{ Name='svc_sql';       Description='SQL Server service';     PathPatterns=@('*IT*Backups*','*Finance*') }
      @{ Name='svc_fileshare'; Description='File share service';     PathPatterns=@('*') }
    )
  }

  Scenarios = @{
    Smoke = @{
      Description = 'Smoke validation: 2000 files, RecentSkew, single run.'
      Runs = @(
        @{ MaxFiles = 2000; DatePreset = 'RecentSkew'; RecentBias = 50 }
      )
    }
  }
}
