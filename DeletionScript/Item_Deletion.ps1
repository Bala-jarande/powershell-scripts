Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\15\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS

#Global Variables
$username = "int\svc_crbspmigrate_p"
$password = "P_y/]qjsZy4K.DQ[bt"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

#Set parameter values
$siteURL=""
$FileRelativeURL=""

Function Remove-SPOFile()
{
  param
    (
        [Parameter(Mandatory=$true)] [string] $siteURL,
        [Parameter(Mandatory=$true)] [string] $FileRelativeURL
    )
    Try {
        #Get Credentials to connect
        $ctx = New-Object Microsoft.SharePoint.Client.ClientContext($siteURL)
        $credentials = New-Object System.Net.NetworkCredential($username, $securePassword)
        $ctx.Credentials = $credentials 
 
        #Get the file to delete
        $File = $ctx.Web.GetFileByServerRelativeUrl($FileRelativeURL)
        $ctx.Load($File)
        $ctx.ExecuteQuery()
                 
        #Delete the fil
        $File.Recycle()
        $ctx.ExecuteQuery()
 
        write-host -f Green "File has been deleted successfully!"
     }
    Catch {
        write-host -f Red "Error deleting file !" $_.Exception.Message
    }
}
 

$Contents = Import-Csv "DeletionSiteList.csv"
$siteCollectionUrl = ""
Foreach($row in $Contents)
{
    $siteURL = $row.SiteURL.Trim();
    $domain = "https://euteamsites.willistowerswatson.com"
    $finalURL = $domain + $siteURL
    $FileRelativeURL = $row.RelativeURL.Trim();
    Remove-SPOFile -SiteURL $finalURL -FileRelativeURL $FileRelativeURL
    	    
}





