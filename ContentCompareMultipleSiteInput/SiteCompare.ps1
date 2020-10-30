Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS

function CompareListsandItemCount($siteUrlSource, $siteUrlDestination)
{


                $ExcludeList = Import-CSV "ExcludedList.csv"

                [System.net.ServicePointManager]::SecurityProtocol=[System.net.SecurityProtocolType]::Tls12
                
                $userName13 = "INT\svc_crbspmigrate_p"
                $password13 = "P_y/]qjsZy4K.DQ[bt"
                $securePassword13 = ConvertTo-SecureString $password13 -AsPlainText -Force 
                $ctxSource = New-Object Microsoft.SharePoint.Client.ClientContext($sourceURl)  
                $Creds13 = New-Object System.Net.NetworkCredential($userName13, $securePassword13)
                $ctxSource.Credentials = $Creds13
                
                $ctxDestination = New-Object Microsoft.SharePoint.Client.ClientContext($DestinationURL)  
                $CredsDest = New-Object System.Net.NetworkCredential($userName13, $securePassword13)
                $ctxDestination.Credentials = $CredsDest
                     
                    $webSource = $ctxSource.Web  
                    $ctxSource.Load($webSource)
                    $listsSource = $webSource.Lists
                    $ctxSource.Load($listsSource)
                    $ctxSource.ExecuteQuery()
                
                    $webDestination = $ctxDestination.Web  
                
                    $listsDestination = $webDestination.Lists
                    $ctxDestination.Load($listsDestination)
                    $ctxDestination.ExecuteQuery()

                   
                        
                    Write-Host -ForegroundColor Yellow "The site URL is" $webSource.Title
                    Write-Host -ForegroundColor Yellow "The dest site URL is" $webDestination.Title
                    $tableListNames =@();
                
                    #output the list details
                    Foreach ($listSource in $listsSource)
                    {
                        
                   
                         $ExcludedListVal = $false
                         $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $listSource.Title}) | % Action  
                         if(!$ExcludedListVal)
                         {   
                            
                          
                             Write-Host -ForegroundColor Yellow "List name: " $listSource.Title;
                             $o = new-object psobject
                  
                             $o | Add-Member -MemberType noteproperty -Name "sListName" -value $listSource.Title;
                             $o | Add-Member -MemberType noteproperty -Name "sNo. of Items" -value $listSource.ItemCount;
                             
                             
                                 
                             $o | Add-Member -MemberType noteproperty -Name dListName -value NotSet;
                             $o | Add-Member -MemberType noteproperty -Name dItemsCount -value NotSet;
                             $o | Add-Member -MemberType noteproperty -Name Comparison -value NotSet;
                          
                
                    
                        Foreach ($listDestination in $listsDestination)
                        {

                            $ExcludedListVal = $false
                            $ExcludedListVal = $ExcludeList | Where({$_.ExcludedList -eq $listDestination.Title}) | % Action  
                            if(!$ExcludedListVal)
                             {
                             
                             
                    
                            if ($listSource.Title -eq $listDestination.Title)
                            {
                            Write-Host -ForegroundColor Green "List name: " $listDestination.Title;
                                $o.dListName = $listDestination.Title;
                                $o.dItemsCount = $listDestination.ItemCount;
                                if($listSource.ItemCount -eq $listDestination.ItemCount)
                                {
                                    $o.Comparison = "Properly Synced";
                                }
                                else
                                {
                                    $o.Comparison = "Difference";
                                }
                                
                                break;
                            }
                            }
                        }
                
                            
                        $tableListNames += $o;
                    }
                    }
                
                    return $tableListNames;
                    
                
}

#$output

$Contents = Import-Csv "sites.csv"
Foreach($row in $Contents)
{
    $sourceURl = $row.source.Trim();
    $DestinationURL = $row.target.Trim();
    #Function call

$SiteTitle = $DestinationURL.Substring(49,15)
$Name = -join(".\Log\",$SiteTitle, "_Compare.csv")

CompareListsandItemCount $sourceURl $DestinationURL | Export-CSV  $Name 

}




