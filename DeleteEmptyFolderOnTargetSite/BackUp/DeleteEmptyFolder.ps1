Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS
# Global variables
[PSObject[]] $AllLists = @() 
$username = "int\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
[PSObject[]] $global:MissingListItems = @()
$position = $null
$currentLocation = Get-Location
$ExcludeList = Import-CSV "ExcludedList.csv"
[PSObject[]] $SourceFolders = @() 
[PSObject[]] $TargetFolders = @() 

function GetFolder($url)
{       
       Write-Host "Connecting to site: $url"   
       $clientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($url)
       $Year = $url.split("/")[3]
       $Month = $url.split("/")[4]
       # Credentials for on-premise environment
       $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)      
       $clientContext.Credentials = $credentials        
       $oWebsite = $clientContext.Web
       $childWebs = $oWebsite.Webs    
       $clientContext.Load($oWebsite)
       $clientContext.Load($oWebsite.Lists)    
       $clientContext.Load($childWebs)
       $clientContext.ExecuteQuery()
       
       # Iterate all document libraries
       foreach($list in $oWebsite.Lists)
       {
           $ExcludedListVal = $false
           $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
           if(!$ExcludedListVal)
           {
                if($list.BaseType -ne "DocumentLibrary"){
                        continue
                }
                $clientContext.Load($list)
                $clientContext.Load($List.RootFolder)
                $Folders = $list.RootFolder.Folders
                $clientContext.Load($Folders)
                $clientContext.ExecuteQuery()
                        
                Write-Host " - Scanning document library: " $list.Title  -ForegroundColor Green   
                Write-Host " - document library Count : " $list.ItemCount  -ForegroundColor Cyan
                $ListURL= $List.RootFolder.ServerRelativeUrl

                foreach($SubFolder in $Folders)
                {
                    $clientContext.Load($SubFolder)
                    $clientContext.ExecuteQuery() 
                    if($SubFolder.Name -ne "Forms")
                    {
                        Write-Host "     - Scanning Root Folder: " $SubFolder.Name  -ForegroundColor Yellow
                    
                        $ComparisonURL = ""                        
                        $FinalURL = $SubFolder.ServerRelativeUrl
                        $TempURL =  "/sites/eclipsedm"
                        if(!$FinalURL.ToLower().Contains($TempURL.ToLower()))
                        {
                            $URLArr =  $SubFolder.ServerRelativeUrl.split("/")
                            $Year = $URLArr[1]
                            $Month = $URLArr[2]
                            $SourceUpdatedURL = $Year + "/" + $Month
                            $ComparisonURL = "Sites/EclipseDM" + $Year + $Month
                            $FinalURL =  $FinalURL.replace($SourceUpdatedURL ,$ComparisonURL)
                        } 
                                               
                        $AllList = New-Object -TypeName PSObject -Property @{
                                    WebURL=$url
                                    ListTitle = $list.Title
                                    FolderURL= $SubFolder.ServerRelativeUrl
                                    ComparisonItemURL= $FinalURL.ToLower()                               
                                    } | Select  WebURL,ListTitle,FolderURL,ComparisonItemURL
                        $AllLists= $AllLists + $AllList 
                    }
                }                                                                            
            }                            
       } 
       return ,$AllLists            
}

function GetTargetFolder($url)
{
       Write-Host "Connecting to site: $url"   
       $clientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($url)
     
       $YearMonth = $url.split("/")[4]
       # Credentials for on-premise environment
       $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)      
       $clientContext.Credentials = $credentials        
       $oWebsite = $clientContext.Web
       $childWebs = $oWebsite.Webs    
       $clientContext.Load($oWebsite)
       $clientContext.Load($oWebsite.Lists)    
       $clientContext.Load($childWebs)
       $clientContext.ExecuteQuery()


       for($i=1;$i -le 31;$i++)
       {
            $listTitle = ""
            if($i -lt 10)
            {
                $listTitle = "0" + $i
            }
            else
            {
                $listTitle = $i
            }
            Write-Host " - Scanning document library: " $listTitle  -ForegroundColor Green   
            for($j=0;$j -le 23;$j++)
            { 
                $FolderURL = "/Sites/" + $YearMonth + "/" + $listTitle
                if($j -lt 10)
                {
                    $FolderURL = $FolderURL + "/" + "0" + $j
                }
                else
                {
                    $FolderURL = $FolderURL + "/" + $j
                }  
                Write-Host "     - Scanning Root Folder: " $FolderURL  -ForegroundColor Yellow                              
                $AllList = New-Object -TypeName PSObject -Property @{
                                    WebURL=$url
                                    ListTitle = $listTitle
                                    FolderURL= $FolderURL
                                    ComparisonItemURL= $FolderURL.ToLower()                              
                                    } | Select  WebURL,ListTitle,FolderURL,ComparisonItemURL
                $AllLists= $AllLists + $AllList 
            }
       }       
       return ,$AllLists  
}

#Get Start Migration Time
$Date = Get-Date
Write-Host "Start Time: " $Date -ForegroundColor Yellow
$Contents = Import-Csv "SiteCollectionDetail.csv"
$siteCollectionUrl = ""

Foreach($row in $Contents)
{
     $SourceSiteCollectionUrl = $row.SourceSite.Trim()
     $TargetSiteCollectionUrl = $row.TargetSite.Trim()
     $SourceFolders = GetFolder($SourceSiteCollectionUrl)
     $TargetFolders = GetTargetFolder($TargetSiteCollectionUrl)

     if($TargetSiteCollectionUrl.Contains("https://euteamsites.willistowerswatson.com/Sites/EclipseDM"))
     {
         $clientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($TargetSiteCollectionUrl)              
         # Credentials for on-premise environment
         $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)      
         $clientContext.Credentials = $credentials        
         $oWebsite = $clientContext.Web
         $clientContext.ExecuteQuery()

         $diff = Compare-Object $SourceFolders $TargetFolders -Property ComparisonItemURL -PassThru
         $diff | Add-Member -MemberType NoteProperty -Name "Description" -Value ""
         #$TargetFolders | Add-Member -MemberType NoteProperty -Name "Description" -Value ""           
                                               
         [PSObject[]] $UpdatedArray = @() 
         foreach($DiffItem in $diff)
         {
             if($DiffItem.SideIndicator -eq "=>")
             {
                   try
                   {                                   
                        $Folder = $oWebsite.GetFolderByServerRelativeUrl($DiffItem.ComparisonItemURL)
                        $clientContext.Load($Folder)
                        $clientContext.ExecuteQuery()
                        $count = $Folder.ItemCount
                        Write-Host "--- " $DiffItem.ComparisonItemURL " folder Item Count:" $count  -ForegroundColor Green
                        if($count -eq 0)
                        {                                                
                            Write-Host "------- "$DiffItem.ComparisonItemURL " folder has been Removed."   -ForegroundColor Cyan
                            #$Folder.Recycle()
                            $DiffItem.Description = "Folder removed"
                            $UpdatedArray = $UpdatedArray + $DiffItem
                        }
                   }
                   catch
                   {
                        write-host "Folder Not found on Target" -foregroundcolor Red
                        $DiffItem.Description = "Folder Not found on Target"  
                   }
             }                      
         }
         $global:MissingListItems = $global:MissingListItems + $UpdatedArray
     }
     else
     {
         write-host "Wrong URL address" $TargetSiteCollectionUrl -foregroundcolor Red            
     }
                                                    
}
$MissingFolderFilePath = -join(".\DeletedFolderDetails\","DeletedFolderList.csv")     
$global:MissingListItems | Export-Csv -Path $MissingFolderFilePath -NoTypeInformation

$EndDate = Get-Date 
Write-Host "Migration End Time: " $EndDate -ForegroundColor Green 

     