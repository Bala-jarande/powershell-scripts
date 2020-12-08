Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS
$WebAppURL = "http://connect2.willis.com"
$StartWeb = "http://connect2.willis.com/app/CRMANZ"
$userName = "INT\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force     
$Creds = New-Object System.Net.NetworkCredential($userName, $securePassword)
[PSObject[]] $global:SiteItemCount = @() 
$i = 0
function GetItemCount([Microsoft.SharePoint.Client.ClientContext]$ctx)
{    
    try
    {          
        $list = $ctx.web.Lists.GetByTitle("Documents")
        $SubSiteURL = $WebAppURL + $ctx.web.ServerRelativeUrl 
        $query = New-Object Microsoft.SharePoint.Client.CamlQuery
        $query.ViewXml = "<View Scope='Recursive' />"
        $items = $list.GetItems($query)
        $ctx.Load($list) 
        $ctx.Load($items) 
        $ctx.ExecuteQuery()
        Write-Host "ItemCount: " , ":" , $items.Count        
        $ItemCount = New-Object -TypeName PSObject 
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $SubSiteURL       
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Title" -Value $ctx.web.Title 
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Item Count" -Value $items.Count
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Last Modified Date" -Value $list.LastItemModifiedDate
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "List Exist"   
        $global:SiteItemCount = $global:SiteItemCount + $ItemCount
    }
    catch
    {
        $ItemCount = New-Object -TypeName PSObject 
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Site URL" -Value $SubSiteURL         
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Title" -Value $ctx.web.Title 
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Item Count" -Value $items.Count 
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Last Modified Date" -Value $list.LastItemModifiedDate  
        $ItemCount | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "List Not Exist"   
        $global:SiteItemCount = $global:SiteItemCount + $ItemCount
    }    
}
function GetSPWeb([string]$siteURL)
{
    Write-Host "Site URL >> "$siteURL  
    $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteURL)               
    $ctx.Credentials = $Creds
    $oWebsite = $ctx.Web
    $childWebs = $oWebsite.Webs    
    $ctx.Load($oWebsite)           
    $ctx.Load($childWebs)
    $ctx.ExecuteQuery()    
    GetItemCount $ctx

    # Iterate all subsites
    foreach ($childWeb in $childWebs)
    {
        if($i -lt 20000)
        {
            $SourceChildpath = $WebAppURL + $childWeb.ServerRelativeUrl                              
            GetSPWeb $SourceChildpath   
            $i = $i + 1
        }
        else
        {
            break
        }
             
    }   
}
GetSPWeb $StartWeb
$global:SiteItemCount| Export-Csv -Path "SitListItemCount.csv" -NoTypeInformation 