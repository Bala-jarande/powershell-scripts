Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS
# Global variables
$username = "int\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$siteCollectionUrl = "https://euteamsites.willistowerswatson.com/Sites/EclipseDM"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$global:totaldocumentsCheckedOut = 0
$global:totalNotScannedList = 0
[PSObject[]] $global:LastModifiedFiles = @()
[PSObject[]] $global:NotScannedList = @()
$CheckedOutFile = ""
$position = $null
$CompareDate = "2020-08-12"

$currentLocation = Get-Location
$ExcludeList = Import-CSV "ExcludedList.csv"

function GetLastModifiedBy($url)
{
       Write-Host "Connecting Source site: $url"   
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

       Write-Host "Source site connected" -ForegroundColor Green  

       $TargetSite = "https://euteamsites.willistowerswatson.com/Sites/EclipseDM" + $Year + $Month

       Write-Host "Connecting Target site: $TargetSite"   
       $TargetclientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($TargetSite)                 
       $TargetclientContext.Credentials = $credentials        
       $TargetoWebsite = $TargetclientContext.Web
       $TargetchildWebs = $TargetoWebsite.Webs    
       $TargetclientContext.Load($TargetoWebsite)
       $TargetclientContext.Load($TargetoWebsite.Lists)    
       $TargetclientContext.Load($TargetchildWebs)
       $TargetclientContext.ExecuteQuery()

       Write-Host "Target site connected" -ForegroundColor Green  
       
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
                $clientContext.ExecuteQuery()         
                Write-Host " - Scanning source document library: " $list.Title  -ForegroundColor Yellow   
                #Write-Host " - document library Count : " $list.ItemCount 
                # CAML query to find all checked out documents, recursive thru folders     
                #$caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType'/><Value Type='Integer'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query></View>"                                        
                $caml = "<View Scope='RecursiveAll'><Query><Where><And><Eq><FieldRef Name='FSObjType'/><Value Type='Integer'>0</Value></Eq><Geq><FieldRef Name='Modified' IncludeTimeValue=FALSE' /><Value Type='DateTime' IncludeTimeValue='FALSE'>" + $CompareDate + "</Value></Geq></And></Where></Query></View>"                                        
                #$caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType' /><Value Type='Lookup'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query><RowLimit Paged='TRUE'>1</RowLimit></View>"                                        
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
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Year" -Value $Year
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Month" -Value $Month
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Day" -Value $list.Title                                                 
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Total Item Count" -Value $list.ItemCount                    
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Error Message" -Value $_.Exception.Message
                    $global:NotScannedList = $global:NotScannedList + $ErrorFile   
                    $global:totalNotScannedList = $global:totalNotScannedList + 1         
                }    
                Write-Host " -- Library Name:" $list.Title " ---- " $documents.Count " document(s) found" -foregroundcolor green                     
                if ($items.Count -ge 0)
                {                                            
                        $ExcludedListVal = $false
                        $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
                        if(!$ExcludedListVal)
                        {   
                            #Get Target site
                            $TargetList = $list.Title 
                            $TargetItem = GetTargetItemCont $TargetclientContext $TargetList
                            $diffval = ""
                            if($documents.Count -eq $TargetItem)
                            {
                                $diffval = "Same"
                            }
                            else
                            {
                                $diffval = "Different"
                            }

                            $LastModifiedFile = New-Object -TypeName PSObject 
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Year" -Value $Year
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Month" -Value $Month
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Day" -Value $list.Title
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source Item Count" -Value $documents.Count
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Target Item Count" -Value $TargetItem
                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Result" -Value $diffval
                            $global:LastModifiedFiles = $global:LastModifiedFiles + $LastModifiedFile 
                                                                                                    
                        }                         
                        $items = $null                             
                     }
              }                              
       }            
}

function GetTargetItemCont($TargetclientContext, $TargetList)
{
           $list = $TargetclientContext.Web.Lists.GetByTitle($TargetList)    
           $TargetclientContext.Load($list)            
           $TargetclientContext.ExecuteQuery()

           $ExcludedListVal = $false
           $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
           if(!$ExcludedListVal)
           {
                if($list.BaseType -ne "DocumentLibrary"){
                        continue
                }
                $TargetclientContext.Load($list)
                $TargetclientContext.ExecuteQuery()         
                Write-Host " - Scanning target document library: " $list.Title  -ForegroundColor Yellow   
                #Write-Host " - document library Count : " $list.ItemCount 
                # CAML query to find all checked out documents, recursive thru folders     
                #$caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType'/><Value Type='Integer'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query></View>"                                        
                $caml = "<View Scope='RecursiveAll'><Query><Where><And><Eq><FieldRef Name='FSObjType'/><Value Type='Integer'>0</Value></Eq><Geq><FieldRef Name='Modified' IncludeTimeValue=FALSE' /><Value Type='DateTime' IncludeTimeValue='FALSE'>" + $CompareDate + "</Value></Geq></And></Where></Query></View>"                                        
                #$caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType' /><Value Type='Lookup'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query><RowLimit Paged='TRUE'>1</RowLimit></View>"                                        
                try
                {                                                    
                        $spquery = New-Object Microsoft.SharePoint.Client.CamlQuery 
                        $spquery.ViewXml = $caml                                                
                        $documents = $list.GetItems($spquery)         
                        $TargetclientContext.Load($documents)
                        $TargetclientContext.ExecuteQuery()                
                        $items = $documents                                             
           
                } 
                catch
                {
                    Write-Host $_.Exception.Message -foregroundcolor Red
                    $listTitle = $list.Title
                    write-host $list.Title      " Not Scanned" -foregroundcolor Red
                    $ErrorFile = New-Object -TypeName PSObject 
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Year" -Value $Year
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Month" -Value $Month
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Day" -Value $list.Title                                                 
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Total Item Count" -Value $list.ItemCount                    
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Error Message" -Value $_.Exception.Message
                    $global:NotScannedList = $global:NotScannedList + $ErrorFile   
                    $global:totalNotScannedList = $global:totalNotScannedList + 1         
                }    
                Write-Host " -- Library Name:" $list.Title " ---- " $documents.Count " document(s) found" -foregroundcolor green                     
                if ($items.Count -ge 0)
                {                                            
                        $ExcludedListVal = $false
                        $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
                        if(!$ExcludedListVal)
                        {                               
                            return $documents.Count                                            
                        }                         
                        $items = $null                             
                     }
              }                              
          
}

#Get Start Migration Time
$StartDate = Get-Date
Write-Host "Comparison Start Time: " $StartDate -ForegroundColor Yellow

$Contents = Import-Csv "SiteCollectionDetail.csv"
$siteCollectionUrl = ""

Foreach($row in $Contents)
{
     $siteCollectionUrl = $row.SourceSite.Trim();
     GetLastModifiedBy($siteCollectionUrl)
     $SiteSplit = $siteCollectionUrl.Split("/");
     $Length = $SiteSplit.length;
     $SiteID = $SiteSplit[$Length - 1]                                 
}

$ReportGenerationTime = $StartDate.Day.ToString() + $StartDate.Month.ToString() + $StartDate.Year.ToString() + $StartDate.Hour.ToString() + $StartDate.Second.ToString()
$FileName = "ModifiedByFileCount" + $ReportGenerationTime + " " + ".csv"
$FilePath = -join(".\OutPut\",$FileName)
$NotScannedFilePath = -join(".\OutPut\","NotScannedListReport.csv")   
$global:LastModifiedFiles| Export-Csv -Path $FilePath -NoTypeInformation #-Append #-Encoding UTF8   
$global:NotScannedList| Export-Csv -Path $NotScannedFilePath -NoTypeInformation   

$EndDate = Get-Date
Write-Host "Migration End Time: " $EndDate -ForegroundColor Green  

$Duration = NEW-TIMESPAN –Start $StartDate –End $EndDate
 
Write-Host "Total Duration  " $Duration.Hours ":" $Duration.Minutes ":" $Duration.Seconds -ForegroundColor Cyan 