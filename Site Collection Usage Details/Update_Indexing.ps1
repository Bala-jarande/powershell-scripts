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
    $siteURL = $row.Targeturl.Trim();
    
   
    function AddRemoveListIndex($siteUrl)
            {
                Write-Host $siteUrl -ForegroundColor Cyan
   
                $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteUrL)
                $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)
                $ctx.Credentials = $credentials 
                $web1 = $ctx.Site
                $ctx.Load($web1)
                

               #Get Storage Details
                $web1.Retrieve("Usage")
                $ctx.ExecuteQuery()
                $output = $web1.Usage.Storage

               
                $SizeinMB = [System.Math]::Round((($output)/1MB),4)
                $SizeinGB = [System.Math]::Round((($output)/1GB),4)

               Write-Host "Size in MB" $SizeinMB -ForegroundColor Green
               Write-Host "Size in GB" $SizeinGB -ForegroundColor Green
               
                #print to csv
                $date = Get-Date -Format "dd/MM/yyyy HH:mm"
                $datestring = $date.ToString()
                $day = Get-Date -Format "dddd"
                $currentMonth = Get-Date -UFormat %m

                $currentMonth = (Get-Culture).DateTimeFormat.GetMonthName($currentMonth)
               
                $Name = -join(".\Log\",$day, $currentMonth,"Site_Collection_Size.csv")  
                New-Object -TypeName PSCustomObject -Property @{              
                Site = $siteURL  
                Size_In_MB = $SizeinMB
                Size_In_GB = $SizeinGB  
                Date = $date
                          
                } $Table | Select-Object "Site", "Size_In_MB", "Size_In_GB", "Date" | Export-Csv -Path $Name -NoTypeInformation -Append 
               }
               
    
                

        AddRemoveListIndex $siteURL 
    

    }
      
  
   

