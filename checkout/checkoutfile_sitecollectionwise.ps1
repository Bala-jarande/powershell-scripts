Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS
# Global variables
$username = "svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
#$siteCollectionUrl = "http://eclipsedm.willis.com/2012/11"
$global:totaldocumentsCheckedOut = 0
$global:totalNotScannedList = 0
[PSObject[]] $global:CheckedOutFiles = @()
[PSObject[]] $global:NotScannedList = @()
$CheckedOutFile = ""
$position = $null
      

function GetCheckedOutdocuments($url)
{
    Write-Host " Connecting to site:" $url	
	$clientContext = New-Object  Microsoft.SharePoint.Client.ClientContext($url)
	# Credentials for on-premise environment
	$credentials = New-Object System.Net.NetworkCredential($username, $securePassword)
	# Credentials for SharePoint Online
	#$credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($username, $securePassword)
	$clientContext.Credentials = $credentials 
	
	$oWebsite = $clientContext.Web
	$childWebs = $oWebsite.Webs    
	$clientContext.Load($oWebsite)
	$clientContext.Load($oWebsite.Lists)	
    $clientContext.Load($childWebs)
    $clientContext.ExecuteQuery()
	
	# Iterate all document libraries
	foreach($list in $oWebsite.Lists){
        if($list.BaseType -ne "DocumentLibrary"){
			continue
		}
        $clientContext.Load($list)
        $clientContext.ExecuteQuery()		 
		Write-Host " - Scanning document library: " $list.Title	    
        Write-Host " - document library Count : " $list.Items.Count 
		# CAML query to find all checked out documents, recursive thru folders	
        $caml = "<View Scope='RecursiveAll'><Query><Where><Geq><FieldRef Name='CheckoutUser' LookupId='TRUE'/><Value Type='int'>0</Value></Geq></Where><OrderBy><FieldRef Name='ID' /></OrderBy></Query><RowLimit Paged='TRUE'>15000</RowLimit></View>"				        
        #$caml= '<View Scope="RecursiveAll"><Query><OrderBy><FieldRef Name="ID" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'
        try
        {        
            Do
            {                                
                $spquery = New-Object Microsoft.SharePoint.Client.CamlQuery 
                $spquery.ViewXml = $caml   
                $spquery.ListItemCollectionPosition = $position    		        		
		        $documents = $list.GetItems($spquery)		
		        $clientContext.Load($documents)
		        $clientContext.ExecuteQuery()
                $position = $documents.ListItemCollectionPosition
                $items = $items + $documents            	 	
            }        
            Until($position -eq $null) 	
        } 
        catch
        {
            Write-Host $_.Exception.Message -foregroundcolor Red
            $listTitle = $list.Title
            write-host $list.Title	" Not Scanned" -foregroundcolor Red
            $ErrorFile = New-Object -TypeName PSObject 
            $ErrorFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
            $ErrorFile | Add-Member -MemberType NoteProperty -Name "File Name" -Value "$listTitle Not Scanned"
            $ErrorFile | Add-Member -MemberType NoteProperty -Name "Document URL" -Value $($_.Exception.Message)
            $ErrorFile | Add-Member -MemberType NoteProperty -Name "Checked Out By (Login Name)" -Value ""
            $ErrorFile | Add-Member -MemberType NoteProperty -Name "Checked Out By (Email ID)" -Value ""
            $ErrorFile | Add-Member -MemberType NoteProperty -Name "Modified Date" -Value ""
            $global:NotScannedList = $global:NotScannedList + $ErrorFile   
            $global:totalNotScannedList = $global:totalNotScannedList + 1         
        }               		 
        if ($items.Count -gt 0)
        {                  
			    Write-Host " -- " $documents.Count " checked out document(s) found" -foregroundcolor green				
			    foreach($document in $items)
                {                   
			        $docItem = $list.GetItemById($document.Id)
                    if ($docItem.File.CheckOutStatus -ne "None") 
                    {
                        if (($list.CheckedOutFiles | where {$_.ListItemId -eq $item.ID}) -ne $null) 
                        { 
                            continue
                        }                       
			            $clientContext.Load($docItem)
			            $clientContext.Load($docItem.File)
			            $clientContext.ExecuteQuery()            	            
                        $file = $docItem.File;
                        $clientContext.Load($file)
                        $clientContext.Load($file.ListItemAllFields)
                        $CheckedOutByUser=$file.CheckedOutByUser     
                        $ModifiedBy=$file.ModifiedBy
                        $clientContext.Load($CheckedOutByUser)
                        $clientContext.Load($ModifiedBy)         
                        $clientContext.ExecuteQuery()
                        $global:totaldocumentsCheckedOut = $global:totaldocumentsCheckedOut + 1
                        if($CheckedOutByUser.LoginName -ne $null){               
                            $CheckedOutFile = New-Object -TypeName PSObject 
                            $CheckedOutFile | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $url
                            $CheckedOutFile | Add-Member -MemberType NoteProperty -Name "File Name" -Value $docItem.File.Name
                            $CheckedOutFile | Add-Member -MemberType NoteProperty -Name "Document URL" -Value ("http://workspaces.fortum.com" + $docItem.File.ServerRelativeUrl)
                            $CheckedOutFile | Add-Member -MemberType NoteProperty -Name "Checked Out By (Login Name)" -Value $CheckedOutByUser.LoginName;
                            $CheckedOutFile | Add-Member -MemberType NoteProperty -Name "Checked Out By (Email ID)" -Value $CheckedOutByUser.Email;
                            $CheckedOutFile | Add-Member -MemberType NoteProperty -Name "Modified Date" -Value $docItem.File.TimeLastModified;
                        }  
                        $global:CheckedOutFiles = $global:CheckedOutFiles + $CheckedOutFile                                     
			            Write-Host " --- "$docItem.File.ServerRelativeUrl
                    }                          						  
		        }	
                $items = $null					
	        }                              
    }

    # Iterate all subsites
    foreach ($childWeb in $childWebs){
    $newpath = "http://workspaces.fortum.com" + $childWeb.ServerRelativeUrl           
           GetCheckedOutdocuments($newpath)
    }              
}



$Contents = Import-Csv "SiteCollectionDetail.csv"
$siteCollectionUrl = ""
Foreach($row in $Contents)
{
     $siteCollectionUrl = $row.SourceSite.Trim();
     GetCheckedOutdocuments($siteCollectionUrl)
     $SiteSplit = $siteCollectionUrl.Split("/");
     $Length = $SiteSplit.length;
     $SiteID = $SiteSplit[$Length - 1] 
     if ($global:totaldocumentsCheckedOut -gt 0)
     {   
        $global:CheckedOutFiles| Export-Csv -Append -Path "CheckedOutFiles_$SiteID.csv" -NoTypeInformation #-Append #-Encoding UTF8
     }
     if ($global:totalNotScannedList -gt 0)
     {
        $global:NotScannedList| Export-Csv -Append -Path "NotScanned_$SiteID.csv" -NoTypeInformation #-Append #-Encoding UTF
     } 
     $global:CheckedOutFiles = @()
     $global:NotScannedList = @()
     $global:totaldocumentsCheckedOut = 0
     $global:totalNotScannedList = 0
      
}
#GetCheckedOutdocuments($siteCollectionUrl)
#Write-Host $global:totaldocumentsCheckedIn " document(s) checked in" -foregroundcolor green