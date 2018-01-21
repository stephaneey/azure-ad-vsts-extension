# Disclaimer
For the time being, the automated provisioning of Azure Active Directory Applications only targets B2E kind of applications. It is not tackling B2C nor B2B (multi-tenant) apps.
## The custom Visual Studio Team Services task in a nutshell
In a nutshell, this task was created to automatically provision Azure Active Directory Applications that allow business applications to authorize users and APIs using OAuth2/OpenID. Instead of doing this job manually for each and every business application, it is possible to automate most of these steps as part of the release life cycle. 
However, in order to remain compliant with most enterprise policies, the provisioned apps remain under the control of the identity and access management team that has to provide the Admin Consent to the deployed apps.
Admin Consent is mandatory for all apps that require application permissions while it is optional in some other cases. However, non-consented apps will prompt users as of the first use, which can be annoying with internal employees as internally developed applications should be considered trusted by default. Since the consent part
is beyond the scope of this task, feel free to handle it your own way.

# Release Notes
## v1.0
* Deploy webapi type of Azure Active Directory Applications
* Deploy native client type of Azure Active Directory Applications
* Deploy custom APIs with custom application roles
* Deploy custom APIs with custom oauth2Permissions
* Enable the implicit grant flow
* Request GroupMembershipClaims
* Request both Delegate & Application permissions to other resources
* Generate App Identifiers and App Secrets and store them into Azure Key Vault
* Grant read access onto provisioned Azure Key Vault secrets to MSI-enabled Azure App Services

# Setup prerequisites
This documentation assumes that you have no Visual Studio Team Services endpoint configured yet. If you already have some and if you know Visual Studio Team Services, feel free to adjust your existing endpoints with the information provided below.
## Creation of the Azure Active Directory Application. 
Once you have enabled this extension into your Visual Studio Team Services account, you have to create an Azure Active Directory Application that will be used by the task in order to authenticate against your directory.
You must grant it the following application permission:
![Azure Active Directory Application Permission](/images/aadapp.png "Azure Active Directory Application Permission")
over your Azure Active Directory tenant. Make sure to create an application secret and to copy its value for later use.
This will give the task the right of registering applications while not being able to interfere with other apps. The task will use the ClientCredentials flow to connect to Azure Active Directory. You may consider the registration of this App somehow similar to a regular VSTS Service Endpoint. 
Note that if you already have endpoints registered, you could simply reuse one of the existing Azure Active Directory Applications and give it the above permission. 
## Granting Contributor Role via Role-Based Access Control aka RBAC
The task is will be using the Azure Active Directory Application created in the previous step while connecting to Azure Active Directory and will also be using the RBAC Contributor role to connect to the subscription hosting the Key Vault (more on this below): 
![rbac](/images/rbac.png "rbac")
In the select textbox, you should enter the application identifier of the app you created.
## Creation of the Key Vault
All the application identifier and secrets will be sent to Azure Key Vault by the task. Therefore, you must have a vault and grant the contributor access policy to the Azure Active Directory Application created earlier as shown by the below screenshot:
![Key vault policy](/images/vaultpolicy.png "Key vault policy")
## Creation of a Service Account
When using Access Tokens together with Azure Active Directory V2 PowerShell cmdlets, an account name must be provided to the Connect-AzureAD cmdlet. Therefore, the easiest is to create a service account that is simply a member of the directory.
## Creation of the VSTS Service Endpoint
Now that the Azure Active Directory Application has all the required permissions, it is time to register it inside of Visual Studio Team Services by creating a new Service Endpoint. 
* In VSTS, just go to the Services page. https://yourvstsworkspace/_admin/_services
* Click on New Service Endpoint ==> Azure Resource Manager ==> at the bottom, click on the link labelled Use the full version of the endpoint dialog and fullfill the form with your own App Id & Secret retrieved from the previous step
You should endup with something similar to this:
![service endpoint](/images/endpoint.png "service endpoint")
You can click on the link labelled Verify connection to see if everything is setup correctly.
# Recommended actions
Since the task is supposed to be used across release definitions, it is easier to setup a Variable Group in Visual Studio Team Services where you define the task parameters. These can be overriden at task level should it vary from time to time. While this step is optional, I strongly recommend you to do it. Here is a screenshot of the Variable Group:
![VSTS Variable Group](/images/vstsgroup.png "VSTS Variable Group")
Note that I blurred some values for privacy reasons but here is what these variables stand for:
* tenant: tenant identifier or domain name of your Azure Active Directory
* vault: name of the Azure Active Directory Key Vault where secrets (app identifers & app secrets) will be stored. Note that you must create this vault before using the task
* vstsaccount: service account with no specific permission, just an Azure Active Directory member
* vstsappid: identifier of the Azure Active Directory Application you registered in the previous step 
* vstsappsecret: secret of the Azure Active Directory Application you registered in the previous step. Make sure to mark this variable as hidden

If you do not create this Variable Group, you'll have to define these values at task level. 

# Using the custom Visual Studio Team Services task
## VSTS Agent
You should use the Hosted 2017 agent. In case you use on-premises agent, I recommend creating a separate Agent Phase using the Hosted 2017 agent. If you do so, feel free to tick the option labelled "Skip download of artifacts".
## Configuring the task
Some of the task parameters directly come from the Variable Group created earlier, which means that you must bind this Variable Group to your release definition. They are pre-configured with variable names. You do not need to change anything if you created the Variable Group as explained earlier.
⋅⋅⋅The task shipps with multiple templates that are intended to cover typical topologies. For instance, when having a mobile app connecting to an Azure-hosted API, your work will only consist in providing the right reply & identifer URLs. Since the input field exposed by the task is merely a textbox, you should use a true JSON editor to configure that part of the task.

Here is an example of a custom API that exposes custom application and delegate permissions, and its related web client.

![task configuration](/images/configexample.png "task configuration")

Here are some explanations of the above screenshot:
* The first application "sampleapi" exposes a custom application role and a custom oauth2permission
* The identifier of the API is reused in the RequiredResourceAccess attribute of the web client. Indeed, the webclient wants to request the MyDelegatePermission scope as well as the role1 application permission.
* The IsPublicClient attribute indicates whether the Azure Active Directory Application is a native one or not
* The attribute KeyVaultAppIdName holds the name of the Key Vault secret that stores the idenfifier of the provisioned Azure Active Directory Application. 
* The attribute KeyVaultAppSecretName holds the name of the Key Vault secret that stores the secret (if any) of the provisioned Azure Active Directory Application. 
* The attribute MSIEnabledRelatedWebAppName lets the task grant the SPN of the related web application, a GET access policy to the Vault storing the application identifier and secret. 

## Dependencies
As you noticed, there is a dependency with the Variable Group but there is more. If you use the MSIEnabledRelatedWebAppName attribute, it assumes that you have deployed the corresponding app with MSI enabled in a previous task, as part of the current release. Similarly, the task pushes some information into Key Vault which needs to be fetched by an App Service. Therefore, it is a good practice to define the name of the keyvault secrets as specific release variables that you can reuse across the different tasks of the current release. If you do not use MSI, you still need to push the secret names to the Azure App Service. This can be done through ARM templates. Here is an example of such a sequence within the same release:

![release configuration](/images/releasetasks.png "release configuration")

where the first task is an ARM template that deploys an App Service with MSI enabled and with the corresponding Key Vault secret names:

![ARM Template](/images/armtemplate.png "ARM Template")
