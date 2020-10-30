#Refercne to client dll
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
#$SourceWebApp= $xmlInput.Configuration.Siteurls.siteUrl.SourceWebApp
#$TargetWebApp= $xmlInput.Configuration.Siteurls.siteUrl.TargetWebApp
#$SourceManagePath= $xmlInput.Configuration.Siteurls.siteUrl.SourceManagePath
#$TargetManagePath = $xmlInput.Configuration.Siteurls.siteUrl.TargetManagePath

#$SourceManagePathURL = "/" + $SourceManagePath + "/"
#$TargetManagePathURL = "/" + $TargetManagePath + "/"

#Start: Reading Source and Target value from configuration file

#Setup Credentials to connect with Target Site in SharePoint online
Write-Host "=========Enter Credentials for Target Site to connect:============"
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

Write-host "============Connected With Source Web and Target Web==================="
$SourceWeb = $Context.Web
$TargetWeb =$TargetContext.Web
#Array for Lists name and items count
  [PSObject[]] $AllLists = @() 
  [PSObject[]] $ListItems = @()
  [PSObject[]] $MissingListItems = @() 
  $position = $null
#Query to retrieve Files from Document Libraries
$qryFiles= '<View Scope="RecursiveAll"><Query><OrderBy><FieldRef Name="ID" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'
#Query to retrieve items from Lists
$qryLists= '<View Scope="Recursive"><Query><OrderBy><FieldRef Name="ID" /></OrderBy></Query><RowLimit Paged="TRUE">5000</RowLimit></View>'
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
                
                Write-host "All Lists and Libraries are retrived from:"$web.URL  -ForegroundColor Green
                Write-host "Processing Web:"$web.URL "for checking subistes" -ForegroundColor Yellow
                #Iterate through each subsite in the current web
                foreach ($SubWeb in $web.Webs)
                {
                    #Call the function recursively to process all subsites underneaththe current web
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
    
                $Context.Load($list)
                #$Context.Load($items)
                $Context.ExecuteQuery()
                #Set Query
                 Do{
                    $query = New-Object Microsoft.SharePoint.Client.CamlQuery
                    $query.ViewXml = $qry

                    $query.ListItemCollectionPosition = $position

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
                                $ListItem = New-Object -TypeName PSObject -Property @{
                                    itemID = $item["ID"]
                                    itemURL = $item["FileRef"]
                                    listTitle=$ListTitle
                                    listURL=$ListURL
                                    } | Select  itemID, itemURL, listTitle, listURL
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
                                    } | Select  itemID, itemURL, listTitle, listURL 
                                $ListItems=$ListItems + $ListItem

                            }

                    }

                return ,$ListItems
             }
        #Function to compare Source and Target Lists
        Function CompareSourceAndTarget([PSObject[]] $SLists, [PSObject[]] $TLists)
            {
                $ExcludedLists= $xmlInput.Configuration.ListsToExclude.List
                
                for($i=0; $i -lt $SLists.Items.Count; $i++)
                    {
                        #Checking if Target Contains Source List
                        $SourceSiteURL = $SLists.ListURL[$i]
                        $URLArr =  $SourceSiteURL.split("/")
                        $Year = $URLArr[1]
                        $Month = $URLArr[2]
                        $SourceUpdatedURL = $Year + "/" + $Month
                        $TargetUpdatedURL = "Sites/EclipseDM" + $Year + $Month
                        $SourceSiteURL = $SourceSiteURL.replace($SourceUpdatedURL ,$TargetUpdatedURL)
                        if($TLists.ListURL -contains $SourceSiteURL -and $ExcludedLists -notcontains $SLists.ListTitle[$i] -and $SLists.Hidden[$i] -eq $false)
                            {
                                for($j=0; $j -lt $TLists.Items.Count; $j++)
                                     { 
                                        #If Source List and Target list are same
                                        if($TLists.ListTitle[$j] -eq $SLists.ListTitle[$i])
                                           {
                                                #If Source List Items not equal Target List
                                                if($TLists.ItemCount[$j] -ne $SLists.ItemCount[$i])
                                                    {

                                                        Write-Host "==============List:" $SLists.ListTitle[$i] "is migratrated but item count is different================"
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
                                                        
                                                        foreach($SourceListItem in $SourceListItems)
                                                        { 
                                                            #if some items are migrated in Target List
                                                            if($TargetListItems.itemURL.Count -gt "0")
                                                                {
                                                                    #If it is docuemnt library then comparing with FileURL/ItemURL
                                                                    $SListItemURL = $SourceListItem.itemURL
                                                                    if($SLists.ListBaseTemplate[$i] -ne "GenericList")
                                                                    {
                                                                         $SourceSiteURL = $SLists.ListURL[$i]
                                                                         $URLArr =  $SourceSiteURL.split("/")
                                                                         $Year = $URLArr[1]
                                                                         $Month = $URLArr[2]
                                                                         $SourceUpdatedURL = $Year + "/" + $Month
                                                                         $TargetUpdatedURL = "Sites/EclipseDM" + $Year + $Month
                                                                         $SourceSiteURL = $SourceSiteURL.replace($SourceUpdatedURL ,$TargetUpdatedURL)
                                                                    }
                                                                    if($TargetListItems.itemURL -notcontains $SListItemURL -and $SLists.ListBaseTemplate[$i] -ne "GenericList")
                                                                        {
                                                                            $MissingListItem = New-Object -TypeName PSObject -Property @{
                                                                                listTitle= $SourceListItem.listTitle
                                                                                listURL=$SourceListItem.listURL
                                                                                sourceListItemsCount=$SLists.ItemCount[$i]
                                                                                targetListItemsCount=$TLists.ItemCount[$j]
                                                                                itemID = $SourceListItem.itemID
                                                                                itemURL= $SourceListItem.itemURL
                                                                                } | Select  listTitle,listURL, sourceListItemsCount, targetListItemsCount, itemID, itemURL
                                                                            $MissingListItems=$MissingListItems + $MissingListItem
                                                                        }
                                                                        #if it is list then comparing with Item Id
                                                                 elseif($TargetListItems.itemID -notcontains $SourceListItem.itemID -and $SLists.ListBaseTemplate[$i] -eq "GenericList")
                                                                        {
                                                                         # Write-Host $SourceListItem.itemURL "exist in Target list"
                                                                            $MissingListItem = New-Object -TypeName PSObject -Property @{
                                                                                listTitle= $SourceListItem.listTitle
                                                                                listURL=$SourceListItem.listURL
                                                                                sourceListItemsCount=$SLists.ItemCount[$i]
                                                                                targetListItemsCount=$TLists.ItemCount[$j]
                                                                                itemID = $SourceListItem.itemID
                                                                                itemURL= $SourceListItem.itemURL
                                                                                } | Select  listTitle, listURL, sourceListItemsCount, targetListItemsCount, itemID, itemURL
                                                                            $MissingListItems=$MissingListItems + $MissingListItem
                                                                         }
                                                                else
                                                                        {
                                                                        }

                                                                }
                                                            else
                                                                {
                                                                #if no items are migrated  in Target list
                                                                $MissingListItem = New-Object -TypeName PSObject -Property @{
                                                                        listTitle= $SourceListItem.listTitle
                                                                        listURL=$SourceListItem.listURL
                                                                        sourceListItemsCount=$SLists.ItemCount[$i]
                                                                        targetListItemsCount=$TLists.ItemCount[$j]
                                                                        itemID = $SourceListItem.itemID
                                                                        itemURL= $SourceListItem.itemURL
                                                                        } | Select  listTitle, listURL, sourceListItemsCount, targetListItemsCount, itemID, itemURL
                                                                    $MissingListItems=$MissingListItems + $MissingListItem
                                                                }


                                                        }
        

                                                    }
                                                else
                                                    {
                                                       
                                                     Write-Host "=============" $SLists.ListTitle[$i]  "Migrated successfully with all items================" -ForegroundColor Green
                        

                                                    }


                                           }
    

                                     }

                            }
                       else
                       {
                       if($ExcludedLists -notcontains $SLists.ListTitle[$i] -and $SLists.Hidden[$i] -eq $false)
                       {
                        Write-Host $SLists.ListTitle[$i] + "not migrated" -ForegroundColor Yellow
                        $MissingListItem = New-Object -TypeName PSObject -Property @{
                                            listTitle= $SLists.ListTitle[$i]
                                            listURL=$SLists.ListURL[$i] 
                                            sourceListItemsCount=$SLists.ItemCount[$i]
                                            targetListItemsCount="0"
                                            itemID = "0"
                                            itemURL= $SLists.ListURL[$i]  +" :is not migrated"
                                            } | Select  listTitle, listURL, sourceListItemsCount, targetListItemsCount, itemID, itemURL
                        $MissingListItems=$MissingListItems + $MissingListItem
                        }

                       }

                    }
            return ,$MissingListItems
            
            }

        #Call the function to get all sites
        $SLists= Get-SPOWeb $SourceWebUrl $SourceWebUrl
        Write-host "All Lists and Libraries are retrived from Site and Subsites from:"$SourceWebUrl  -ForegroundColor Green
        
        $TLists= Get-SPOWeb $TargetWebUrl $TargetWebUrl
        Write-host "All Lists and Libraries are retrived from Site and Subsites from:"$TargetWebUrl  -ForegroundColor Green
        #Comparing Source and Target Listsand thire items
       $MissingListItems = CompareSourceAndTarget -SLists $SLists -TLists $TLists
       $FileName= -join($xmlInput.Configuration.Siteurls.siteUrl.SiteTitle, "_MissingListItems.csv")
      
       $MissingListItems| Export-Csv -Path $FileName -NoTypeInformation        
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
