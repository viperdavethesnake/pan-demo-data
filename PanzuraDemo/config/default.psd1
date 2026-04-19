# PanzuraDemo v4 — default configuration.
# Values here are the canonical source for the full-scale run.
# config/smoke.psd1 is merged over this for smoke validation.
# Import-DemoConfig does the merge.

@{
  Metadata = @{
    Version     = '4.1.0'
    Description = 'Full-scale messy enterprise NAS generator.'
  }

  Share = @{
    Root        = 'S:\Shared'
    Name        = 'Shared'
    CreateShare = $true
  }

  AD = @{
    BaseOUName   = 'DemoCorp'
    MailDomain   = $null        # null = use AD DNS root
    Password     = 'P@nz!demo-2026'
    UsersOU      = 'Users'
    GroupsOU     = 'Groups'
    ServiceOU    = 'ServiceAccounts'
  }

  # --- Departments --------------------------------------------------------
  # Each dept is a self-contained record: SAM prefix (for sam fallback),
  # user-count range, list of sub-folders, and a weighted extension map.
  # 15 departments total.
  Departments = @(
    @{
      Name = 'Finance'; SamPrefix = 'fin'
      UsersPerDept = @{ Min = 25; Max = 40 }
      SubFolders   = @('AP','AR','Payroll','Budget','Tax','Audit','Forecasts','GeneralLedger')
      Extensions = @{
        '.xlsx'=25; '.pdf'=15; '.csv'=15; '.docx'=10
        '.xlsm'=5;  '.pptx'=3; '.xls'=8;  '.doc'=3
        '.ppt'=1;   '.accdb'=1; '.mdb'=1; '.msg'=3
        '.zip'=2;   '.7z'=1;  '.txt'=3;  '.log'=2
        '.tsv'=1;   '.bak'=0.5; '.tmp'=0.5
      }
    }
    @{
      Name = 'HR'; SamPrefix = 'hr'
      UsersPerDept = @{ Min = 12; Max = 22 }
      SubFolders   = @('Employees','Benefits','Onboarding','Reviews','Policies','Recruiting','Compliance')
      Extensions = @{
        '.docx'=25; '.pdf'=30; '.xlsx'=10; '.pptx'=5
        '.doc'=5;   '.xls'=3;  '.msg'=8;  '.txt'=5
        '.zip'=2;   '.jpg'=3;  '.png'=2;  '.rtf'=1
        '.bak'=0.5
      }
    }
    @{
      Name = 'Engineering'; SamPrefix = 'eng'
      UsersPerDept = @{ Min = 35; Max = 55 }
      SubFolders   = @('Source','Builds','Releases','Specs','Reviews','Incidents','Sandbox')
      Extensions = @{
        '.txt'=10; '.log'=15; '.json'=10; '.yaml'=5
        '.ps1'=8;  '.psm1'=2; '.cs'=6;   '.js'=6
        '.ts'=4;   '.xml'=5;  '.zip'=4;  '.pdf'=3
        '.md'=4;   '.py'=5;   '.sh'=2;   '.java'=3
        '.sql'=3;  '.docx'=3; '.cfg'=2;  '.ini'=1
      }
    }
    @{
      Name = 'Sales'; SamPrefix = 'sal'
      UsersPerDept = @{ Min = 40; Max = 60 }
      SubFolders   = @('Clients','Pipeline','Proposals','Contracts','Commissions','Forecasts')
      Extensions = @{
        '.xlsx'=25; '.docx'=20; '.pptx'=18; '.pdf'=18
        '.msg'=10;  '.zip'=4;  '.xls'=3;   '.doc'=2
      }
    }
    @{
      Name = 'Legal'; SamPrefix = 'leg'
      UsersPerDept = @{ Min = 4; Max = 8 }
      SubFolders   = @('Contracts','Matters','IP','Compliance','Litigation','NDA')
      Extensions = @{
        '.pdf'=45; '.docx'=25; '.doc'=5; '.xlsx'=8
        '.msg'=8;  '.pptx'=3;  '.zip'=3; '.rtf'=2; '.txt'=1
      }
    }
    @{
      Name = 'IT'; SamPrefix = 'it'
      UsersPerDept = @{ Min = 20; Max = 35 }
      SubFolders   = @('Configs','Scripts','Logs','Backups','Installs','Apps','Credentials')
      Extensions = @{
        '.log'=25; '.cfg'=10; '.ini'=8;  '.ps1'=10
        '.bat'=5;  '.vbs'=2;  '.xml'=8;  '.json'=8
        '.zip'=10; '.exe'=3;  '.msi'=2;  '.bak'=3
        '.trn'=2;  '.sql'=2;  '.txt'=2
      }
    }
    @{
      Name = 'Ops'; SamPrefix = 'ops'
      UsersPerDept = @{ Min = 15; Max = 25 }
      SubFolders   = @('Runbooks','Inventory','Incidents','Workflows','Schedules')
      Extensions = @{
        '.xlsx'=20; '.docx'=20; '.pdf'=18; '.csv'=12
        '.txt'=12;  '.pptx'=7;  '.zip'=5;  '.log'=3
        '.msg'=3
      }
    }
    @{
      Name = 'Marketing'; SamPrefix = 'mkt'
      UsersPerDept = @{ Min = 15; Max = 28 }
      SubFolders   = @('Campaigns','Brand','Social','Events','Assets','Analytics')
      Extensions = @{
        '.pptx'=30; '.docx'=10; '.xlsx'=7;  '.png'=15
        '.jpg'=12;  '.pdf'=10;  '.zip'=5;   '.psd'=3
        '.ai'=2;    '.mp4'=3;   '.html'=2;  '.svg'=1
      }
    }
    @{
      Name = 'R&D'; SamPrefix = 'rnd'
      UsersPerDept = @{ Min = 25; Max = 45 }
      SubFolders   = @('Research','Prototypes','Experiments','Patents','LabData')
      Extensions = @{
        '.txt'=15; '.pdf'=20; '.docx'=12; '.xlsx'=8
        '.xml'=8;  '.json'=8; '.zip'=10;  '.cs'=4
        '.py'=6;   '.csv'=5;  '.md'=3;    '.log'=1
      }
    }
    @{
      Name = 'QA'; SamPrefix = 'qa'
      UsersPerDept = @{ Min = 18; Max = 30 }
      SubFolders   = @('TestPlans','TestResults','Automation','Bugs','Performance')
      Extensions = @{
        '.log'=25; '.txt'=15; '.csv'=10; '.json'=10
        '.xml'=10; '.zip'=10; '.docx'=5; '.xlsx'=8
        '.ps1'=4;  '.js'=3
      }
    }
    @{
      Name = 'Facilities'; SamPrefix = 'fac'
      UsersPerDept = @{ Min = 5; Max = 10 }
      SubFolders   = @('Blueprints','Maintenance','Leases','Safety','Incidents')
      Extensions = @{
        '.pdf'=28; '.docx'=22; '.xlsx'=18; '.jpg'=10
        '.png'=8;  '.txt'=4;   '.dwg'=5;   '.vsd'=3; '.dxf'=2
      }
    }
    @{
      Name = 'Procurement'; SamPrefix = 'pro'
      UsersPerDept = @{ Min = 8; Max = 15 }
      SubFolders   = @('RFPs','POs','Vendors','Contracts','Receiving')
      Extensions = @{
        '.xlsx'=30; '.pdf'=28; '.docx'=22; '.csv'=6
        '.msg'=8;   '.zip'=3;  '.xls'=3
      }
    }
    @{
      Name = 'Logistics'; SamPrefix = 'log'
      UsersPerDept = @{ Min = 10; Max = 20 }
      SubFolders   = @('Shipments','Inventory','Customs','Tracking')
      Extensions = @{
        '.csv'=35; '.xlsx'=28; '.pdf'=15; '.docx'=10
        '.zip'=5;  '.xml'=4;   '.json'=3
      }
    }
    @{
      Name = 'Training'; SamPrefix = 'trn'
      UsersPerDept = @{ Min = 6; Max = 12 }
      SubFolders   = @('Curriculum','Materials','Schedules','Certificates')
      Extensions = @{
        '.pptx'=35; '.docx'=22; '.pdf'=20; '.xlsx'=10
        '.zip'=5;   '.mp4'=4;   '.jpg'=2;  '.png'=2
      }
    }
    @{
      Name = 'Support'; SamPrefix = 'sup'
      UsersPerDept = @{ Min = 30; Max = 50 }
      SubFolders   = @('Tickets','KB','Escalations','Reports')
      Extensions = @{
        '.log'=30; '.txt'=20; '.docx'=10; '.pdf'=10
        '.csv'=10; '.zip'=5;  '.xlsx'=5;  '.json'=5
        '.md'=5
      }
    }
  )

  # --- Extension size bands (KB) -----------------------------------------
  ExtensionProperties = @{
    '.docx' = @{ MinKB = 8;    MaxKB = 2048 }
    '.doc'  = @{ MinKB = 16;   MaxKB = 1024 }
    '.xlsx' = @{ MinKB = 16;   MaxKB = 8192 }
    '.xlsm' = @{ MinKB = 16;   MaxKB = 8192 }
    '.xls'  = @{ MinKB = 32;   MaxKB = 4096 }
    '.pdf'  = @{ MinKB = 32;   MaxKB = 16384 }
    '.pptx' = @{ MinKB = 64;   MaxKB = 32768 }
    '.ppt'  = @{ MinKB = 64;   MaxKB = 16384 }
    '.txt'  = @{ MinKB = 1;    MaxKB = 512 }
    '.md'   = @{ MinKB = 1;    MaxKB = 256 }
    '.jpg'  = @{ MinKB = 128;  MaxKB = 4096 }
    '.png'  = @{ MinKB = 64;   MaxKB = 2048 }
    '.gif'  = @{ MinKB = 32;   MaxKB = 1024 }
    '.bmp'  = @{ MinKB = 256;  MaxKB = 8192 }
    '.svg'  = @{ MinKB = 1;    MaxKB = 128 }
    '.zip'  = @{ MinKB = 256;  MaxKB = 65536 }
    '.7z'   = @{ MinKB = 256;  MaxKB = 65536 }
    '.csv'  = @{ MinKB = 4;    MaxKB = 1024 }
    '.tsv'  = @{ MinKB = 4;    MaxKB = 1024 }
    '.log'  = @{ MinKB = 8;    MaxKB = 51200 }
    '.xml'  = @{ MinKB = 4;    MaxKB = 512 }
    '.json' = @{ MinKB = 2;    MaxKB = 256 }
    '.yaml' = @{ MinKB = 2;    MaxKB = 64 }
    '.msg'  = @{ MinKB = 16;   MaxKB = 1024 }
    '.vbs'  = @{ MinKB = 1;    MaxKB = 64 }
    '.ps1'  = @{ MinKB = 2;    MaxKB = 128 }
    '.psm1' = @{ MinKB = 2;    MaxKB = 128 }
    '.bat'  = @{ MinKB = 1;    MaxKB = 32 }
    '.cmd'  = @{ MinKB = 1;    MaxKB = 32 }
    '.ini'  = @{ MinKB = 1;    MaxKB = 16 }
    '.cfg'  = @{ MinKB = 1;    MaxKB = 64 }
    '.cs'   = @{ MinKB = 2;    MaxKB = 256 }
    '.js'   = @{ MinKB = 2;    MaxKB = 128 }
    '.ts'   = @{ MinKB = 2;    MaxKB = 128 }
    '.py'   = @{ MinKB = 2;    MaxKB = 256 }
    '.sh'   = @{ MinKB = 1;    MaxKB = 64 }
    '.java' = @{ MinKB = 2;    MaxKB = 256 }
    '.sql'  = @{ MinKB = 2;    MaxKB = 1024 }
    '.rtf'  = @{ MinKB = 4;    MaxKB = 256 }
    '.accdb'= @{ MinKB = 128;  MaxKB = 8192 }
    '.mdb'  = @{ MinKB = 128;  MaxKB = 4096 }
    '.exe'  = @{ MinKB = 500;  MaxKB = 204800 }
    '.msi'  = @{ MinKB = 1024; MaxKB = 102400 }
    '.dll'  = @{ MinKB = 64;   MaxKB = 10240 }
    '.bak'  = @{ MinKB = 1024; MaxKB = 2097152 }   # up to 2GB
    '.trn'  = @{ MinKB = 256;  MaxKB = 524288 }
    '.tmp'  = @{ MinKB = 1;    MaxKB = 10240 }
    '.dwg'  = @{ MinKB = 64;   MaxKB = 4096 }
    '.dxf'  = @{ MinKB = 16;   MaxKB = 2048 }
    '.vsd'  = @{ MinKB = 32;   MaxKB = 2048 }
    '.psd'  = @{ MinKB = 1024; MaxKB = 102400 }
    '.ai'   = @{ MinKB = 256;  MaxKB = 16384 }
    '.mp4'  = @{ MinKB = 5120; MaxKB = 512000 }
    '.html' = @{ MinKB = 1;    MaxKB = 256 }
  }

  # --- Magic-byte headers (as int arrays; cast to byte[] on use) ---------
  FileHeaders = @{
    '.pdf'   = @(37, 80, 68, 70, 45, 49, 46, 52, 13, 10)                # %PDF-1.4\r\n
    '.zip'   = @(80, 75, 3, 4)                                          # PK\x03\x04
    '.docx'  = @(80, 75, 3, 4)
    '.xlsx'  = @(80, 75, 3, 4)
    '.xlsm'  = @(80, 75, 3, 4)
    '.pptx'  = @(80, 75, 3, 4)
    '.7z'    = @(55, 122, 188, 175, 39, 28)
    '.rar'   = @(82, 97, 114, 33, 26, 7, 0)
    '.doc'   = @(208, 207, 17, 224, 161, 177, 26, 225)
    '.xls'   = @(208, 207, 17, 224, 161, 177, 26, 225)
    '.ppt'   = @(208, 207, 17, 224, 161, 177, 26, 225)
    '.msi'   = @(208, 207, 17, 224, 161, 177, 26, 225)
    '.msg'   = @(208, 207, 17, 224, 161, 177, 26, 225)
    '.jpg'   = @(255, 216, 255, 224)
    '.png'   = @(137, 80, 78, 71, 13, 10, 26, 10)
    '.gif'   = @(71, 73, 70, 56, 57, 97)                                # GIF89a
    '.bmp'   = @(66, 77)                                                # BM
    '.psd'   = @(56, 66, 80, 83)
    '.rtf'   = @(123, 92, 114, 116, 102, 49)                            # {\rtf1
    '.accdb' = @(0, 1, 0, 0, 83, 116, 97, 110, 100, 97, 114, 100)       # \x00\x01\x00\x00Standard
    '.mdb'   = @(0, 1, 0, 0, 83, 116, 97, 110, 100, 97, 114, 100)
    '.exe'   = @(77, 90)                                                # MZ
    '.dll'   = @(77, 90)
    # Text-based formats use plain-text stubs (see Write-FileMagic).
  }

  # --- Name templates per folder pattern (glob-style) --------------------
  NameTemplates = @{
    'HR/Employees/*'        = @(
      'W2_{year}.pdf','I9_{year}.pdf','Offer_Letter_{year}.pdf',
      'Benefits_Election_{year}.pdf','Performance_Review_{year}_Q{quarter}.docx',
      'Timesheet_{year}_{month}.xlsx','Background_Check.pdf','Promotion_Letter_{year}.pdf'
    )
    'Finance/AP/*'          = @(
      'Invoice_{Vendor}_{num}.pdf','PO_{num}.pdf','Payment_Approval_{num}.docx',
      'Vendor_Statement_{month}_{year}.xlsx','AP_Aging_{month}_{year}.xlsx'
    )
    'Finance/AR/*'          = @(
      'Invoice_{Customer}_{num}.pdf','{Customer}_Statement_{month}_{year}.pdf',
      'Aging_Report_{month}_{year}.xlsx','Credit_Memo_{num}.pdf','Collection_Notice_{num}.docx'
    )
    'Finance/Budget/*'      = @(
      'Budget_Q{quarter}_{year}.xlsx','Forecast_{year}.xlsx',
      'Variance_Analysis_{month}_{year}.pdf','Capex_Request_{Project}.docx',
      'OpEx_{year}.xlsx'
    )
    'Finance/Payroll/*'     = @(
      'Payroll_{month}_{year}.xlsx','Timesheet_Import_{month}.csv',
      'YTD_Summary_{year}.pdf','Tax_Withholding_{year}.pdf'
    )
    'Finance/Tax/*'         = @(
      'Tax_Return_{year}.pdf','1099_Summary_{year}.xlsx','State_Filing_{year}.pdf',
      'W2_Export_{year}.csv'
    )
    'Engineering/Source/*'  = @(
      '{module}.cs','{module}.ts','{module}.py','{module}.js',
      'config.yaml','README.md','api-spec.json','schema.sql'
    )
    'Engineering/Builds/*'  = @(
      'build-{date}-release.log','build-{date}-debug.log',
      'artifacts-{version}.zip','test-results-{date}.xml','coverage-{date}.xml'
    )
    'Engineering/Releases/*'= @(
      'release-{version}.zip','release-notes-{version}.md',
      'changelog-{version}.md','deploy-{version}.ps1'
    )
    'Engineering/Specs/*'   = @(
      'SRS_{Feature}_v{n}.docx','Design_{Feature}.pdf','API_Spec_{Product}.md',
      'ERD_{Feature}.vsd','Architecture_{Feature}.pptx'
    )
    'Sales/Clients/*'       = @(
      'Proposal_{Client}_{year}.docx','Contract_{Client}_signed.pdf',
      'SoW_{Project}.docx','MSA_{Client}.pdf','Quote_{Client}_{num}.xlsx',
      'Meeting_Notes_{date}.docx'
    )
    'Sales/Proposals/*'     = @(
      'Proposal_{Client}_{date}.docx','SoW_Template_v{n}.docx',
      'Pricing_{Product}_{year}.xlsx','ROI_Calculator.xlsx'
    )
    'Sales/Contracts/*'     = @(
      'Contract_{Client}_{year}.pdf','Amendment_{Client}_{year}.pdf',
      'NDA_{Client}.pdf','Renewal_{Client}_{year}.pdf'
    )
    'Sales/Pipeline/*'      = @(
      'Pipeline_{month}_{year}.xlsx','Forecast_Q{quarter}_{year}.xlsx',
      'Opportunity_{num}.docx'
    )
    'Legal/Contracts/*'     = @(
      'Contract_{Client}_{year}.pdf','NDA_{Client}_signed.pdf',
      'MSA_{Client}.docx','Amendment_{year}.pdf','Termination_Notice_{year}.pdf'
    )
    'Legal/Matters/*'       = @(
      'Pleading_{date}.pdf','Discovery_{Client}.pdf',
      'Brief_{Matter}.docx','Motion_{date}.pdf','Correspondence_{date}.pdf'
    )
    'Legal/IP/*'            = @(
      'Patent_Application_{num}.pdf','Trademark_{year}.pdf',
      'Prior_Art_Search_{num}.pdf','Claims_{num}.docx'
    )
    'IT/Logs/*'             = @(
      'application-{date}.log','security-{date}.log','iis-{date}.log',
      'sql-{date}.log','audit-{date}.log','error-{date}.log'
    )
    'IT/Configs/*'          = @(
      '{Product}-production.cfg','{Product}-staging.cfg','web.config',
      'appsettings.json','service.ini','database.cfg'
    )
    'IT/Scripts/*'          = @(
      'Backup-{Product}.ps1','Deploy-{Product}.ps1','Cleanup-{target}.ps1',
      'Monitor-{Product}.ps1','Restart-{Product}.ps1','healthcheck.sh'
    )
    'IT/Backups/*'          = @(
      '{Product}-full-{date}.bak','{Product}-diff-{date}.bak',
      '{Product}-tlog-{date}.trn','{Product}_export_{date}.zip'
    )
    'IT/Installs/*'         = @(
      '{Product}_installer_v{n}.exe','setup_{Product}.msi',
      '{Product}-{version}.zip','readme.txt'
    )
    'IT/Credentials/*'      = @(
      'service_accounts.xlsx','api_keys.txt','ssl_certs_{year}.zip'
    )
    'Marketing/Campaigns/*' = @(
      'Brief_{Campaign}.docx','Assets_{Campaign}.zip','Report_{Campaign}.pdf',
      'Email_Template_{n}.html','Landing_Page_{Campaign}.html'
    )
    'Marketing/Brand/*'     = @(
      'Logo_{variant}.png','Brand_Guidelines_v{n}.pdf','Style_Guide.pdf',
      'Color_Palette.ai'
    )
    'Marketing/Assets/*'    = @(
      'Banner_{n}.png','Video_{Campaign}.mp4','Photo_{event}.jpg',
      'Graphic_{n}.psd','Illustration_{n}.ai'
    )
    'R&D/Research/*'        = @(
      'Study_{Topic}_{year}.pdf','Analysis_{Subject}.xlsx',
      'Literature_Review_{Topic}.docx','Whitepaper_{n}.pdf'
    )
    'R&D/Patents/*'         = @(
      'Patent_Application_{num}.pdf','Prior_Art_{num}.pdf',
      'Claims_{num}.docx','Disclosure_{year}.pdf'
    )
    'QA/TestResults/*'      = @(
      'TestRun_{date}.xml','BugReport_{num}.docx',
      'Regression_{version}.xlsx','Performance_{date}.csv'
    )
    'QA/TestPlans/*'        = @(
      'TestPlan_{Feature}.docx','TestCases_{Feature}.xlsx',
      'AcceptanceCriteria_{Feature}.md'
    )
    'Support/Tickets/*'     = @(
      'Ticket_{num}_{Customer}.txt','Escalation_{num}.docx',
      'Resolution_{num}.md'
    )
    'Support/KB/*'          = @(
      'KB_{num}_{Topic}.docx','How_To_{task}.md','Troubleshooting_{Product}.pdf'
    )
    'Support/Reports/*'     = @(
      'Weekly_Report_{date}.xlsx','SLA_Report_{month}_{year}.pdf',
      'Customer_Satisfaction_{month}.csv'
    )
    'Facilities/Blueprints/*' = @(
      'Floor_Plan_{Building}.dwg','Layout_{Room}.dxf','Architectural_{Building}.pdf'
    )
    'Facilities/Leases/*'   = @(
      'Lease_{Building}_{year}.pdf','Lease_Amendment_{year}.pdf'
    )
    'Procurement/RFPs/*'    = @(
      'RFP_{Product}_{year}.pdf','Response_{Vendor}.pdf',
      'Evaluation_{Product}.xlsx'
    )
    'Procurement/POs/*'     = @(
      'PO_{num}.pdf','Receipt_{num}.pdf','Goods_Received_{num}.xlsx'
    )
    'Logistics/Shipments/*' = @(
      'BOL_{num}.pdf','Manifest_{date}.csv','Tracking_{num}.xlsx'
    )
    'Training/Curriculum/*' = @(
      'Module_{n}_{Topic}.pptx','Workbook_{Topic}.docx','Quiz_{Topic}.xlsx'
    )
    'Training/Certificates/*' = @(
      'Certificate_{user}_{Topic}.pdf'
    )
    'Archive/*'             = @(
      '{Dept}_documents_{year}.zip','{Dept}_backup_{year}.bak',
      'archived_{Topic}_{year}.pdf','old_{Topic}_{year}.xlsx',
      'legacy_{Topic}.docx'
    )
    '*/Clients/*/Contracts/*'      = @('Contract_{Client}_{year}.pdf','MSA_{Client}.pdf','SoW_{Project}.docx','Renewal_{year}.pdf')
    '*/Clients/*/Proposals/*'      = @('Proposal_{Client}_{date}.docx','Pitch_{Client}.pptx','Quote_{num}.xlsx')
    '*/Clients/*/Invoices/*'       = @('Invoice_{Client}_{num}.pdf','Statement_{month}_{year}.pdf')
    '*/Clients/*/Correspondence/*' = @('Email_{date}.msg','Letter_{date}.docx','Meeting_Notes_{date}.docx')
    '*/Clients/*'                  = @('Account_Overview_{year}.docx','Plan_{year}.xlsx','Contact_Sheet.xlsx')
    '*/Matters/*/Pleadings/*'      = @('Pleading_{date}.pdf','Complaint.pdf','Answer_{date}.pdf','Motion_{date}.pdf')
    '*/Matters/*/Discovery/*'      = @('RequestFor_{Topic}.pdf','Response_{date}.pdf','Interrogatory_{num}.pdf','Deposition_{date}.pdf')
    '*/Matters/*/Briefs/*'         = @('Brief_{date}.docx','Memo_{Topic}.docx','Opposition_{date}.pdf')
    '*/Matters/*/Evidence/*'       = @('Exhibit_{num}.pdf','Evidence_{date}.pdf','Document_{num}.pdf')
    '*/Matters/*/Correspondence/*' = @('Email_{date}.msg','OpposingCounsel_{date}.pdf','CourtFiling_{date}.pdf')
    '*/Matters/*'                  = @('Matter_Summary.docx','Strategy_{year}.pdf','Billing_{month}_{year}.xlsx')
    '*/Vendors/*/Contracts/*'      = @('Contract_{Vendor}_{year}.pdf','MSA_{Vendor}.pdf','Amendment_{year}.pdf')
    '*/Vendors/*/POs/*'            = @('PO_{num}.pdf','PO_Amendment_{num}.pdf')
    '*/Vendors/*/Invoices/*'       = @('Invoice_{Vendor}_{num}.pdf','Credit_Memo_{num}.pdf')
    '*/Vendors/*/Statements/*'     = @('{Vendor}_Statement_{month}_{year}.xlsx','Reconciliation_{month}_{year}.xlsx')
    '*/Vendors/*'                  = @('Vendor_Profile.docx','Contact_Sheet.xlsx','Scorecard_{year}.xlsx')
    '*/Campaigns/*/Brief/*'        = @('Brief.docx','Audience_Spec.pdf','Budget.xlsx','Timeline.xlsx')
    '*/Campaigns/*/Assets/*'       = @('Banner_{n}.png','Video_Hero.mp4','Social_{n}.png','Ad_{n}.jpg')
    '*/Campaigns/*/Reports/*'      = @('Weekly_{date}.pdf','Final_Report.pdf','Metrics_{date}.xlsx')
    '*/Campaigns/*/Email/*'        = @('Email_Template_{n}.html','Subject_Tests.xlsx','SendList_{date}.csv')
    '*/Campaigns/*'                = @('Overview.docx','KPIs.xlsx','Retrospective.docx')
    '*/Apps/*/Logs/*'              = @('application-{date}.log','error-{date}.log','audit-{date}.log','trace-{date}.log')
    '*/Apps/*/Configs/*'           = @('production.config','staging.config','web.config','appsettings.json')
    '*/Apps/*/Releases/*'          = @('release-{version}.zip','changelog-{version}.md','deploy-{version}.ps1')
    '*/Apps/*'                     = @('README.md','ARCHITECTURE.pdf','OperationalRunbook.docx')
    'Temp/*'                = @(
      '~temp-{n}.tmp','tmp{hash}.tmp','~${name}.tmp','outfile_{n}.tmp',
      'cache_{n}.tmp'
    )
    'Projects/*'            = @(
      'Kickoff.pptx','Meeting_Notes_{date}.docx','Design_{Component}.pdf',
      'Status_{date}.xlsx','Requirements.docx','Timeline.xlsx',
      'Charter.docx','Retrospective.docx'
    )
    'Users/*'               = @(
      'notes.txt','todo.txt','My_Reports.xlsx','Personal_Expenses.xlsx',
      'resume.docx','Scan_{date}.pdf','Expenses_{year}.xlsx',
      'Meeting_Notes_{date}.docx','Reference_{Topic}.pdf'
    )
    'Sensitive/*'           = @(
      'Confidential_{Topic}.pdf','Restricted_{year}.docx','Private_{Topic}.xlsx'
    )
    'Board/*'               = @(
      'Board_Minutes_{date}.pdf','Board_Deck_{date}.pptx','Executive_Summary_{year}.pdf'
    )
    '_install_files/*'      = @(
      '{Product}_installer_v{n}.exe','setup_{Product}.msi',
      '{Product}-{version}.zip','readme.txt','license.txt'
    )
    'default'               = @(
      '{prefix}_{year}{ext}','{prefix}_v{n}{ext}','{prefix}_{num}{ext}'
    )
  }

  # --- Data pools for template substitution -----------------------------
  DataPools = @{
    Vendors = @(
      'Oracle','SAP','Workday','ADP','Salesforce','Microsoft','Adobe','AWS','Zoom',
      'Slack','Atlassian','ServiceNow','DocuSign','Okta','Zendesk','HubSpot',
      'Dropbox','Box','Cisco','VMware','IBM','Google','Dell','HP','Lenovo',
      'RedHat','NetSuite','Tableau','Splunk','Twilio'
    )
    Clients = @(
      'Acme Corp','Titan Industries','Summit Holdings','Apex Partners','Zenith Group',
      'Beacon Enterprises','Helix Systems','Cascade Logistics','Ridge Capital','Vortex Media',
      'Horizon Analytics','Keystone Services','Nova Pharma','Orbit Solutions','Pinnacle Retail',
      'Pacific Freight','Sierra Manufacturing','Granite Insurance','Liberty Finance',
      'Aurora Dynamics','Meridian Automotive','Sterling Properties','Atlas Shipping',
      'Phoenix Energy','Cypress Biotech','Delta Air','Everest Construction',
      'Frontier Telecom','Harbor Holdings','Keystone Foods',
      'Blackstone Capital','Redwood Partners','Sapphire Health','Obsidian Mining',
      'Quartz Analytics','Emerald Hospitality','Ruby Security','Jade Technologies',
      'Amber Networks','Onyx Software','Crimson Media','Indigo Research',
      'Azure Pharma','Cobalt Manufacturing','Magenta Retail','Teal Logistics',
      'Copper Industries','Iron Bridge Capital','Silver Creek Corp','Gold Standard LLC',
      'Platinum Services','Diamond Construction','Pearl Maritime','Coral Reef Partners',
      'Marble Holdings','Slate Partners','Flint Ventures','Ember Dynamics',
      'Ashen Biotech','Cinder Networks'
    )
    Projects = @(
      'Phoenix','Apollo','Titan','Olympus','Kraken','Orion','Andromeda','Perseus',
      'Helios','Artemis','Zeus','Hydra','Pegasus','Atlas','Hermes','Nova',
      'Vega','Polaris','Sirius','Gemini','Lyra','Magellan','Columbus',
      'Voyager','Pioneer','Endeavor','Discovery','Enterprise','Atlantis','Challenger',
      'Summit','Everest','Olympus-2024','Kraken-Refresh','Cerberus','Icarus',
      'Medusa','Minotaur','Prometheus','Charon'
    )
    Products = @(
      'CRM','ERP','HRIS','DMS','CMS','SCM','WMS','BI','ITSM','LMS',
      'EHR','POS','APM','SIEM','EDR','DLP','IAM','VPN','MFA','SSO'
    )
    Customers = @(
      'GlobalTech','MidMarket Inc','SmallBiz LLC','Enterprise Co','Regional Group',
      'Consolidated Services','North Star','South Bay','East Ridge','West End',
      'Central Systems','Metro Holdings','Urban Partners','Valley Enterprises',
      'Mountain View','Harbor Industries','Gateway Group','Pacific Holdings',
      'Atlantic Corp','Western Union Inc'
    )
    Matters = @(
      'Smith-v-Acme','ContractReview-2022','IP-Dispute-2023','Licensing-Agreement-2024',
      'MergerReview-Titan','AcquisitionDiligence-Apex','EmploymentClaim-2023',
      'TradeSecret-2023','PatentInfringement-Orion','ClassAction-Vortex',
      'Regulatory-Inquiry-2022','DataBreachResponse-2023','ShareholderSuit-2024',
      'SubpoenaResponse-Q3-2023','VendorDispute-Keystone','NDA-Violation-2024',
      'Trademark-Opposition-2023','SEC-Investigation-2022','AntitrustReview-Nova',
      'RealEstate-Acquisition-Austin','Insurance-Claim-2023','LaborBoard-Filing-2024',
      'PatentLitigation-Helix','CopyrightInfringement-2023','SoftwareLicense-Audit',
      'DivestitureReview-Sierra','IP-Assignment-2024','ExportControl-2023',
      'DueDiligence-CypressAcq','RegulatoryFine-2024'
    )
    Topics = @(
      'Security','Compliance','Infrastructure','Deployment','Migration',
      'Performance','Optimization','Architecture','Integration','Automation',
      'Monitoring','Backup','Recovery','Scaling','Reliability'
    )
    Apps = @(
      'CustomerPortal','BillingSystem','InvoiceEngine','OrderManagement',
      'WarehouseTrack','PayrollProcess','HRCore','BenefitsHub',
      'LearningPortal','KnowledgeBase','HelpDesk','AssetTracker',
      'FleetManagement','ExpenseReport','TravelBooking','FacilitiesMgr',
      'IncidentTracker','ChangeMgmt','BuildPipeline','DeployAgent'
    )
    Campaigns = @(
      'Spring-Launch-2024','Summer-Promo-2023','Fall-Retargeting','HolidayPush-2024',
      'Q1-Webinar-Series','ContentRefresh-2023','PartnerBoost-2024','BrandRelaunch',
      'CustomerWin-Back','LeadGen-Q2-2024','EnterprisePush-2023','SMB-Expansion',
      'PaidSocial-Refresh','SEO-Overhaul-2024','EmailNurture-2023','ProductLaunch-Atlas',
      'CompetitiveTakeout','ThoughtLeadership-Q3','RegionalExpansion-West',
      'Podcast-Sponsorship-2024','EventSeries-2023','InfluencerPilot','ABM-Top50',
      'WinBack-Enterprise','AnalystRelations-2024'
    )
  }

  # --- Folder tree shape ------------------------------------------------
  FolderTree = @{
    ArchiveYearRange = @{ Start = 2015; End = 2024 }
    # v4.1: per-year quarter subfolders under Archive to spread file density.
    ArchiveQuarters  = $true

    UserHomeDirs = @{
      DeptScoped    = $true
      RootScoped    = $true
      # v4.1: $null means "create a home dir for every real user in the dept"
      # (previously capped at 12). Dramatically expands folder count.
      DeptUserCount = $null
      # v4.1: fraction of real users that also get root-scoped home dir
      # (previously 0.4). 1.0 = all real users get both.
      RootFraction  = 1.0
    }

    MaxDepth        = 7
    CleanNamesOnly  = $true
    ProjectsPerDept = @{ Min = 2; Max = 4 }
    # v4.1: every project gets these subs (previously 33% chance each).
    ProjectSubs     = @('Planning','Execution','Review','Resources','Documentation')
    LegacyFolderChance = @{ DeptLevel = 0.30; SubDuplicate = 0.25 }
    CrossDeptFolders = @('Shared','Public','Inter-Department','Board','Vendors','__Archive','__OLD__','_install_files')

    # --- v4.1 dept-specific folder classes ---------------------------
    # Each entry drives per-dept folder generation. Set Enabled=$false to skip.
    ClientFolders = @{
      Enabled    = $true
      PerDept    = @{ Sales = @{ Min = 20; Max = 40 } }
      SubFolders = @('Contracts','Proposals','Invoices','Correspondence','Projects')
    }
    MatterFolders = @{
      Enabled    = $true
      PerDept    = @{ Legal = @{ Min = 15; Max = 25 } }
      SubFolders = @('Pleadings','Discovery','Briefs','Correspondence','Evidence')
    }
    VendorFolders = @{
      Enabled    = $true
      PerDept    = @{
        Procurement = @{ Min = 20; Max = 30 }
        Finance     = @{ Min = 10; Max = 20 }
      }
      SubFolders = @('Contracts','POs','Invoices','Statements')
    }
    CampaignFolders = @{
      Enabled    = $true
      PerDept    = @{ Marketing = @{ Min = 15; Max = 25 } }
      SubFolders = @('Brief','Assets','Reports','Email')
    }
    AppFolders = @{
      Enabled    = $true
      PerDept    = @{ IT = @{ Min = 12; Max = 20 } }
      SubFolders = @('Logs','Configs','Releases')
    }
  }

  # --- File generation --------------------------------------------------
  Files = @{
    DefaultCount       = 100000
    DefaultDatePreset  = 'RecentSkew'
    DefaultRecentBias  = 70
    FolderCoherence    = $true
    FolderEraWindowDays = 90
    ArchiveYearOverrides = $true
    ArchiveYearWindowDays = 180
    LegacyFossilRate   = 0.08
    # Heavy-tail; Ultra max capped at 100K so no NTFS directory hits the
    # 200K+ insert-slowdown zone. See spec decision #24 for rationale.
    HeavyTailDistribution = @(
      @{ Name='Empty'; Pct=1;  Min=0;     Max=0      }
      @{ Name='Small'; Pct=45; Min=1;     Max=50     }
      @{ Name='Med';   Pct=25; Min=51;    Max=500    }
      @{ Name='Large'; Pct=20; Min=501;   Max=5000   }
      @{ Name='Mega';  Pct=8;  Min=5001;  Max=50000  }
      @{ Name='Ultra'; Pct=1;  Min=50001; Max=100000 }
    )
    Attributes = @{
      ReadOnlyChance = 0.05
      HiddenChance   = 0.02
      AdsChance      = 0.15
    }
    Ownership = @{    # sums to 1.0
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

  # --- Timestamp model --------------------------------------------------
  TimestampModel = @{
    FileClasses = @(
      @{ Name='Active';            Pct=25; WriteGapMin=0;    WriteGapMax=30;   AccessGapMin=0;    AccessGapMax=14    }
      @{ Name='Reference';         Pct=15; WriteGapMin=0;    WriteGapMax=90;   AccessGapMin=0;    AccessGapMax=30    }
      @{ Name='WriteOnceReadMany'; Pct=10; WriteGapMin=0;    WriteGapMax=1;    AccessGapMin=0;    AccessGapMax=14    }
      @{ Name='WriteOnceNeverRead';Pct=15; WriteGapMin=0;    WriteGapMax=1;    AccessGapMin=0;    AccessGapMax=0     }
      @{ Name='Aging';             Pct=15; WriteGapMin=0;    WriteGapMax=180;  AccessGapMin=30;   AccessGapMax=365   }
      # Dormant: old file, written shortly after creation, never accessed since.
      # CT is pinned 3-5 years ago in New-DemoFile; WT ~= CT; AT ~= WT.
      @{ Name='Dormant';           Pct=15; WriteGapMin=0;    WriteGapMax=180;  AccessGapMin=0;    AccessGapMax=30    }
      @{ Name='LegacyArchive';     Pct=5;  WriteGapMin=0;    WriteGapMax=30;   AccessGapMin=0;    AccessGapMax=0     }
    )
    DormancyByFolderPattern = @{
      '*/Archive/*'      = 0.75
      '*/Users/*'        = 0.55
      '*/Projects/*'     = 0.50
      '*/Temp/*'         = 0.40
      '*/Sales/Pipeline/*' = 0.05
      '*/IT/Logs/*'      = 0.05
      'default'          = 0.20
    }
  }

  # --- Mess injection ---------------------------------------------------
  Mess = @{
    OrphanSidCount = 40
    AclPatterns = @(
      @{ Name='ProperAGDLP';  Pct=55 }
      @{ Name='LazyGlobalGG'; Pct=25 }
      @{ Name='OrphanSidAce'; Pct=10 }
      @{ Name='EveryoneRead'; Pct=5  }
      @{ Name='DenyAce';      Pct=5  }
    )
    AccidentalInheritanceBreakChance = 0.05
    ServiceAccounts = @(
      @{ Name='svc_backup';     Description='Backup service account';     PathPatterns=@('*Archive*','*Backups*') }
      @{ Name='svc_sql';        Description='SQL Server service';         PathPatterns=@('*IT*Backups*','*Finance*Archive*') }
      @{ Name='svc_web';        Description='Web app pool';               PathPatterns=@('*IT*Logs*','*IT*Apps*') }
      @{ Name='svc_monitor';    Description='System monitoring';          PathPatterns=@('*IT*Logs*','*Ops*') }
      @{ Name='svc_fileshare';  Description='File share service';         PathPatterns=@('*') }
      @{ Name='svc_print';      Description='Print spooler';              PathPatterns=@('*Facilities*','*IT*') }
      @{ Name='svc_sharepoint'; Description='SharePoint service';         PathPatterns=@('*Marketing*','*Sales*') }
      @{ Name='svc_scanner';    Description='Document scanner service';   PathPatterns=@('*Support*','*HR*') }
      @{ Name='svc_antivirus';  Description='Antivirus quarantine';       PathPatterns=@('*Temp*','*') }
      @{ Name='svc_sccm';       Description='SCCM deployment service';    PathPatterns=@('*IT*','*Ops*') }
    )
    TitlesByLevel = @{
      Exec   = @('VP','SVP','CTO','CIO','CFO','CMO','CHRO','Director')
      Senior = @('Senior Manager','Principal','Senior Analyst','Architect','Senior Lead')
      Mid    = @('Manager','Analyst','Consultant','Specialist','Lead','Developer')
      Junior = @('Associate','Coordinator','Assistant','Junior Analyst','Specialist I')
    }
    Offices = @('New York','San Francisco','Chicago','Austin','Seattle','Boston','Remote')
  }

  # --- Parallelism ------------------------------------------------------
  Parallel = @{
    ThrottleLimit = 0          # 0 = Environment.ProcessorCount * 2
    ManifestPath  = 'logs/manifest.jsonl'
    PlanPath      = 'logs/plan.jsonl'
  }

  # --- Scenarios --------------------------------------------------------
  Scenarios = @{
    Default = @{
      Description = 'Single 100K run with RecentSkew.'
      Runs = @(
        @{ MaxFiles = 100000; DatePreset = 'RecentSkew'; RecentBias = 30 }
      )
    }
    MessyLegacy = @{
      Description = 'Three layered runs: LegacyMess + YearSpread + RecentSkew.'
      Runs = @(
        @{ MaxFiles = 30000; DatePreset = 'LegacyMess' }
        @{ MaxFiles = 30000; DatePreset = 'YearSpread' }
        @{ MaxFiles = 40000; DatePreset = 'RecentSkew'; RecentBias = 30 }
      )
    }
    QuickSmoke = @{
      Description = 'Very small run for iteration.'
      Runs = @(
        @{ MaxFiles = 500; DatePreset = 'RecentSkew' }
      )
    }
  }
}
