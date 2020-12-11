#Refercne to client dll
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS

#Variables for Processing


#Start: Reading Source and Target value from configuration file

#Setup Credentials to connect with Target Site in SharePoint online
$userName13 = "INT\svc_crbspmigrate_p"
$password13 = "P_y/]qjsZy4K.DQ[bt"
$securePassword13 = ConvertTo-SecureString $password13 -AsPlainText -Force
$Credentials = New-Object System.Net.NetworkCredential($userName13, $securePassword13)
#Set up the context for source site
#$Context = New-Object Microsoft.SharePoint.Client.ClientContext($SourceWebUrl)
#$Context.Credentials = $Credentials
#Set up the context for target site
#$TargetContext = New-Object Microsoft.SharePoint.Client.ClientContext($TargetWebUrl)
#$TargetContext.Credentials = $Credentials

Write-host "============Connecting With Source Web and Target Web===================`n" -ForegroundColor Yellow
#$SourceWeb = $Context.Web
#$TargetWeb =$TargetContext.Web
#Array for Lists name and items count
[PSObject[]] $AllLists = @() 
[PSObject[]] $ListItems = @()
[PSObject[]] $global:MissingListItems = @() 
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
        function Get-SPOList($WebURL,$ListTitle)
        {
            $Context = New-Object Microsoft.SharePoint.Client.ClientContext($WebUrl)                
            $Context.Credentials = $Credentials               
            $web = $context.Web
            $Context.Load($web)            
            $Context.executeQuery()

            #Get All Lists from the web
            $List = $Web.Lists.GetByTitle($ListTitle)
            $Context.Load($List)
            $Context.ExecuteQuery()

                                 
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
                                                    
            
            return $AllList
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
            }

        Function Get-ListItems([String]$ListTitle,[String]$qry, [String]$ListURL, [String]$WebURL)
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
                                        $ListItem = New-Object -TypeName PSObject -Property @{
                                        itemID = $item["ID"]
                                        OriginalitemURL = $item["FileRef"]
                                        ComparisonItemURL = $SourceSiteURL
                                        listTitle=$ListTitle
                                        listURL=$ListURL
                                        } | Select  itemID, OriginalitemURL, ComparisonItemURL, listTitle, listURL
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
        Function CompareSourceAndTarget($SList, $TList)
        {                         
           # for($i=0; $i -lt $SList.Items.Count; $i++)
            #{
                     #Checking if Target Contains Source List
                     $SourceSiteURL = $SList.ListURL
                     $URLArr =  $SourceSiteURL.split("/")
                     $Year = $URLArr[1]
                     $Month = $URLArr[2]
                     $SourceUpdatedURL = $Year + "/" + $Month                        
                     $TargetUpdatedURL = "Sites/EclipseDM" + $Year + $Month
                     #$TargetUpdatedURL = "Sites/EclipseDMTesting"
                     $SourceSiteURL = $SourceSiteURL.replace($SourceUpdatedURL ,$TargetUpdatedURL)
                     if($TList.ListURL -contains $SourceSiteURL -and $SList.Hidden -eq $false)
                     {
                             #for($j=0; $j -lt $TLists.Items.Count; $j++)
                             #{ 
                                        #If Source List and Target list are same
                                        #if($TLists.ListTitle[$j] -eq $SLists.ListTitle[$i])
                                        #{
                                                Write-Host "==============List:" $SList.ListTitle " comparison is in Progress================"
                                                #Setting context for Target
                                                $TargetContext = New-Object Microsoft.SharePoint.Client.ClientContext($TList.WebURL)            
                                                $TargetContext.Credentials = $Credentials
                                                if($SList.ListBaseTemplate -ne "GenericList")
                                                {
                                                       $SourceListItems = Get-ListItems -ListTitle $SList.ListTitle -qry $qryFiles -ListURL $SList.ListURL -WebURL $SList.WebURL
                                                       $TargetListItems = Get-ListItems -ListTitle $TList.ListTitle -qry $qryFiles -ListURL $TList.ListURL -WebURL $TList.WebURL
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
                                        }                                          
                                #}
                        #}
                #}                          
        }

        Function Get-ListCount($SList, $TList)        
        {
                if($SList.ListTitle -eq $TList.ListTitle)
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

        $Contents = Import-Csv "Lists.csv"
        $siteCollectionUrl = ""

        #Get Start Migration Time
        $Date = Get-Date -Format "MMM-dd-yyyy HH:MM"
        Write-Host "Comparison Start Time: " $Date -ForegroundColor Yellow

        Foreach($row in $Contents)
        {
            $SourceWebUrl = $row.SourceSite.Trim();
            $ListTitle = $row.List.Trim();
            $SplitSite = $SourceWebUrl.split("/")
            $Year = $SplitSite[3]
            $Month = $SplitSite[4]
            $TargetWebUrl = "https://euteamsites.willistowerswatson.com/Sites/EclipseDM" + $Year + $Month
            
            #Call the function to get all sites
            Write-host "Retriving all Libraries from Site: "$SourceWebUrl -ForegroundColor Yellow
            $SList= Get-SPOList $SourceWebUrl $ListTitle
            Write-host "Source Library is retrived from Site: "$SourceWebUrl  -ForegroundColor Green
        
            Write-host "Retriving all Libraries from Site: "$TargetWebUrl -ForegroundColor Yellow        
            $TList= Get-SPOList $TargetWebUrl $ListTitle
            Write-host "Target Library is retrived from Site: "$TargetWebUrl  -ForegroundColor Green

            #Comparing Source and Target Listsand thire items
            CompareSourceAndTarget -SList $SList -TList $TList                                                    
        }

        $EndDate = Get-Date -Format "MMM-dd-yyyy HH:MM"       
        $FileName= -join(".\Logs\","MissingListItems(SelectedList).csv") 
        $ErrorFileName= -join(".\Logs\","ErrorDetails(SelectedList).csv")     
        $MissingListItems| Export-Csv -Path $FileName -NoTypeInformation
        $global:ErrorDetails | Export-Csv -Path $ErrorFileName -NoTypeInformation                 
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
