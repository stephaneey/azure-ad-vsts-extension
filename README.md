# azure-ad-vsts-extension
## Disclaimer

For the time being, the automated provisioning of AAD apps only targets B2E kind of apps. It is not tackling B2C nor B2B (multi-tenant) apps.

## The custom Visual Studio Team Services task in a nutshell
In a nutshell, this task was created to automatically provision Azure Active Directory Applications that allow business applications to authorize users and APIs using OAuth2/OpenID. Instead of doing this job manually for each and every business application, it is possible to automate most of these steps as part of the release. However, in order to remain compliant with most enterprise policies, the provisioned configuration remains under the control of the identity and access management team that has to provide the Admin Consent to deployed apps.

Admin Consent is mandatory for all apps that require application permissions

Admin Consent is optional in some cases but recommended for internal use. Indeed, consumer apps that are not consented by an admin, emit user-consent prompts which may be annoying in an internal context since all internal developped apps should be trusted by default. User consent might also be confusing for the end user.

## Capabilities of the custom Visual Studio Team Services task

* Deploy webapi type of Azure Active Directory Applications
* Deploy native client type of Azure Active Directory Applications
* Deploy custom APIs with custom application roles
* Deploy custom APIs with custom oauth2Permissions
* Enable the implicit grant flow
* Request GroupMembershipClaims
* Request both Delegate & Application permissions aka the RequiredResourceAccess
* Generate App Secrets and storing them into Azure Key Vault
* Enable Managed Service Identity (MSI) for the Service Principal Name (SPN) associated to a given web client

All these tasks are performed through an Azure Active Directory Application which is granted the Manage apps that this app creates or owns application permission exposed by the Azure Graph API, and via the Contributor RBAC permission over the Digital Key Vault. 
Of course, tasks will be performed according to the configuration you provide. A basic consistency check is done at run time to prevent typical errors. In case of configuration error, a corresponding exception will be thrown which will cause the task to fail and will stop the release. However, some checks might also generate warnings so it's always worthwhile to have a look at the logs. 
An example of warning could be: you request the GroupMembership to contains all the security groups of a given user while the consumer app requires the implicit grant flow (typical use inside of a web browser). However, in such situations, the token will never contain more than 5 groups (by design limitation), which might end up in an improper design choice since users often belong to more than 5 groups.

## Using the custom Visual Studio Team Services task
Prior to using the task, one must bind the release definition with the Variable Group VSTS. This group contains somme connection information ​to both AAD and Azure Key Vault.

In order to configure the AAD provisioning, one must look for the task named AAD App Provisioning and MSI Automation. The following parameters can/must be configured:

* Vault: defaults to $vault .  Contains the name of the Key Vault where to store the secrets
* VSTS app client id, app secret, tenant, vsts account : leave the defaults. These are used to connect to the target AAD using the permissions depicted earlier. All the values come from the Variable Group. In theory, you should not need to override them. If you deal with multiple tenants (sandbox, prod), then you'd better create another Variable Group then overriding the values at release definition level.
* AAD Starting Template: pick the template that's the closest to your target topology. The starting template is just to get started with configuration elements. You must update the default provided piece of JSON text with your own values. You'd better use a JSON editor to do so.
Typical scenarios

The 3 templates currently provided cover most of the scenarios. For instance, when having a mobile app connecting to an Azure-hosted API, your work will only consist in providing the right reply & identifer URLs.  Topologies having 1 web api, 1 web client and/or 1 mobile client are entirely covered. 

If the amount of clients vary (2 web clients for instance or more than 1 API), the only thing to do is to copy/paste parts of the generated JSON and make sure to update the important parts (reply/identifer URLs).

More advanced scenarios
More advanced scenarios might come with custom API roles and/or Oauth2Permissions. This is typically used when using role-based permissioning at App level. So, if you share an API across mutliple audiences, you might want to let some users do more than others (ie: visitor, contributor, owner...) and some specific roles/scopes will be injected at runtime by AAD and sent to the API. 

The combination of AD Groups/User Assignment at AAD App level where custom roles are associated to groups/Custom roles is also often used to workaround the GroupMembershipClaims limitation depicted earlier.

Also, for S2S calls, exposing different roles enables multiple S2S scenarios with a high granularity.

For these, feel free to have a look at the template pointer provided earlier.​
