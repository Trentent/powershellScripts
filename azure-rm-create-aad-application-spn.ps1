<#
    creates new azurermadapplication for use with logging in to azurerm using password or cert
    to enable script execution, you may need to Set-ExecutionPolicy Bypass -Force

        Copyright 2017 Microsoft Corporation

        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.

    # can be used with scripts for example
    # cert auth. put in ps script
    # Add-AzureRmAccount -ServicePrincipal -CertificateThumbprint $cert.Thumbprint -ApplicationId $app.ApplicationId -TenantId $tenantId
    # requires free AAD base subscription
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal#provide-credentials-through-automated-powershell-script

    # 170609
#>
param(
    [pscredential]$credentials,
    [Parameter(Mandatory=$true)]
    [string]$aadDisplayName,
    [string]$uri,
    [switch]$list,
    [string]$pfxPath = "$($env:temp)\$($aadDisplayName).pfx",
    [ValidateSet('cert','key','password','certthumb')]
    [string]$logonType
)

# ----------------------------------------------------------------------------------------------------------------
function main()
{
   
    $error.Clear()
    # authenticate
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        try
        {
            Add-AzureRmAccount
        }
        catch [System.Management.Automation.CommandNotFoundException]
        {
            write-host "installing azurerm sdk. this will take a while..."
            
            install-module azurerm
            import-module azurerm

            Add-AzureRmAccount
        }
    }

    if (!$uri)
    {
        $uri = "https://$($env:Computername)/$($aadDisplayName)"
    }

    $tenantId = (Get-AzureRmSubscription).TenantId

    if ((Get-AzureRmADApplication -DisplayNameStartWith $aadDisplayName -ErrorAction SilentlyContinue))
    {
        $app = Get-AzureRmADApplication -DisplayNameStartWith $aadDisplayName

        if ((read-host "AAD application exists: $($aadDisplayName). Do you want to delete?[y|n]") -imatch "y")
        {
            remove-AzureRmADApplication -objectId $app.objectId -Force
        
            $id = Get-AzureRmADServicePrincipal -SearchString $aadDisplayName
        
            if (@($id).Count -eq 1)
            {
                Remove-AzureRmADServicePrincipal -ObjectId $id
            }
        }
    }
    
    if (!$list)
    {
        if ($logontype -ieq 'cert')
        {
            Write-Warning "this option is NOT currently working!!!"
            $cert = New-SelfSignedCertificate -CertStoreLocation "cert:\currentuser\My" -Subject "CN=$($aadDisplayName)" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
            
             if(!$credentials)
    {
            $credentials = (get-credential)
    }
            #$cert = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -eq $thumbPrint)
            $pwd = ConvertTo-SecureString -String $credentials.Password -Force -AsPlainText

            Export-PfxCertificate -cert "cert:\currentuser\my\$($cert.thumbprint)" -FilePath $pfxPath -Password $pwd
            $cert509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate($pfxPath, $pwd)
            $thumbprint = $cert509.thumbprint
            $keyValue = [System.Convert]::ToBase64String($cert509.GetRawCertData())
            write-host "New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore"
            $keyCredential = New-Object  Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADKeyCredential
            $keyCredential.StartDate = $cert.NotBefore
            $keyCredential.EndDate= $cert.NotAfter
            $keyCredential.KeyId = [guid]::NewGuid()
            #$keyCredential.Type = "AsymmetricX509Cert"
            #$keyCredential.Usage = "Verify"
            $keyCredential.CertValue = $cert.Thumbprint #$keyValue
            $keyCredential
            #$app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore
            $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -KeyCredentials $KeyCredential
        }
        elseif ($logontype -ieq 'certthumb')
        {
            
            $cert = New-SelfSignedCertificate -CertStoreLocation "cert:\currentuser\My" -Subject "CN=$($aadDisplayName)" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
            write-host "New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore"
            $thumbprint = $cert.Thumbprint
            $enc = [system.Text.Encoding]::UTF8
            $bytes = $enc.GetBytes($cert.Thumbprint)
            $ClientSecret = [System.Convert]::ToBase64String($bytes)
            $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -Password $ClientSecret -EndDate $cert.NotAfter
        }
        elseif($logontype -ieq 'key')
        {
            $bytes = New-Object Byte[] 32
            $rand = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rand.GetBytes($bytes)

            $ClientSecret = [System.Convert]::ToBase64String($bytes)

            $endDate = [System.DateTime]::Now.AddYears(2)

            $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $URI -IdentifierUris $URI -Password $ClientSecret -EndDate $endDate
            write-host "client secret: $($ClientSecret)" -ForegroundColor Yellow

        }
        else
        {
         if(!$credentials)
    {
            $credentials = (get-credential)
    }
            # to use password
            $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -PasswordCredentials $credentials
        }

        $app
        
        New-AzureRmADServicePrincipal -ApplicationId $app.ApplicationId
        
        Start-Sleep 15
        New-AzureRmRoleAssignment -RoleDefinitionName Reader -ServicePrincipalName $app.ApplicationId
        New-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $app.ApplicationId

        if ($logontype -ieq 'cert' -or $logontype -ieq 'certthumb')
        {
            write-host "for use in script: Add-AzureRmAccount -ServicePrincipal -CertificateThumbprint $($cert.Thumbprint) -ApplicationId $($app.ApplicationId) -TenantId $($tenantId)"
            write-host "certificate thumbprint: $($cert.Thumbprint)"
            
        }
    } # else

    $app
    write-host "application id: $($app.ApplicationId)"
    write-host "tenant id: $($tenantId)"
    write-host "application identifier Uri: $($uri)"
    write-host "keyValue: $($keyValue)"
    write-host "clientsecret: $($clientsecret)"
    write-host "thumbprint: $($thumbprint)"
}
# ----------------------------------------------------------------------------------------------------------------

main