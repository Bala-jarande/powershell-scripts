Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
Import-Module Sharegate
CLS

function IncrementalMigration($srcSite, $srcList, $dstSite, $dstList)
{
    
    Write-Host "Starting Migration for list" $srcSite "to" $dstSite -ForegroundColor Green
    $mypassword = ConvertTo-SecureString "P_y/]qjsZy4K.DQ[bt" -AsPlainText -Force
    $srcSite1 = Connect-Site -Url $srcSite -Username "INT\svc_crbspmigrate_p" -Password $mypassword
    Write-Host $srcList
    $srcList1 = Get-List -Site $srcSite1 -Name $srcList
    
    $mypassword = ConvertTo-SecureString "P_y/]qjsZy4K.DQ[bt" -AsPlainText -Force
    $dstSite1 = Connect-Site -Url $dstSite -Username "INT\svc_crbspmigrate_p" -Password $mypassword
    $dstList1 = Get-List -Site $dstSite1 -Name $dstList
    #Write-Host "Starting Migration for list" $srcList1 "to" $dstList1

     $copysettings = New-CopySettings -OnContentItemExists IncrementalUpdate
     $result = Copy-Content -SourceList $srcList1 -DestinationList $dstList1 -CopySettings $copysettings
     Export-Report -CopyResult $result -Path "C:\Users\MoteSh_ADM\Desktop\Eclipse Scripts\FinalMigrationDelta\Basic ShareGate\EclipseDM20121123.xlsx"

    }

#Extracting Data from CSV
$Contents = Import-Csv "MigrationSiteList.csv"
Foreach($row in $Contents)
{    
    
    $SourceURL = $row.SourceSite.Trim() 
    $TargetURL = $row.TargetSite.Trim() 
    $SourceList = $row.SourceList.Trim() 
    $TargetList = $row.TargetList.Trim()
    IncrementalMigration $SourceURL $SourceList $TargetURL $TargetList  
}