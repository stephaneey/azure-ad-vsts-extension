[CmdletBinding()]
param()
# Disclaimer: this code is provide as is with no warranty of any kind. Use it at your own risks.
# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {    
    Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
    Initialize-Azure
    #Azure AD V2 cmdlets are required
    Install-Module -Name AzureADPreview -Force -Scope CurrentUser
    #collecting input parameters
    $appid=Get-VstsInput -Name vstsappclientid
    $secret=Get-VstsInput -Name vstsappsecret
    $account=Get-VstsInput -Name vstsaccount
    $tenant=Get-VstsInput -Name tenant
    $vault=Get-VstsInput -Name vault		
    #the next two lines enable the retrieval of an accessotken obtained via the VSTS app that is granted access to AAD.
    $body="resource=https%3A%2F%2Fgraph.windows.net&client_id=$appid&client_secret=$secret&grant_type=client_credentials"	
    $resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.microsoftonline.com/$tenant/oauth2/token" -Method POST -Body $body| ConvertFrom-Json
    #initiating a connection to AAD using the retrieved accesstoken.
    Connect-AzureAD -TenantId $tenant -AadAccessToken $resp.access_token -AccountId $account
    #checking which template is to be applied.
    $SelectedTemplate=Get-VstsInput -Name TemplateSelector
    if($SelectedTemplate -eq "NativeAndWebAPI")
    {
        $apps = Get-VstsInput -Name NativeAndWebAPI  |ConvertFrom-Json
    }
    if($SelectedTemplate -eq "WebAndWebAPI")
    {
        $apps = Get-VstsInput -Name WebAndWebAPI  |ConvertFrom-Json
    }
    if($SelectedTemplate -eq "NativeAndWebAndWebAPI")
    {
         $apps = Get-VstsInput -Name NativeAndWebAndWebAPI  |ConvertFrom-Json
    }
	if($SelectedTemplate -eq "APIWithRolesAndScopesAndWebClient")
	{
		$apps = Get-VstsInput -Name APIWithRolesAndScopesAndWebClient  |ConvertFrom-Json
	}
	if($SelectedTemplate -eq"JavascriptAndWebAPI")
	{
		$apps = Get-VstsInput -Name JavascriptAndWebAPI  |ConvertFrom-Json
	}
	if($SelectedTemplate -eq "APIWithRolesAndScopesAssignmentAndWebClient")
	{
		$apps = Get-VstsInput -Name APIWithRolesAndScopesAssignmentAndWebClient  |ConvertFrom-Json
	}
    #validating input
    if($apps -eq $null -or $apps.Count -eq 0)
    {
        throw "invalid template"
    }
    if($null -ne ($apps.applications |where {$_.IsPublicClient -eq $false -and $_.RequiredResourceAccess.Count -ge 0 -and ($_.KeyVaultAppSecretName -eq "" -or $_.KeyVaultAppSecretName -eq $null)}))
    {
        throw "Some non-native apps require access to resources and do not specify a keyvault secret name"
    } 
   
    if(($apps.applications |where{$_.GroupMembershipClaims -ne $null -and $_.GroupMembershipClaims -ne "" -and $_.GroupMembershipClaims -ne "SecurityGroup" -and $_.GroupMembershipClaims -ne "All"}) -ne $nulll)
    {
        throw "GroupMembershipClaims has a wrong value. Valid values are null, All or SecurityGroup"
    }

    if(($apps.applications |where{$_.GroupMembershipClaims -ne $null -and $_.GroupMembershipClaims -ne ""}) -ne $null -and 
    ($apps.applications |where{$_.Oauth2AllowImplicitFlow -eq $true -and $_.IsPublicClient -eq $false}) -ne $null)
    {
        write-warning "whatch out, you're using the implicit grant flow together with groupMembershipClaims which is by default limited to 5 groups max"
    }   

    #fetching apps from the template
    foreach($app in $apps.applications)
    {
        $GroupMembershipClaims = $null;
        if($app.GroupMembershipClaims -ne $null -and $app.GroupMembershipClaims -ne "")
        {           
            $GroupMembershipClaims = $app.GroupMembershipClaims
        }

        if($app.Oauth2AllowImplicitFlow)
        {
            $ImplicitFlow=$true;
        }
        else
        {
            $ImplicitFlow=$false;
        }        
        
        $TargetApp = Get-AzureADApplication -Filter "DisplayName eq '$($app.name)'"
         if(($app.overwrite -eq $false -and $TargetApp -eq $null) -or $app.overwrite -eq $true)
         {
             #in case we overwrite, we can simply remove the webapp before re-creating it
             if($app.overwrite -eq $true -and $TargetApp -ne $null)
             {
                Remove-AzureADApplication -ObjectId $TargetApp.ObjectId
             }
             [System.Collections.Generic.List[String]]$ReplyUrls = New-Object "System.Collections.Generic.List[String]"
             foreach($url in $app.ReplyUrls)
             {
                if($url -ne $null -and $url -ne "")
                {
                    $ReplyUrls.Add($url)
                }
                
             }
             
             [System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]]$accesses=New-Object "System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]"
             if(!$app.IsPublicClient)
             {
                if($ReplyUrls.Count -gt 0)
                {
                    $NewApp = New-AzureADApplication -DisplayName "$($app.name)" -IdentifierUris $app.IdentifierUri -ReplyUrls $ReplyUrls -Oauth2AllowImplicitFlow $ImplicitFlow -GroupMembershipClaims $GroupMembershipClaims
                }
                else
                {
                    $NewApp = New-AzureADApplication -DisplayName "$($app.name)" -IdentifierUris $app.IdentifierUri -Oauth2AllowImplicitFlow $ImplicitFlow -GroupMembershipClaims $GroupMembershipClaims
                }
                
                $AppServicePrincipal=New-AzureADServicePrincipal -AppId $NewApp.AppId
             }
             else{
                 if($ReplyUrls.Count -gt 0)
                 {
                    $NewApp = New-AzureADApplication -DisplayName "$($app.name)" -PublicClient $true -ReplyUrls $ReplyUrls -Oauth2AllowImplicitFlow $ImplicitFlow
                 }
                 else{
                    $NewApp = New-AzureADApplication -DisplayName "$($app.name)" -PublicClient $true -Oauth2AllowImplicitFlow $ImplicitFlow
                 }                
             }
             #if it's a web client or a webapi that needs access to other resources, then a passwordCredential is required
             if(!$app.IsPublicClient -and $app.RequiredResourceAccess.Length -gt 0)
             {				
                $secret=New-AzureADApplicationPasswordCredential -ObjectId $NewApp.ObjectId
				$ss = ConvertTo-SecureString -String $secret.Value -AsPlainText -Force
                $ss1 = ConvertTo-SecureString -String $NewApp.AppId -AsPlainText -Force
                $out1 = Set-AzureKeyVaultSecret -VaultName $vault -Name $app.KeyVaultAppSecretName -SecretValue $ss
                $out2 = Set-AzureKeyVaultSecret -VaultName $vault -Name $app.KeyVaultAppIdName -SecretValue $ss1
				if($app.MSIEnabledRelatedWebAppName -ne $null -and $app.MSIEnabledRelatedWebAppName -ne "")
				{
					Write-Host "Trying to find MSI principal $($app.MSIEnabledRelatedWebAppName)"
					$principal = Get-AzureADServicePrincipal -Filter "DisplayName eq '$($app.MSIEnabledRelatedWebAppName)'"
					if($principal -ne $null)
					{           
						Write-Host "Found MSI principal"
						#in case several principals are returned (ie AAD APP having the same display name as a webapp)
						$TargetServicePrincipal=$principal|where {$_.alternativeNames -Match 'sites/'}
						Write-Host "Found Target MSI principal $($TargetServicePrincipal)"
						if($TargetServicePrincipal.Count -eq 1)
						{
							Set-AzureRmKeyVaultAccessPolicy -VaultName $vault -ObjectId $TargetServicePrincipal.ObjectId -PermissionsToSecrets get
                        
						}
						else
						{
							write-host "could not find any service principal for app $($app.name)"
						}    
					}
				}			
				
             }
			 
			 if(!$app.IsPublicClient -and $app.RequiredResourceAccess.Length -eq $null -and $app.KeyVaultAppIdName -ne $null -and $app.KeyVaultAppIdName -ne "")
			 {
				 $ss1 = ConvertTo-SecureString -String $NewApp.AppId -AsPlainText -Force
				 $out2 = Set-AzureKeyVaultSecret -VaultName $vault -Name $app.KeyVaultAppIdName -SecretValue $ss1
			 }
             
             $delegates = $NewApp.Oauth2Permissions
             foreach($delegate in $app.Oauth2Permissions)
             {  
                $oauth2Permission = New-Object Microsoft.Open.AzureAD.Model.Oauth2Permission
                $oauth2Permission.Id = new-guid                
                $oauth2Permission.Type="User"
                $oauth2Permission.UserConsentDescription = $delegate.UserConsentDescription
                $oauth2Permission.UserConsentDisplayName = $delegate.UserConsentDisplayName
                $oauth2Permission.AdminConsentDescription=$oauth2Permission.UserConsentDescription
                $oauth2Permission.AdminConsentDisplayName=$oauth2Permission.UserConsentDisplayName
                $oauth2Permission.Id = new-guid
                $oauth2Permission.IsEnabled = $true                
                $oauth2Permission.Value=$delegate.Value                
                $delegates.Add($oauth2Permission)
             }

             if($delegates.Count -gt 0)
             {
                Set-AzureADApplication -ObjectId $NewApp.ObjectId -Oauth2Permissions $delegates
             }
         
             $roles = $NewApp.AppRoles
             foreach($role in $app.AppRoles)
             {  
                $appRole = New-Object Microsoft.Open.AzureAD.Model.AppRole
                $appRole.AllowedMemberTypes = New-Object System.Collections.Generic.List[string]
                $appRole.AllowedMemberTypes.Add("User")
                $appRole.AllowedMemberTypes.Add("Application")
                $appRole.DisplayName = $role.DisplayName                
                $appRole.Id = new-guid
                $appRole.IsEnabled = $true
                $appRole.Description=$role.Description
                $appRole.Value=$role.Value                
                $roles.Add($appRole)
             }

             if($roles.Count -gt 0)
             {
                Set-AzureADApplication -ObjectId $NewApp.ObjectId -AppRoles $roles
             }
			 # user/group assignment
			  if(!$app.IsPublicClient -and $app.UserAndGroupAssignment -ne $null -and $app.UserAndGroupAssignment -ne "")
			 {
					 foreach($UserGroupAssignment in $app.UserAndGroupAssignment)
					 {
						 $TargetAppResource = Get-AzureADServicePrincipal -Filter "appId eq '$($NewApp.AppId)'"
						 if($UserGroupAssignment.type -eq "Group")
						 {
							 $TargetAssignmentPrincipal = Get-AzureADGroup -Filter "DisplayName eq '$($UserGroupAssignment.name)'" | where-object {$_.SecurityEnabled}							 
						 }
                         else
                         {
                            $TargetAssignmentPrincipal = Get-AzureADUser -Filter "UserPrincipalName eq '$($UserGroupAssignment.name)'"
                         }
						 if($TargetAssignmentPrincipal.Count -eq 0 -or $TargetAssignmentPrincipal.Count -gt 1)
						 {
							 Write-Host "TargetPrincipal $($name) not found, skipping assignment"
						 }
						 else
						 {
							 if($UserGroupAssignment.AssignedRole -eq $null -or $UserGroupAssignment.AssignedRole -eq "")
							 {
								 $RoleId="00000000-0000-0000-0000-000000000000"
							 }
							 else
							 {
								 $role=$TargetAppResource.AppRoles | where-object {$_.Value -eq $UserGroupAssignment.AssignedRole}
								 if($role.Count -eq 1)
								 {
									 $RoleId=$role.Id
								 }
                                 else
                                 {
                                    write-host "role $($UserGroupAssignment.AssignedRole) not found, assigning default role"
                                    $RoleId="00000000-0000-0000-0000-000000000000"
                                 }

							 }
                             if($UserGroupAssignment.type -eq "Group")
                             {
                                New-AzureADGroupAppRoleAssignment -ObjectId $TargetAssignmentPrincipal.ObjectId -PrincipalId $TargetAssignmentPrincipal.ObjectId -Id $RoleId -ResourceId $TargetAppResource.ObjectId
                             }
                             else
                             {
                                New-AzureADUserAppRoleAssignment -ObjectId $TargetAssignmentPrincipal.ObjectId -PrincipalId $TargetAssignmentPrincipal.ObjectId -Id $RoleId -ResourceId $TargetAppResource.ObjectId
                             }
							 
						 }
						 
						 
					 }
		     }

             foreach($access in $app.RequiredResourceAccess)
             {
                if($access.resource -ne $null)
                {
                    write-host "trying to find resource $access.resource $($access.resource)"
                    $TargetResource = (Get-AzureADServicePrincipal  -Filter "ServicePrincipalNames eq '$($access.resource)'" )
                    if($TargetResource -ne $null)
                    {
                        $ResourceAccess = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]@{
                            ResourceAppId=$TargetResource[0].AppId ;ResourceAccess=@{}}
                        foreach($perm in $access.perms)
                        {
							if($perm.type -eq "Scope")
							{
								$PermAccess = $TargetResource[0].Oauth2Permissions | ? {$_.Value -eq "$($perm.name)"}
								if($PermAccess -ne $null)
								{
									write-host "Granting delegate permission $($perm.name) on resource $($access.resource)"
									$res=[Microsoft.Open.AzureAD.Model.ResourceAccess]@{Id = $PermAccess.Id ;Type = "Scope"}
								}
								else
								{
									throw "Delegate permission $($perm.name) not found for resource $($access.resource)"
								}
								
							}
							ElseIf($perm.type -eq "Role")
							{
								$PermAccess = $TargetResource[0].appRoles | ? {$_.Value -eq "$($perm.name)"}
								if($PermAccess -ne $null)
								{
									write-host "Granting application permission $($perm.name) on resource $($access.resource)"
									$res=[Microsoft.Open.AzureAD.Model.ResourceAccess]@{Id = $PermAccess.Id ;Type = "Role"}
								}
								else
								{
									throw "Application permission $($perm.name) not found for resource $($access.resource)"
								}								
							}
                            if($res -ne $null)
							{
								$ResourceAccess.ResourceAccess.Add($res);
							}
                            
                        }        
                        $accesses.Add($ResourceAccess)         
                    }
                    else
                    {
                        write-host "Resource $($access.resource) not found" -Verbose
                    }
                }
                
             }             
             Set-AzureADApplication -ObjectId $NewApp.ObjectId -RequiredResourceAccess $accesses -AppRoles $roles             
         }
         else
         {
            write-host "App $($app.name) already exists";
         }      
    }    
    
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}