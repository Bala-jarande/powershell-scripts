Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS

$username = "int\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$siteURL = ""
#$listName = ""
$Status = $true
#-----------------
#For Testing Purposes.....
#To change the indexing of modified column to non-indexed change the Status to $false...
#---------------------




$Contents = Import-Csv "IndexingSiteList.csv"
$siteCollectionUrl = ""
Foreach($row in $Contents)
{
    $siteURL = $row.Targeturl.Trim();
    #$listName = $row.ListName.Trim();
    #Function call
    
    $listName = @("01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28","29","30","31")
    For ($i=0; $i -lt 31; $i++) 
    {
    $listName[$i]
    function AddRemoveListIndex($siteUrl, $listName, $columnName, $indexToken)
            {
   
                $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteURL)
                $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)
                $ctx.Credentials = $credentials 

                $lists = $ctx.Web.Lists
                $list= $lists.GetByTitle($listName)
                $field = $list.Fields.GetByTitle($columnName)
                $ctx.Load($field)
                $ctx.ExecuteQuery()

                $x = $field.Indexed.ToString()
                if($x -eq "True")
                {
                    Write-Host $siteURl "--" $listName 
                    Write-Host "Modified Column Already Indexed" -ForegroundColor Cyan

                }
                Else
                {
                  Write-host "Update Index for list "$listName "of site " $siteURL  -ForegroundColor Yellow 

                  $field.Indexed = $indexToken
                  $field.Update()
                  $ctx.ExecuteQuery()
                  Write-host -ForegroundColor Green "Successfully updated the  Index to" $indexToken " for " $listName
                  $x = "TRUE"
                }

                #print to csv
               
                $SiteTitle = $siteURL.Substring(49,15)
                $Name = -join(".\Log\",$SiteTitle, "_Indexing.csv")  
                New-Object -TypeName PSCustomObject -Property @{              
                Indexed = $x
                List = $listName
                Site = $siteURL    
                          
                } | Export-Csv -Path $Name -NoTypeInformation -Append
    
                

         }
    AddRemoveListIndex $siteURL $listName[$i] "Modified" $Status
    
   
    }  
    	    
}

