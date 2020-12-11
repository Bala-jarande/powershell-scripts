Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"

$sourceURl="http://access.willis.com/site/willisargentinaops"
$DestinationURL="https://nasp.willistowerswatson.com/sites/willisargentinaops"

function CompareListsandItemCount($siteUrlSource, $siteUrlDestination)
{
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
        Write-Host -ForegroundColor Yellow "List name: " $listSource.Title;
        $o = new-object psobject
  
        $o | Add-Member -MemberType noteproperty -Name "sListName" -value $listSource.Title;
        $o | Add-Member -MemberType noteproperty -Name "sNo. of Items" -value $listSource.ItemCount;
        $o | Add-Member -MemberType noteproperty -Name "sLastItemModifiedDate" -value $listSource.LastItemUserModifiedDate;
            
        $o | Add-Member -MemberType noteproperty -Name dListName -value NotSet;
        $o | Add-Member -MemberType noteproperty -Name dItemsCount -value NotSet;
        $o | Add-Member -MemberType noteproperty -Name dLastItemModifiedDate -value NotSet;

    
        Foreach ($listDestination in $listsDestination)
        {
    
            if ($listSource.Title -eq $listDestination.Title)
            {
            Write-Host -ForegroundColor Green "List name: " $listDestination.Title;
                $o.dListName = $listDestination.Title;
                $o.dItemsCount = $listDestination.ItemCount;
                $o.dLastItemModifiedDate = $listDestination.LastItemUserModifiedDate;
                break;
            }
        }
                
        $tableListNames += $o;
    }

    return $tableListNames;
}

#$output =CompareListsandItemCount "http://nateamsites.willistowerswatson.com/sites/ComplianceVenezuela" "http://nateamsites.willistowerswatson.com/sites/ComplianceVenezuela" 
#$output
CompareListsandItemCount $sourceURl $DestinationURL | Export-CSV  C:\Users\jarandeba_adm\Desktop\willisargentinaops.csv

