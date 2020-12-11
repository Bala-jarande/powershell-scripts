Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS
# Global variables
$username = "int\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$global:totaldocumentsCheckedOut = 0
$global:totalNotScannedList = 0
[PSObject[]] $global:LastModifiedFiles = @()
[PSObject[]] $global:NotScannedList = @()
$CheckedOutFile = ""
$position = $null

$currentLocation = Get-Location
$ExcludeList = Import-CSV "ExcludedList.csv"

function GetLastModifiedBy($url)
{
       Write-Host "Connecting to site: $url"   
       $clientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($url)
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
       foreach($list in $oWebsite.Lists){
           $ExcludedListVal = $false
           $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
           if(!$ExcludedListVal)
           {
                if($list.BaseType -ne "DocumentLibrary"){
                        continue
                }
                $clientContext.Load($list)
                $clientContext.ExecuteQuery()         
                Write-Host " - Scanning document library: " $list.Title      
                Write-Host " - document library Count : " $list.Items.Count 
                # CAML query to find all checked out documents, recursive thru folders     
                #$caml = "<View Scope='RecursiveAll'><Query><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query><RowLimit Paged='TRUE'>1</RowLimit></View>"                                        
                $caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType' /><Value Type='Lookup'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query><RowLimit Paged='TRUE'>1</RowLimit></View>"                                        
                try
                {        
                                            
                        $spquery = New-Object Microsoft.SharePoint.Client.CamlQuery 
                        $spquery.ViewXml = $caml                                                
                        $documents = $list.GetItems($spquery)         
                        $clientContext.Load($documents)
                        $clientContext.ExecuteQuery()                
                        $items = $documents                        
           
                } 
                catch
                {
                    Write-Host $_.Exception.Message -foregroundcolor Red
                    $listTitle = $list.Title
                    write-host $list.Title      " Not Scanned" -foregroundcolor Red
                    $ErrorFile = New-Object -TypeName PSObject 
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Library Name" -Value $list.Title  
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "File Name" -Value "$listTitle Not Scanned"
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Document URL" -Value $($_.Exception.Message)
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Modified By (Login Name)" -Value ""  
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Modified By (Email ID)" -Value $CheckedOutByUser.Email          
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Modified Date" -Value ""
                    $global:NotScannedList = $global:NotScannedList + $ErrorFile   
                    $global:totalNotScannedList = $global:totalNotScannedList + 1         
                }                         
                if ($items.Count -gt 0)
                {                  
                        Write-Host " -- " $documents.Count " document(s) found" -foregroundcolor green  
                        $ExcludedListVal = $false
                        $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
                        if(!$ExcludedListVal)
                        {                 
                            foreach($document in $items)
                            {                   
                                $docItem = $list.GetItemById($document.Id)
                                $clientContext.Load($docItem)
                                $clientContext.Load($docItem.File)
                                $clientContext.ExecuteQuery()                               
                                $file = $docItem.File;
                                $clientContext.Load($file)
                                $clientContext.Load($file.ListItemAllFields)                      
                                $ModifiedBy=$file.ModifiedBy                    
                                $clientContext.Load($ModifiedBy)         
                                $clientContext.ExecuteQuery()
                                $LocalDate = $docItem.File.TimeLastModified
                                #$LocalDate = $LocalDate.AddHours(-5)                       
                                if($docItem.File -ne $null){               
                                        $LastModifiedFile = New-Object -TypeName PSObject 
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Library Name" -Value $list.Title  
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "File Name" -Value $docItem.File.Name
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Document URL" -Value ("http://docs.willis.com" + $docItem.File.ServerRelativeUrl)
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Modified By (Login Name)" -Value $ModifiedBy.LoginName
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Modified By (Email ID)" -Value $ModifiedBy.Email
                                        $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Modified Date" -Value $LocalDate
                                 }  
                                 $global:LastModifiedFiles = $global:LastModifiedFiles + $LastModifiedFile                                     
                                 Write-Host " --- "$docItem.File.ServerRelativeUrl                                                                      
                            }   
                        } 
                     $items = $null                             
                     }
              }                              
       }

    # Iterate all subsites
    foreach ($childWeb in $childWebs){
           $newpath = "http://docs.willis.com/" + $childWeb.ServerRelativeUrl           
           GetLastModifiedBy($newpath)
    }              
}




$Contents = Import-Csv "SiteCollectionDetail.csv"
$siteCollectionUrl = ""
Foreach($row in $Contents)
{
     $siteCollectionUrl = $row.SourceSite.Trim();
     GetLastModifiedBy($siteCollectionUrl)
     $SiteSplit = $siteCollectionUrl.Split("/");
     $Length = $SiteSplit.length;
     $SiteID = $SiteSplit[$Length - 1]   
     $FilePath = -join(".\LastUpdatedReport\",$SiteID, "_LastModifiedBy.csv")     
     $global:LastModifiedFiles| Export-Csv -Append -Path $FilePath -NoTypeInformation #-Append #-Encoding UTF8   
     #$global:LastModifiedFiles| Export-Csv -Path "LastModifiedBy_$SiteID.csv" -NoTypeInformation   
     $global:CheckedOutFiles = @()
     $global:NotScannedList = @()     
     $global:totalNotScannedList = 0
      
}
