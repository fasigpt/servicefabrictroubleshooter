param(
[parameter(Mandatory=$true)]
[string]
$subscriptionId,
[parameter(Mandatory=$true)]
[string]
$resourcegroup,
[parameter(Mandatory=$true)]
[string]
$servicefabricclustername
#$servicefabricclustername

) #Pass SubscriptionId and servicefabricclustername Name and the resource group





Function DisplayMessage
{
    Param(
    [String]
    $Message,

    [parameter(Mandatory=$true)]
    [ValidateSet("Error","Warning","Info","Input")]
    $Level
    )
    Process
    {
        if($Level -eq "Info"){
            Write-Host -BackgroundColor White -ForegroundColor Black $Message `n
            }
        if($Level -eq "Warning"){
        Write-Host -BackgroundColor Yellow -ForegroundColor Black $Message `n
        }
        if($Level -eq "Error"){
        Write-Host -BackgroundColor Red -ForegroundColor White $Message `n
        }
                             if($Level -eq "Input"){
            Write-Host -BackgroundColor White -ForegroundColor Black $Message `n
            }
    }
}






function Get-UriSchemeAndAuthority
{
    param(
        [string]$InputString
    )

    $Uri = $InputString -as [uri]
    if($Uri){
               return  $Uri.Authority
    } else {
        throw "Malformed URI"
    }
}



#region Make sure to check for the presence of ArmClient here. If not, then install using choco install
    $chocoInstalled = Test-Path -Path "$env:ProgramData\Chocolatey"
    if (-not $chocoInstalled)
    {
        DisplayMessage -Message "Installing Chocolatey" -Level Info
        Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    else
    {
        #Even if the folder is present, there are times when the directory is empty effectively meaning that choco is not installed. We have to initiate an install in this condition too
        if((Get-ChildItem "$env:ProgramData\Chocolatey" -Recurse | Measure-Object).Count -lt 20)
        {
            #There are less than 20 files in the choco directory so we are assuming that either choco is not installed or is not installed properly.
            DisplayMessage -Message "Installing Chocolatey. Please ensure that you have launched PowerShell as Administrator" -Level Info
            Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        }
    }

    $armClientInstalled = Test-Path -Path "$env:ProgramData\chocolatey\lib\ARMClient"

    if (-not $armClientInstalled)
    {
        DisplayMessage -Message "Installing ARMClient" -Level Info
        choco install armclient
    }
    else
    {
        #Even if the folder is present, there are times when the directory is empty effectively meaning that ARMClient is not installed. We have to initiate an install in this condition too
        if((Get-ChildItem "$env:ProgramData\chocolatey\lib\ARMClient" -Recurse | Measure-Object).Count -lt 5)
        {
            #There are less than 5 files in the choco directory so we are assuming that either choco is not installed or is not installed properly.
            DisplayMessage -Message "Installing ARMClient. Please ensure that you have launched PowerShell as Administrator" -Level Info
            choco install armclient
        }
    }


    <#
    NOTE: Please inspect all the powershell scripts prior to running any of these scripts to ensure safety.
    This is a community driven script library and uses your credentials to access resources on Azure and will have all the access to your Azure resources that you have.
    All of these scripts download and execute PowerShell scripts contributed by the community.
    We know it's safe, but you should verify the security and contents of any script from the internet you are not familiar with.
    #>

#endregion




#Do any work only if we are able to login into Azure. Ask to login only if the cached login user does not have token for the target subscription else it works as a single sign on
#armclient clearcache

if(@(ARMClient.exe listcache| Where-Object {$_.Contains($subscriptionId)}).Count -lt 1){
    ARMClient.exe login >$null
}

if(@(ARMClient.exe listcache | Where-Object {$_.Contains($subscriptionId)}).Count -lt 1){
    #Either the login attempt failed or this user does not have access to this subscriptionId. Stop the script
    DisplayMessage -Message ("Login Failed or You do not have access to subscription : " + $subscriptionId) -Level Error
    return
}
else
{
    DisplayMessage -Message ("User Logged in") -Level Info
}



   
#region building parameters for Connect-ServiceFabricCluster
   $FindValue = $null;
   DisplayMessage -Message "Fetching service fabric basic details..." -Level Info    
              #Fetch service fabric basic details
              $sfbasicjson = ARMClient.exe get /subscriptions/$subscriptionId/resourceGroups/$resourcegroup/providers/Microsoft.ServiceFabric/clusters/$servicefabricclustername/?api-version=2018-02-01
    #Convert the string representation of JSON into PowerShell objects for easy 
              $sfbasicdetails = $sfbasicjson | ConvertFrom-Json

  if ( $sfbasicdetails.properties.clientCertificateThumbprints.Count -lt 1)
  {
              DisplayMessage -Message "No Client Admin Certificates Found. Please upload a certificate to your cluster , refer https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-security-update-certs-azure " -Level Error
  }
  
  else
  {
           if ($sfbasicdetails.properties.clientCertificateThumbprints.Count -eq 1 )
           {
			  $FindValue = $sfbasicdetails.properties.clientCertificateThumbprints[0].certificateThumbprint
			  DisplayMessage -Message "using the cert thumprint $FindValue for authentication" -Level Warning
		   }	
		   else
		   {
			DisplayMessage -Message "Multiple Client Admin Certificates Found..Below are the thumbprints of the admin certificates" -Level Warning
			
			
			 $sfbasicdetails.properties.clientCertificateThumbprints | foreach {   
			 
			   $_.certificateThumbprint
			 }
			
			
			$FindValue = Read-Host -Prompt " `nPlease enter the certificate thumbprint you would like authenticate with"
			
		   }
		   
              
  }
       

       
$StoreLocation = "CurrentUser"
$FindType = "FindByThumbprint"
$StoreName = "My"
$ServerCertThumbprint = $sfbasicdetails.properties.certificate.thumbprint
$hostname= Get-UriSchemeAndAuthority $sfbasicdetails.properties.managementEndpoint
$hostname = $hostname -replace ":\d\d+"
$port = $sfbasicdetails.properties.nodeTypes[0].clientConnectionEndpointPort
$ConnectionEndpoint = $hostname + ':' + $port
#$ConnectionEndpoint
#endregion


#Connecting to the cluster
try
{
$connectArgs = @{ ConnectionEndpoint = $ConnectionEndpoint;  X509Credential = $True;  StoreLocation = $StoreLocation;  StoreName = $StoreName; FindType = $FindType;  FindValue = $FindValue; ServerCertThumbprint = $ServerCertThumbprint  }
DisplayMessage -Message "Connecting to cluster with below details.." -Level Info
$connectArgs
$sfconnection = Connect-ServiceFabricCluster @connectArgs -Verbose
$sfmanifest = Get-ServiceFabricClusterManifest
$sfmanifest
}

Catch
{
  $_.Exception.Message
  
  DisplayMessage -Message "`nMake sure the client certificate with thumbprint $FindValue  is in your User- Personal Certificate Store and if it is self signed, then the cert should also be present in Trusted Root" -Level Error
  
  return
}



return
