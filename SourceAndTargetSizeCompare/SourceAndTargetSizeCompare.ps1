Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
CLS

$username = "int\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

$Contents = Import-Csv "SiteList.csv"
$siteCollectionUrl = ""
Foreach($row in $Contents)
{
    $siteURL = $row.Sourceurl.Trim();
    $TargetURL = $row.Targeturl.Trim();
   
    function AddRemoveListIndex($siteUrl, $TargetUrl)
            {
                Write-Host "Comparing" $siteUrl "and" $TargetURL -ForegroundColor Cyan
   
                #Connecting Source site
                $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteUrl)
                $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)
                $ctx.Credentials = $credentials 
                $web1 = $ctx.Site
                $ctx.Load($web1)
                

               #Getting Source Storage Details
                $web1.Retrieve("Usage")
                $ctx.ExecuteQuery()
                $output = $web1.Usage.Storage

                #Connecting Target Site
                $ctx1 = New-Object Microsoft.SharePoint.Client.ClientContext($TargetUrl)
                $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)
                $ctx1.Credentials = $credentials 
                $web2 = $ctx1.Site
                $ctx1.Load($web2)
                

               #Get Target Storage Details
                $web2.Retrieve("Usage")
                $ctx1.ExecuteQuery()
                $outputTarget = $web2.Usage.Storage

               
                $SizeinMBSource = [System.Math]::Round((($output)/1MB),4)
                $SizeinMBTarget = [System.Math]::Round((($outputTarget)/1MB),4)
               

                $SizeinGBSource = [System.Math]::Round((($output)/1GB),4)
                $SizeinGBTarget = [System.Math]::Round((($outputTarget)/1GB),4)

               Write-Host "Size in MB Source" $SizeinMBSource -ForegroundColor Green
               Write-Host "Size in MB Target" $SizeinMBTarget -ForegroundColor Green
               Write-Host "Size in GB Source" $SizeinGBSource -ForegroundColor Green
               Write-Host "Size in GB Target" $SizeinGBTarget -ForegroundColor Green
               
               
                $Name = -join(".\Log\","SourceAndTargetSite_Collection_Size.csv")  
                New-Object -TypeName PSCustomObject -Property @{              
                SourceSite = $siteURL 
                TargetSite = $TargetURL 
                Size_In_MB_Source = $SizeinMBSource
                Size_In_MB_Target = $SizeinMBTarget
                Size_In_GB_Source = $SizeinGBSource
                Size_In_GB_Target = $SizeinGBTarget
                
               # Status = $Status
               # Size_In_GB = $SizeinGB  
                
                          
                } $Table | Select-Object "SourceSite", "TargetSite", "Size_In_MB_Source", "Size_In_MB_Target", "Size_In_GB_Source", "Size_In_GB_Target" | Export-Csv -Path $Name -NoTypeInformation -Append 
               }
               
    
                

        AddRemoveListIndex $siteURL $TargetURL
    

    }
      
  
   

