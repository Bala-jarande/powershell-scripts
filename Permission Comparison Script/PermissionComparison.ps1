Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "c:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"
CLS

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
$SourceWebapp = $xmlInput.Configuration.Siteurls.siteUrl.SouceWebApp

#Credentials
$userName13 = "INT\svc_crbspmigrate_p"
$password13 = "P_y/]qjsZy4K.DQ[bt"
$securePassword13 = ConvertTo-SecureString $password13 -AsPlainText -Force

$userNameO365 = "INT\svc_crbspmigrate_p"
$passwordO365 = "P_y/]qjsZy4K.DQ[bt"
$securePasswordO365 = ConvertTo-SecureString $passwordO365 -AsPlainText -Force

#Array for missing user and group
[PSObject[]] $global:MissingPermission = @() 
$O365UserTitle=New-Object System.Collections.ArrayList

$SiteUserList13 = New-Object System.Collections.ArrayList
$SiteUserListO365 = New-Object System.Collections.ArrayList

function GetMissedGroupsAndUsers([Microsoft.SharePoint.Client.ClientContext]$ctx13,[Microsoft.SharePoint.Client.ClientContext]$ctx365 )
{
    $web13=$ctx13.Web
    $ctx13.Load($web13)    
    $spGroups13 = $web13.SiteGroups 
    #$SiteUsers13=$web13.SiteUsers 
    $ctx13.Load($web13)   
    $ctx13.Load($spGroups13)     
    #$ctx13.Load($SiteUsers13) 
    $ctx13.executeQuery()
    Write-Host "Source>> Groups Count-$($spGroups13.Count)"      
    #Write-Host "Source>> Site Users Count-$($SiteUsers13.Count)" 
    $SourceWebapp = $SourceWebapp +  $web13.ServerRelativeUrl
    $webO365=$ctx365.Web
    $spGroupsO365 = $webO365.SiteGroups   
    $SiteUsersO365=$webO365.SiteUsers 
    $ctx365.Load($webO365)
    $ctx365.Load($spGroupsO365) 
    $ctx365.Load($SiteUsersO365)     
    $ctx365.executeQuery()
    Write-Host "Target>> Groups Count-$($spGroupsO365.Count)" -ForegroundColor Green   
    #Write-Host "Target>> Site Users Count-$($SiteUsersO365.Count)" -ForegroundColor Green 
    #Checking Groups Migration   
    foreach($spGroup13 in $spGroups13){
        $checkGroup = CheckGroup -ctx $ctx365 -GroupName $spGroup13.Title
        if($checkGroup){
            $spGroup0365=$webO365.SiteGroups.GetByName($spGroup13.Title)
            $ctx365.Load($spGroup0365)
            $ctx365.ExecuteQuery()           
        }
        Else{
            $MissingPer = New-Object -TypeName PSObject 
            $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
            $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
            $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
            $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value  ""
            $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value  "" 
            $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value ""   
            $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Group Not Migrated"
            $global:MissingPermission = $global:MissingPermission + $MissingPer
        }
        
   }

    #Checking Users in Each Group
    foreach($spGroup13 in $spGroups13){ 
        $checkGroup = CheckGroup -ctx $ctx365 -GroupName $spGroup13.Title 
        if($checkGroup){          
            $spGroup0365=$webO365.SiteGroups.GetByName($spGroup13.Title)
            $spUsers365=$spGroup0365.Users
            $ctx365.Load($spGroup0365)
            $ctx365.Load($spUsers365)
            $ctx365.ExecuteQuery()
            Write-Host "Target>> Group Name-"$spGroup0365.Title "| User Count-"$spUsers365.Count -ForegroundColor Green       
            $O365UserTitle=New-Object System.Collections.ArrayList
            foreach($SPUser365 in $spUsers365){
                $ctx365.Load($SPUser365)
                $ctx365.ExecuteQuery()
                $O365UserTitle.Add($SPUser365.Title.ToLower())
            }
            if($spGroup0365 -ne $null)
            {   
                $users13=$spGroup13.Users
                $ctx13.Load($spGroup13)
                $ctx13.Load($users13)
                $ctx13.ExecuteQuery() 
                Write-Host "Source>> Group Name-" $spGroup13.Title "| User count-"$users13.Count           
                foreach($spUser13 in $users13)
                {                    
                    #$ctx13.Load($spUser13)
                    #$ctx13.ExecuteQuery()                    
                    if(![string]::IsNullOrEmpty($spUser13.Email))
                    {                        
                        $CheckUserInGroup=$true
                        if($CheckUserInGroup){
                            try
                            {    
                                $userO365=$spGroup0365.Users.GetByEmail($spUser13.Email)
                                $ctx365.Load($spGroup0365)
                                $ctx365.Load($userO365)
                                $ctx365.ExecuteQuery()
                                Write-Host "Group User Migrated"  $spUser13.LoginName-ForegroundColor Cyan  
                                                                   
                            }
                            catch
                            {                                                                    
                                $UserSplit = $($spUser13.LoginName).Split("\");
                                $Length = $UserSplit.length;
                                $spLogin = $UserSplit[$Length - 1]
                                $ADCheck=CheckUserInAD -UserLoginName $spLogin                                    
                                $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}                                               
                                if($ADCheck)
                                {
                                    try
                                    {
                                        $LoginName = "i:0#.w|" + $spUser13.LoginName
                                        $Allusers=$spGroup0365.Users
                                        $ctx365.Load($Allusers)
                                        $ctx365.ExecuteQuery()
                                        $userO365=$Allusers.GetByLoginName($LoginName)                                        
                                        $ctx365.Load($userO365)
                                        $ctx365.ExecuteQuery()
                                        Write-Host "Group User Migrated"  $spUser13.LoginName-ForegroundColor Cyan 
                                    }
                                    catch
                                    {
                                        Write-Host "Group User Not Migrated"  $spUser13.LoginName-ForegroundColor Red
                                        $MissingPer = New-Object -TypeName PSObject 
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                                        $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"   
                                        $global:MissingPermission = $global:MissingPermission + $MissingPer
                                    } 
                                }  
                                else
                                {
                                    $MissingPer = New-Object -TypeName PSObject 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                                    $global:MissingPermission = $global:MissingPermission + $MissingPer 
                                }                                                                
                            }
                        }
                        else
                        {
                            $UserSplit = $($spUser13.LoginName).Split("\");
                            $Length = $UserSplit.length;
                            $spLogin = $UserSplit[$Length - 1]
                            $ADCheck=CheckUserInAD -UserLoginName $spLogin
                            $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}
                            #$ADCheck = $true
                            if($ADCheck)
                            {
                                $MissingPer = New-Object -TypeName PSObject 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"   
                                $global:MissingPermission = $global:MissingPermission + $MissingPer 
                            }  
                            else
                            {
                                $MissingPer = New-Object -TypeName PSObject 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                                $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                                $global:MissingPermission = $global:MissingPermission + $MissingPer 
                            }                          
                        }
                    }                    
                    elseif((!$O365UserTitle.Contains($spUser13.Title.ToLower())) -and [string]::IsNullOrEmpty($spUser13.Email)){
                        $ADCheck=$true
                        $AdUser= ""
                        $flag = 0
                        $IsPresent = $true                      
                        if($spUser13.PrincipalType -eq "User"){
                            $UserSplit = $($spUser13.LoginName).Split("\");
                            $Length = $UserSplit.length;
                            $spLogin = $UserSplit[$Length - 1]
                            $ADCheck = $true
                            $ADCheck=CheckUserInAD -UserLoginName $spLogin
                            $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}
                            $flag = 1
                        }
                        elseif($spUser13.PrincipalType -eq "SecurityGroup")
                        {                            
                            $UserSplit = $($spUser13.Title).Split("\");
                            $Length = $UserSplit.length;
                            $spLogin = $UserSplit[$Length - 1]
                            Write-host $spLogin
                            $TargetGroupName = ""
                            $NotFoundGroup = $false                                                                                                                                         
                            $flag = 2
                        }

                        if($ADCheck)
                        {
                            if($flag -eq 1)
                            {
                                try
                                {    
                                     $accountname = "i:0#.w|"+ $spUser13.LoginName                                      
                                     $userO365=$spGroup0365.Users.GetByLoginName($accountname)
                                     $ctx365.Load($spGroup0365)
                                     $ctx365.Load($userO365)
                                     $ctx365.ExecuteQuery()
                                     Write-Host "Group ---> User Migrated...."  $spUser13.LoginName-ForegroundColor Cyan                                                                     
                                }
                                catch
                                {                                                                 
                                    $MissingPer = New-Object -TypeName PSObject 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"   
                                    $global:MissingPermission = $global:MissingPermission + $MissingPer 
                                }                                                      
                            }
                            else
                            {
                                    $MissingPer = New-Object -TypeName PSObject 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing AD Group User"   
                                    $global:MissingPermission = $global:MissingPermission + $MissingPer 
                            }                           
                        }
                        else
                        {
                             $MissingPer = New-Object -TypeName PSObject 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                             $global:MissingPermission = $global:MissingPermission + $MissingPer 
                        } 
                    }
                    else
                    {   
                        $ADCheck=$true
                        $AdUser= ""
                        $flag = 0
                        $IsPresent = $true
                        if($spUser13.PrincipalType -eq "User"){
                            $UserSplit = $($spUser13.LoginName).Split("\")
                            $Length = $UserSplit.length
                            $spLogin = $UserSplit[$Length - 1]
                            $ADCheck=CheckUserInAD -UserLoginName $spLogin 
                            $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}
                            $flag = 1
                            #$ADCheck = $true 
                        } 
                        elseif($spUser13.PrincipalType -eq "SecurityGroup")
                        {                            
                            $UserSplit = $($spUser13.Title).Split("\");
                            $Length = $UserSplit.length;
                            $spLogin = $UserSplit[$Length - 1]
                            Write-host $spLogin
                            $TargetGroupName = ""
                            $NotFoundGroup = $false                                                                                                                                         
                            $flag = 2
                        }
                         
                        if($ADCheck)
                        {
                            if($flag -eq 1)
                            {
                                try
                                {    
                                     $accountname = "i:0#.w|"+ $spUser13.LoginName                                      
                                     $userO365=$spGroup0365.Users.GetByLoginName($accountname)
                                     $ctx365.Load($spGroup0365)
                                     $ctx365.Load($userO365)
                                     $ctx365.ExecuteQuery()
                                     Write-Host "Group ---> User Migrated...."  $spUser13.LoginName-ForegroundColor Cyan                                                                     
                                }
                                catch
                                {                                                                 
                                    $MissingPer = New-Object -TypeName PSObject 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"   
                                    $global:MissingPermission = $global:MissingPermission + $MissingPer 
                                }                                                      
                            }
                            else
                            {
                                    $MissingPer = New-Object -TypeName PSObject 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing AD Group User"   
                                    $global:MissingPermission = $global:MissingPermission + $MissingPer 
                            }                           
                        }
                        else
                        {
                             $MissingPer = New-Object -TypeName PSObject 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                             $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                             $global:MissingPermission = $global:MissingPermission + $MissingPer 
                        }                       
                    }
                } 
            }
        }
    }

    $O365UserTitle=New-Object System.Collections.ArrayList
    foreach($SPSiteUser365 in $SiteUsersO365){
        $ctx365.Load($SPSiteUser365)
        $ctx365.ExecuteQuery()
        $O365UserTitle.Add($SPSiteUser365.Title.ToLower())
    }

    #Checking for Site Users  
    foreach($spSiteUser in $SiteUsers13){              
        $ctx13.Load($spSiteUser)
        $ctx13.ExecuteQuery()                          
        if(![string]::IsNullOrEmpty($spSiteUser.Email))
        {               
            $userO365=$webO365.SiteUsers.GetByEmail($spSiteUser.Email)                
            $ctx365.Load($userO365)
            try
            {
                $ctx365.ExecuteQuery()
                if($userO365 -ne $null)
                {  
                    Write-Host "Site User Migrated"  $spSiteUser.LoginName  -ForegroundColor Cyan                                    
                }                                     
            }
            catch
            {  
                $UserSplit = $($spSiteUser.LoginName).Split("\");
                $Length = $UserSplit.length;
                $spLogin = $UserSplit[$Length - 1]
                $ADCheck=CheckUserInAD -UserLoginName $spLogin 
                $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}
                #$ADCheck = $true                                                    
                $MissingPer = New-Object -TypeName PSObject
                if($ADCheck){ 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value "Site User" 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spLogin
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"         
                    $global:MissingPermission = $global:MissingPermission + $MissingPer
                }
                else
                {
                    $MissingPer = New-Object -TypeName PSObject 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spLogin
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                    $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                    $global:MissingPermission = $global:MissingPermission + $MissingPer 
                }
            }           
        }      
        elseif((!$O365UserTitle.Contains($spSiteUser.Title.ToLower())) -and [string]::IsNullOrEmpty($spSiteUser.Email)){
            $ADCheck=$true
            $AdUser = ""
            if($spSiteUser.PrincipalType -eq "User"){
                $UserSplit = $($spSiteUser.LoginName).Split("\");
                $Length = $UserSplit.length;
                $spLogin = $UserSplit[$Length - 1]
                #$ADCheck = $true
                $ADCheck=CheckUserInAD -UserLoginName $spLogin
                $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}
            }
            if($ADCheck){
                $MissingPer = New-Object -TypeName PSObject 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value "Site User"
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spSiteUser.LoginName 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"   
                $global:MissingPermission = $global:MissingPermission + $MissingPer 
            }
            else
            {
                $MissingPer = New-Object -TypeName PSObject 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                $global:MissingPermission = $global:MissingPermission + $MissingPer 
            }
        }
        else
        {   
            $ADCheck=$true
            $AdUser = ""
            if($spSiteUser.PrincipalType -eq "User"){
                $UserSplit = $($spSiteUser.LoginName).Split("\");
                $Length = $UserSplit.length;
                $spLogin = $UserSplit[$Length - 1]
                #$ADCheck = $true
                $ADCheck=CheckUserInAD -UserLoginName $spLogin
                $AdUser=Get-ADUser -Filter{SamAccountName -like $spLogin}
            }
            if($ADCheck -and (!$O365UserTitle.Contains($spSiteUser.Title.ToLower()))){                                                     
                $MissingPer = New-Object -TypeName PSObject 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $AdUser.Name 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spSiteUser.LoginName 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Missing User"         
                $global:MissingPermission = $global:MissingPermission + $MissingPer
            }
            else
            {
                $MissingPer = New-Object -TypeName PSObject 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Source Site URL" -Value $SourceWebapp
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Target Site URL" -Value $webO365.Url
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Group Name" -Value $spGroup13.Title 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Title" -Value $spUser13.Title 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Login Name" -Value $spUser13.LoginName 
                $MissingPer | Add-Member -MemberType NoteProperty -Name "User Email" -Value $AdUser.UserPrincipalName
                $MissingPer | Add-Member -MemberType NoteProperty -Name "Comments" -Value  "Invalid User"   
                $global:MissingPermission = $global:MissingPermission + $MissingPer 
            }
        }
    }        
}

function CheckGroup($ctx,$GroupName){
    $web=$ctx.Web
    $spGroup=$web.SiteGroups.GetByName($GroupName)    
    $ctx.Load($web)
    $ctx.Load($spGroup)    
    try{
        $ctx.ExecuteQuery()        
        Return $true
    }
    catch{
        return $false
    }
}
function CheckUserInGroup($ctx,$GroupName,$User){
    $web=$ctx.Web
    $spGroup=$web.SiteGroups.GetByName($GroupName)
    $userO365=$spGroup.Users.GetByEmail($User)
    $ctx.Load($web)
    $ctx.Load($spGroup)
    $ctx.Load($userO365)
    try{
        $ctx.ExecuteQuery()
        Return $true
    }
    catch{
        return $false
    }
}
function CheckUserInAD($UserLoginName,$UserEmail)
{
    $global:correctuserEmail = ""
    $AdUser=Get-ADUser -Filter{SamAccountName -like $UserLoginName}
    if($AdUser){
        $global:correctuserEmail = $AdUser.UserPrincipalName
        if($AdUser.Enabled -eq "True")
        {
            Return $true        
        }
        else
        {
            Return $false
        }
    }
    else
    {
        Return $false      
    }    
}
function GetSPWeb([string]$siteURL13,[string]$siteURLO365){
    Write-Host "Source>>"$siteURL13
    Write-Host "Target>>"$siteURLO365   -ForegroundColor Green

    $ctx13 = New-Object Microsoft.SharePoint.Client.ClientContext($siteURL13)  
    $Creds13 = New-Object System.Net.NetworkCredential($userName13, $securePassword13)
    $ctx13.Credentials = $Creds13
    $oWebsite = $ctx13.Web
    $childWebs = $oWebsite.Webs    
    $ctx13.Load($oWebsite)           
    $ctx13.Load($childWebs)
    $ctx13.ExecuteQuery()

    $ctxO365 = New-Object Microsoft.SharePoint.Client.ClientContext($siteURLO365)  
    $CredsO365 = New-Object System.Net.NetworkCredential($userNameO365,$securePasswordO365)
    $ctxO365.Credentials = $CredsO365  
    $webO365=$ctxO365.Web  
    $childWebs365 = $webO365.Webs   
    $ctxO365.Load($webO365) 
    $ctxO365.Load($childWebs365)
    $ctxO365.ExecuteQuery()

    GetMissedGroupsAndUsers -ctx13 $ctx13 -ctx365 $ctxO365

    # Iterate all subsites
    foreach ($childWeb in $childWebs)
    {
        $SourceChildpath = "http://connect.willis.com" + $childWeb.ServerRelativeUrl 
        $TargetChildpath = "https://euteamsites.willistowerswatson.com" + $childWeb.ServerRelativeUrl                  
        GetSPWeb -siteURL13 $SourceChildpath -siteURLO365 $TargetChildpath
    }   
}

$SiteSplit = $SourceWebUrl.Split("/");
$Length = $SiteSplit.length;
$SiteName = $SiteSplit[$Length - 1] 
GetSPWeb -siteURL13 $SourceWebUrl -siteURLO365 $TargetWebUrl
$global:MissingPermission| Export-Csv -Path "MissingGroupsAndUser_$SiteName.csv" -NoTypeInformation 
