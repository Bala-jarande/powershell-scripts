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

$currentLocation = Get-Location
$ExcludeList = Import-CSV "ExcludedList.csv"

function GetLastModifiedBy($url, $Day, $row)
{
       Write-Host "Connecting to site: $url"   
       $clientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($url)
       $Year = $url.split("/")[3]
       $Month = $url.split("/")[4]
       # Credentials for on-premise environment
       $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)      
       $clientContext.Credentials = $credentials        
       $oWebsite = $clientContext.Web        
       $clientContext.Load($oWebsite)
       $clientContext.ExecuteQuery()

       #Get All Lists from the web
       $list = $oWebsite.Lists.GetByTitle($Day)
       $clientContext.Load($list)
       $clientContext.ExecuteQuery()
       
       # Iterate all document libraries
       #foreach($list in $oWebsite.Lists)
       #{
           $ExcludedListVal = $false
           $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
           if(!$ExcludedListVal)
           {
                if($list.BaseType -ne "DocumentLibrary"){
                        continue
                }
                $clientContext.Load($list)
                $clientContext.ExecuteQuery()         
                Write-Host " - Scanning document library: " $list.Title  -ForegroundColor Yellow   
                Write-Host " - document library Count : " $list.ItemCount 
                # CAML query to find all checked out documents, recursive thru folders     
                $SmallListcaml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType'/><Value Type='Integer'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query><RowLimit Paged='TRUE'>5000</RowLimit></View>"
                $caml= '<View Scope="RecursiveAll"><Query><OrderBy><FieldRef Name="Modified" Ascending="False" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'
                #$caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType'/><Value Type='Integer'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query></View>"                                        
                #$caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='FSObjType' /><Value Type='Lookup'>0</Value></Eq></Where><OrderBy><FieldRef Name='Modified' Ascending='False' /></OrderBy></Query><RowLimit Paged='TRUE'>1</RowLimit></View>"                                        
                $items = $null
                try
                {   if($list.ItemCount -lt 5000)
                    {                                                 
                        $spquery = New-Object Microsoft.SharePoint.Client.CamlQuery 
                        #$query.ListItemCollectionPosition = $position
                        $spquery.ViewXml = $SmallListcaml                                                
                        $documents = $list.GetItems($spquery)         
                        $clientContext.Load($documents)
                        $clientContext.ExecuteQuery()                
                        $items = $documents
                    }
                    else
                    {                        
                        #Set Query
                        Do{
                            $query = New-Object Microsoft.SharePoint.Client.CamlQuery
                            $query.ListItemCollectionPosition = $position
                            $query.ViewXml = $caml                        
                            $currentCollection = $list.GetItems($query)
                            $clientContext.Load($currentCollection)
                            $clientContext.ExecuteQuery()
                            ## Getting the position of the previous page
                            $position = $currentCollection.ListItemCollectionPosition

                            # Adding current collection to the allItems collection
                            $items += $currentCollection
                         } 
                         Until($position -eq $null)
                     }                      
           
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

                #$item = $items[0]
                                        
                if ($items.Count -gt 0)
                {                  
                        #Write-Host " -- " $documents.Count " document(s) found" -foregroundcolor green  
                        $ExcludedListVal = $false
                        $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $list.Title}) | % Action  
                        if(!$ExcludedListVal)
                        {      
                            #$document = $items[0]           
                            foreach($document in $items)
                            {      
                                if($document["FSObjType"] -eq 0)
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
                                    $LocalDate = $LocalDate.ToUniversalTime().ToString()                                    
                                    $EclipseId = $docItem["EclipseId"] 
                                    $IsModifiedSame =  "Different" 
                                    $IsCountSame = "Different"
                                    $IsEclipseIdSame = "Different"                  
                                    $SourceDate = Get-Date $row.'Modified Date'
                                    $TargetDate = Get-Date $LocalDate
                                    if($docItem.File -ne $null)
                                    { 
                                            if($SourceDate.ToString("dd/MM/yyyy")  -eq  $TargetDate.ToString("dd/MM/yyyy"))
                                            {
                                                $IsModifiedSame = "Same"
                                            }
                                            if($row.'Total Item Count' -eq $list.ItemCount)
                                            {
                                                $IsCountSame = "Same"
                                            }
                                            if($row.EclipseId -eq $EclipseId)
                                            {
                                                $IsEclipseIdSame =  "Same"
                                            }
                                            $LastModifiedFile = New-Object -TypeName PSObject 
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $row.'Site URL'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Year" -Value $row.Year
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Month" -Value $row.Month
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Day" -Value $row.Day  
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source File Name" -Value $row.'File Name'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Target File Name" -Value $docItem.File.Name 
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source EclipseId" -Value $row.EclipseId
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Target EclipseId" -Value $EclipseId
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source Document URL" -Value $row.'Document URL'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source Modified By (Login Name)" -Value $row.'Modified By (Login Name)'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source Modified By (Email ID)" -Value $row.'Modified By (Email ID)'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source Modified Date" -Value $row.'Modified Date'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Target Modified Date" -Value $LocalDate
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Source Total Item Count" -Value $row.'Total Item Count'
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Target Total Item Count" -Value $list.ItemCount
                                            #$LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
                                            #$LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Year" -Value $Year
                                            #$LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Month" -Value $Month
                                            #$LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Day" -Value $list.Title                                                                                 
                                            #$LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Document URL" -Value ("http://eclipsedm.willis.com" + $docItem.File.ServerRelativeUrl)
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Target Modified By (Login Name)" -Value $ModifiedBy.LoginName
                                            #$LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Modified By (Email ID)" -Value $ModifiedBy.Email                                                                                
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Same EclipseId" -Value $IsEclipseIdSame
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Same Modified Date" -Value $IsModifiedSame
                                            $LastModifiedFile | Add-Member -MemberType NoteProperty -Name "Same Item count" -Value $IsCountSame
                                     }  
                                     $global:LastModifiedFiles = $global:LastModifiedFiles + $LastModifiedFile                                     
                                     Write-Host " -- Last Modified document: "$docItem.File.ServerRelativeUrl "On " $LocalDate   -ForegroundColor Green
                                     if($IsEclipseIdSame -eq "Same")
                                     {
                                        Write-Host " -- EclipseID             :" $IsEclipseIdSame -ForegroundColor Cyan
                                     }
                                     else
                                     {
                                        Write-Host " -- EclipseID             :" $IsEclipseIdSame -ForegroundColor Red
                                     }
                                     if($IsModifiedSame -eq "Same")
                                     {
                                        Write-Host " -- Modified Date         :" $IsModifiedSame -ForegroundColor Cyan
                                     }
                                     else
                                     {
                                        Write-Host " -- Modified Date         :" $IsModifiedSame -ForegroundColor Red
                                     }
                                     if($IsCountSame -eq "Same")
                                     {
                                        Write-Host " -- ItemCount             :" $IsCountSame -ForegroundColor Cyan
                                     }
                                     else
                                     {
                                        Write-Host " -- ItemCount             :" $IsCountSame -ForegroundColor Red
                                     }                                     
                                     Write-Host "`n"
                                     break
                                 }                                                              
                            }   
                        } 
                        $items = $null                             
                     }
                
              }                              
       #}            
}

#Get Start Migration Time
$StartDate = Get-Date
Write-Host "Comparison Start Time: " $StartDate -ForegroundColor Yellow
$InputFilePath = -join(".\LastUpdatedReport\","LastModifiedBy.csv")
$Contents = Import-Csv $InputFilePath


Foreach($row in $Contents)
{
     $Year = $row.Year.Trim()
     $Month = $row.Month.Trim()
     $Day = $row.Day.Trim()
     
     $url = $siteCollectionUrl + $Year + $Month
     GetLastModifiedBy $url $Day $row
     $SiteSplit = $url.Split("/")
     $Length = $SiteSplit.length
     $SiteID = $SiteSplit[$Length - 1]                                 
}
$ReportGenerationTime = $StartDate.Day.ToString() + $StartDate.Month.ToString() + $StartDate.Year.ToString() + $StartDate.Hour.ToString() + $StartDate.Second.ToString()
$FileName = " LastModifiedBy" + $ReportGenerationTime + " " + ".csv"
$FilePath = -join(".\LastUpdatedReport\",$FileName)
$NotScannedFilePath = -join(".\LastUpdatedReport\","NotScannedListReport.csv")   
$global:LastModifiedFiles| Export-Csv -Path $FilePath -NoTypeInformation #-Append #-Encoding UTF8   
$global:NotScannedList| Export-Csv -Path $NotScannedFilePath -NoTypeInformation   

$EndDate = Get-Date
Write-Host "Migration End Time: " $EndDate -ForegroundColor Green  

$Duration = NEW-TIMESPAN –Start $StartDate –End $EndDate
 
Write-Host "Total Duration  " $Duration.Hours ":" $Duration.Minutes ":" $Duration.Seconds -ForegroundColor Cyan 