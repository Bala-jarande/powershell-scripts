﻿#Refercne to client dll
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS

#Variables for Processing

#Start: Reading Source and Target value from configuration file
[string]$InputFile = "SiteURLs.xml"
if(!(Test-Path -Path $InputFile))
{
    Write-Host "Configuration file 'SiteUrls.xml' does not exist"
}
$currentLocation = Get-Location
  
$content = (Get-Content $InputFile)
[xml]$xmlInput = $content
$content = $content -replace ("localhost", $env:COMPUTERNAME)
$content = $content -replace ("{CURRENT_LOCATION}", $currentLocation.Path)

$xmlInput = $content
$SourceWebUrl = $xmlInput.Configuration.Siteurls.siteUrl.Source
$TargetWebUrl = $xmlInput.Configuration.Siteurls.siteUrl.Target
$ExcludedLists= $xmlInput.Configuration.ListsToExclude.List
$SourceIndex =  $SourceWebUrl.IndexOf('.com')
$SourceWebAppURL =  $SourceWebUrl.Substring(0,$SourceIndex + 4)
$TargetIndex =  $TargetWebUrl.IndexOf('.com')
$TargetWebAppURL =  $TargetWebUrl.Substring(0,$TargetIndex + 4)
$SiteTitleArray = ($xmlInput.Configuration.Siteurls.siteUrl.Target).split('/')
$SiteLength = $SiteTitleArray.Length
$SiteTitle = $SiteTitleArray[$SiteLength-1] 

#Start: Reading Source and Target value from configuration file

#Setup Credentials to connect with Target Site in SharePoint online
$userName13 = "INT\svc_crbspmigrate_p"
$password13 = "P_y/]qjsZy4K.DQ[bt"
$securePassword13 = ConvertTo-SecureString $password13 -AsPlainText -Force
$Credentials = New-Object System.Net.NetworkCredential($userName13, $securePassword13)
#Set up the context for source site
$Context = New-Object Microsoft.SharePoint.Client.ClientContext($SourceWebUrl)
$Context.Credentials = $Credentials
#Set up the context for target site
$TargetContext = New-Object Microsoft.SharePoint.Client.ClientContext($TargetWebUrl)
$TargetContext.Credentials = $Credentials

Write-host "============Connecting With Source Web and Target Web===================`n" -ForegroundColor Yellow
$SourceWeb = $Context.Web
$TargetWeb =$TargetContext.Web
#Array for Lists name and items count
[PSObject[]] $AllLists = @() 
[PSObject[]] $ListItems = @()
[PSObject[]] $MissingListItems = @() 
[PSObject[]] $global:ListItemCollection = @()
[PSObject[]] $global:ListItemCount = @()
[PSObject[]] $global:ErrorDetails = @()
  $position = $null
#Query to retrieve Files from Document Libraries
$qryFiles= '<View Scope="RecursiveAll"><Query><OrderBy><FieldRef Name="Modified" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'

#Query to retrieve items from Lists
$qryLists= '<View Scope="Recursive"><Query><OrderBy><FieldRef Name="ID" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'

#Query to retrieve Root Folder files
$qryRootFolder= '<View><Query><OrderBy><FieldRef Name="ID" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'

    Try
    {
        #Function to Get all lists from the web
        function Get-SPOList($Web,$WebURL)
        {
            #Get All Lists from the web
            $Lists = $Web.Lists
            $Context.Load($Lists)
            $Context.ExecuteQuery()

            #Get all lists from the web  
            ForEach($List in $Lists)
            {
             
             
              $Context.Load($List.RootFolder)
              $Context.ExecuteQuery()
              $ListURL= $List.RootFolder.ServerRelativeUrl                            
              #Adding Web URL, List Title and and Items count in array
              $AllList = New-Object -TypeName PSObject -Property @{
                                WebURL=$WebURL
                                ListTitle = $List.Title
                                ListURL=$ListURL
                                ItemCount= $List.ItemCount
                                ListBaseTemplate=$List.BaseType
                                Hidden=$List.Hidden
                                } | Select  WebURL,ListTitle,ListURL,ItemCount, ListBaseTemplate, Hidden
              $AllLists= $AllLists + $AllList                                         
            }
            return ,$AllLists
        }
        
        #Function to get all webs from given URL
        Function Get-SPOWeb($WebUrl, $WebAppURL)
        {
                 
                #Set up the context
                $Context = New-Object Microsoft.SharePoint.Client.ClientContext($WebUrl)                
                $Context.Credentials = $Credentials               
                $web = $context.Web
                $Context.Load($web)
                #Get all immediate subsites of the site
                $Context.Load($web.Webs) 
                $Context.executeQuery()
  
                #Call the function to Get Lists of the web
                Get-SPOList $web $WebAppURL
                
                #Write-host "All Lists and Libraries are retrived from:" $WebUrl  -ForegroundColor Green
                
                #Iterate through each subsite in the current web
                foreach ($SubWeb in $web.Webs)
                {
                    #Call the function recursively to process all subsites underneaththe current web
                    Write-host "Processing Web:" $WebUrl "for checking subistes" -ForegroundColor Yellow
                    Get-SPOWeb $SubWeb.URL
                }                
            }

        Function Get-ListItems([Microsoft.SharePoint.Client.ClientContext]$Context, [String]$ListTitle,[String]$qry, [String]$ListURL, [String]$WebURL)
        {
                $Context = New-Object Microsoft.SharePoint.Client.ClientContext($WebUrl)  
                $Context.Credentials = $Credentials                 
                $web = $context.Web
                $Context.Load($web)
                $Context.ExecuteQuery()
                $list = $Context.Web.Lists.GetByTitle($ListTitle)
                #Write-Host "Getting Items from List: " $ListTitle
                $Context.Load($list)
                #$Context.Load($items)
                $Context.ExecuteQuery()

                try
                {
                    #Set Query
                    Do{
                        $query = New-Object Microsoft.SharePoint.Client.CamlQuery
                        $query.ListItemCollectionPosition = $position
                        $query.ViewXml = $qry                        
                        $currentCollection = $list.GetItems($query)
                        $Context.Load($currentCollection)
                        $Context.ExecuteQuery()
                        ## Getting the position of the previous page
                        $position = $currentCollection.ListItemCollectionPosition

                        # Adding current collection to the allItems collection
                        $items += $currentCollection
                     } 
                    Until($position -eq $null) 

                    ForEach($item in $items)
                    {
                            
                            if($list.BaseType -ne "GenericList")
                            {
                                    
                                    if($item["FSObjType"] -eq "0")
                                    {
                                        #$Context.Load($item)                                        
                                        #$Context.ExecuteQuery()
                                        $ReplacePath = ""
                                        $SourceSiteURL = $item["FileRef"]
                                        $Keyword = $ListURL.ToLower()
                                        if(!$Keyword.contains("/sites/"))
                                        {
                                            $URLArr =  $ListURL.split("/")
                                            $Year = $URLArr[1]
                                            $Month = $URLArr[2]
                                            $SourceUpdatedURL = $Year + "/" + $Month
                                            $ReplacePath = "Sites/EclipseDM" + $Year + $Month
                                            $SourceSiteURL = $SourceSiteURL.replace($SourceUpdatedURL ,$ReplacePath)

                                        }
                                        Write-Host "File URL: " $item["ObjType"]
                                        $ListItem = New-Object -TypeName PSObject -Property @{
                                        itemID = $item["ID"]
                                        OriginalitemURL = $item["FileRef"]
                                        ComparisonItemURL = $SourceSiteURL
                                        listTitle=$ListTitle
                                        listURL=$ListURL
                                        EclipseId=$item["EclipseId"]
                                        EclipseType=$item["EclipseType"]
                                        Created=$item["Created"]
                                        Modified=$item["Modified"]
                                        CreatedBy=$item["Author"].LookupValue
                                        ModifiedBy=$item["Editor"].LookupValue
                                        ObjType = $item["ObjType"]
                                        Year = $Year
                                        Month = $Month
                                        } | Select  itemID,Year, Month, listTitle, OriginalitemURL, ComparisonItemURL, listURL, EclipseId, EclipseType, ObjType, Created, Modified, CreatedBy, ModifiedBy
                                        $ListItems=$ListItems + $ListItem
                                    }

                                }

                            else
                                {
                                    $ListItem = New-Object -TypeName PSObject -Property @{
                                        itemID = $item["ID"]
                                        itemURL = $item["Title"]
                                        listTitle=$ListTitle
                                        listURL=$ListURL
                                        EclipseId=""
                                        } | Select  itemID, itemURL, listTitle, listURL, EclipseId 
                                    $ListItems=$ListItems + $ListItem

                                }

                        }
                }
                catch
                {
                    write-host "Error: $($_.Exception.Message)" -foregroundcolor Red                 	    
                    $ErrorFile = New-Object -TypeName PSObject 
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "List Title" -Value $ListTitle
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "List URL" -Value $ListURL
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Library Status" -Value "Not Scanned"
                    $ErrorFile | Add-Member -MemberType NoteProperty -Name "Error Details" -Value $($_.Exception.Message)
                    $global:ErrorDetails  = $global:ErrorDetails  + $ErrorFile 
                }
                return ,$ListItems
        }

        Function Get-ListItemLargeList([Microsoft.SharePoint.Client.ClientContext]$Context, [String]$ListTitle,[String]$qry, [String]$ListURL, [String]$WebURL)
        {
            $Context = New-Object Microsoft.SharePoint.Client.ClientContext($WebUrl)  
            $Context.Credentials = $Credentials                 
            $web = $context.Web
            $Context.Load($web)
            $Context.ExecuteQuery()
            $list = $Context.Web.Lists.GetByTitle($ListTitle)    
            $Context.Load($list)            
            $Context.ExecuteQuery()
            Write-Host "Getting Items from List: " $ListTitle
            $folders =  $list.RootFolder.Folders
            $Context.Load($folders)
            $Context.ExecuteQuery() 
            $global:ListItemCollection = @()  

            try
            {
                #Get Root Folders Files
                $query = New-Object Microsoft.SharePoint.Client.CamlQuery
                $query.ViewXml = $qryFiles
                $currentCollection = $list.GetItems($query)
                $Context.Load($currentCollection)
                $Context.ExecuteQuery()

                foreach($RootFile in $currentCollection)
                {
                    #Write-Host "`t" $file.Name
                    if($folder.Name -ne "Forms")
                    {
                        if($list.BaseType -ne "GenericList")
                        {
                            $ComparisonURL = ""
                            if($ListTitle.ToLower() -notcontains "sites/eclipsedm")
                            {
                                $URLArr =  $ListURL.split("/")
                                $Year = $URLArr[1]
                                $Month = $URLArr[2]
                                $SourceUpdatedURL = $Year + "/" + $Month
                                $ComparisonURL = "Sites/EclipseDM" + $Year + $Month
                            }
                            $ListItem = New-Object -TypeName PSObject -Property @{
                             itemName = $file.Name
                             itemURL = $file.ServerRelativeUrl
                             listTitle=$ListTitle
                             listURL=$ListURL
                            } | Select  itemName, itemURL, listTitle, listURL 
                            $ListItems=$ListItems + $ListItem
                         }
                    }
                    $global:ListItemCollection = $global:ListItemCollection + $ListItems
                }

                <#foreach($folder in $folders)
                {
                     GetFiles $Context $folder
                }#>
                return $global:ListItemCollection
            }
            catch
            {
                write-host "Error: $($_.Exception.Message)" -foregroundcolor Red                 	    
                $ErrorFile = New-Object -TypeName PSObject 
                $ErrorFile | Add-Member -MemberType NoteProperty -Name "List Title" -Value $ListTitle
                $ErrorFile | Add-Member -MemberType NoteProperty -Name "List URL" -Value $ListURL
                $ErrorFile | Add-Member -MemberType NoteProperty -Name "Library Status" -Value "Not Scanned"
                $ErrorFile | Add-Member -MemberType NoteProperty -Name "Error Details" -Value $($_.Exception.Message)
                $global:ErrorDetails  = $global:ErrorDetails  + $ErrorFile 

            }
        }

        #Function to compare Source and Target Lists
        Function CompareSourceAndTarget([PSObject[]] $SLists, [PSObject[]] $TLists)
        {                         
            for($i=0; $i -lt $SLists.Items.Count; $i++)
            {
                     #Checking if Target Contains Source List
                     $SourceSiteURL = $SLists.ListURL[$i]
                     $URLArr =  $SourceSiteURL.split("/")
                     $Year = $URLArr[1]
                     $Month = $URLArr[2]
                     $SourceUpdatedURL = $Year + "/" + $Month                        
                     $TargetUpdatedURL = "Sites/EclipseDM" + $Year + $Month
                     #$TargetUpdatedURL = "Sites/EclipseDMTesting"
                     $SourceSiteURL = $SourceSiteURL.replace($SourceUpdatedURL ,$TargetUpdatedURL)
                     if($TLists.ListURL -contains $SourceSiteURL -and $ExcludedLists -notcontains $SLists.ListTitle[$i] -and $SLists.Hidden[$i] -eq $false)
                     {
                             for($j=0; $j -lt $TLists.Items.Count; $j++)
                             { 
                                        #If Source List and Target list are same
                                        if($TLists.ListTitle[$j] -eq $SLists.ListTitle[$i])
                                        {
                                                Write-Host "==============List:" $SLists.ListTitle[$i] " comparison is in Progress================"
                                                #Setting context for Target
                                                $TargetContext = New-Object Microsoft.SharePoint.Client.ClientContext($TLists.WebURL[$j])            
                                                $TargetContext.Credentials = $Credentials
                                                if($SLists.ListBaseTemplate[$i] -ne "GenericList")
                                                {
                                                       $SourceListItems = Get-ListItems -Context $Context -ListTitle $SLists.ListTitle[$i] -qry $qryFiles -ListURL $SLists.ListURL[$i] -WebURL $SLists.WebURL[$i]
                                                       $TargetListItems = Get-ListItems -Context $TargetContext -ListTitle $TLists.ListTitle[$j] -qry $qryFiles -ListURL $TLists.ListURL[$j] -WebURL $TLists.WebURL[$j]
                                                }
                                                else
                                                {
                                                        $SourceListItems = Get-ListItems -Context $Context -ListTitle $SLists.ListTitle[$i] -qry $qryLists -ListURL $SLists.ListURL[$i] -WebURL $SLists.WebURL[$i]
                                                        $TargetListItems = Get-ListItems -Context $TargetContext -ListTitle $TLists.ListTitle[$j] -qry $qryLists $TLists.ListURL[$j] -WebURL $TLists.WebURL[$j]
                                                }

                                                $diff = Compare-Object $SourceListItems $TargetListItems -Property ComparisonItemURL -PassThru 
                                                $diff | Add-Member -MemberType NoteProperty -Name "Description" -Value "" 
                                                [PSObject[]] $UpdatedArray = @() 
                                                foreach($DiffItem in $diff)
                                                {
                                                    if($DiffItem.SideIndicator -eq "<=")
                                                    {
                                                        $DiffItem.Description = "Add to Target"
                                                    }
                                                    elseif($DiffItem.SideIndicator -eq "=>")
                                                    {
                                                        $DiffItem.Description = "Delete from Target"
                                                    }
                                                    else
                                                    {
                                                        $DiffItem.Description = "Manual Check Required"
                                                    }
                                                    $UpdatedArray = $UpdatedArray + $DiffItem
                                                }
                                                $global:MissingListItems = $global:MissingListItems + $UpdatedArray                                            
                                                #Write-Host $diff | Format-Table
                                                #$AddToTarget = $diff | where SideIndicator -eq "<="
                                                #$DeletefromTarget = $diff | where SideIndicator -eq "=>"                                                                                                                   
                                                #Add Details Column                                                                                       
                                                #$MissingListItems = $MissingListItems + $diff
                                        }                                          
                                }
                        }
                }
                return ,$MissingListItems            
        }

        Function Get-ListCount([PSObject[]] $SLists, [PSObject[]] $TLists)        
        {
            foreach($SList in $SLists)
            {
                foreach($TList in $TLists)
                {
                    if($SList.ListTitle -eq $TList.ListTitle -and $ExcludedLists -notcontains $TList.ListTitle -and $SList.Hidden -eq $false)
                    {
                        $SourceListURL = $SourceWebAppURL + $SList.ListURL
                        $TargetListURL = $TargetWebAppURL + $TList.ListURL
                        $ItemStatus = ""
                        if($SList.ItemCount -eq $TList.ItemCount)
                        {
                            $ItemStatus = "Same"
                        }
                        else
                        {
                            $ItemStatus = "Difference"
                        }
                        $ListDetails = New-Object -TypeName PSObject -Property @{                                
                                SourceListURL= $SourceListURL
                                TargetListURL= $TargetListURL                                                               
                                SourceItemCount= $SList.ItemCount
                                TargetItemCount= $TList.ItemCount
                                ItemStatus= $ItemStatus
                                ListTitle = $SList.ListTitle                                
                                } | Select  SourceListURL,TargetListURL, ListTitle, SourceItemCount, TargetItemCount, ItemStatus
                        $global:ListItemCount = $global:ListItemCount + $ListDetails
                        break
                    }
                }
            }
        }

        Function GetFiles([Microsoft.SharePoint.Client.ClientContext]$Context, $folder)
        { 
            #Write-Host "Folder Name: "$folder.Name
            $Context.Load($folder.Files)
            $Context.ExecuteQuery() 
            foreach($file in $folder.Files)
            {
                #Write-Host "`t" $file.Name
                if($folder.Name -ne "Forms")
                {
                    if($list.BaseType -ne "GenericList")
                    {
                        $ListItem = New-Object -TypeName PSObject -Property @{
                         itemName = $file.Name
                         itemURL = $file.ServerRelativeUrl
                         listTitle=$ListTitle
                         listURL=$ListURL
                        } | Select  itemName, itemURL, listTitle, listURL 
                        $ListItems=$ListItems + $ListItem
                     }
                }
            }
            $global:ListItemCollection = $global:ListItemCollection + $ListItems
            # Use recursion to loop through all subfolders.
            foreach ($subFolder in $folder.SubFolders)
            {                
                GetFiles $Context $Subfolder 
            }            
        }

        #Get Start Migration Time
        $Date = Get-Date
        Write-Host "Comparison Start Time: " $Date -ForegroundColor Yellow

        #Call the function to get all sites
        Write-host "Retriving all Libraries from Site: "$SourceWebUrl -ForegroundColor Yellow
        $SLists= Get-SPOWeb $SourceWebUrl $SourceWebUrl
        Write-host "All Libraries are retrived from Site: "$SourceWebUrl  -ForegroundColor Green
        
        Write-host "Retriving all Libraries from Site: "$TargetWebUrl -ForegroundColor Yellow        
        $TLists= Get-SPOWeb $TargetWebUrl $TargetWebUrl
        Write-host "All Lists and Libraries are retrived from Site: "$TargetWebUrl  -ForegroundColor Green

        Write-host "============Getting Lists Item Count============" -ForegroundColor Yellow
        Get-ListCount  $SLists $TLists
        Write-host "============Lists Item Count retrived============" -ForegroundColor Green

        $ListItem = -join(".\Logs\",$SiteTitle, "_ListIemCount.csv")   
        $global:ListItemCount | Export-Csv -Path $ListItem -NoTypeInformation

        #Comparing Source and Target Listsand thire items
        $MissingListItems = CompareSourceAndTarget -SLists $SLists -TLists $TLists
        $FileName= -join(".\Logs\",$SiteTitle, "_MissingListItems.csv") 
        $ErrorFileName= -join(".\Logs\",$SiteTitle, "_ErrorDetails.csv")     
        $MissingListItems| Export-Csv -Path $FileName -NoTypeInformation
        $global:ErrorDetails | Export-Csv -Path $ErrorFileName -NoTypeInformation         
        $EndDate = Get-Date
        Write-Host "Migration End Time: " $EndDate -ForegroundColor Green   
   }
   catch 
   {
        write-host "Error: $($_.Exception.Message)" -foregroundcolor Red
   }
   finally
   {
        $AllLists = $null
        $ListItems = $null
        $MissingListItems=$null
        $SourceWeb = $null
        $TargetWeb =$null
        $Context =$null

   }
