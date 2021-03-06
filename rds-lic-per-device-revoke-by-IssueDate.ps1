<#  
.SYNOPSIS  
    script to revoke Windows RDS perdevice cal by issue date

.DESCRIPTION  
    script to revoke Windows RDS perdevice cal by issue date
    requires issuedate as parameter
    tested on Windows 2008 r2 and 2012 RDS License server
    any cal with a date older than provided issuedate will attempt revocation
  
.NOTES  
   File Name  : rds-lic-per-device-revoke-by-issuedate.ps1  
   Author     : jagilber
   Version    : 170204 updated help and questions
                
   History    : 160414 original

.EXAMPLE  
    Example: .\rds-lic-per-device-revoke-by-IssueDate.ps1 -issueDate 2/16/2016 -test
    
.PARAMETER issueDate
    IssueDate is any valid date string, example 2/16/2016. Any cal with a issue date older than entered date will be revoked!"

.PARAMETER test
    Use switch test to simulate cal revoke but not perform. it will not however produce next cal revoke date.
#>  

Param(
    [parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter the IssueDate. Any cal with a issue date older than provided date will be revoked!")]
    [string] $issueDate,
    [parameter(Position = 1, Mandatory = $false, HelpMessage = "Use -test to test revocation but not perform.")]
    [switch] $test
)

$ErrorActionPreference = "Stop"
$activeLicenses = @()
$error.Clear()
cls

try
{
    $issueDate = [Convert]::ToDateTime($issueDate).ToString("yyyyMMdd")
}
catch
{
    write-host "invalid issueDate provided. use date format of mm/dd/yyyy. for example 7/30/2014. exiting"
    return
}

write-host "converted issueDate: $($issueDate)"

write-host "----------------------------------"
write-host "key packs:"
$keyPacks = Get-WmiObject Win32_TSLicenseKeyPack
foreach ($keyPack in $keyPacks)
{
    write-host "----------------------------------"
    $keyPack
}
write-host "----------------------------------"
write-host "----------------------------------"

$licenses = get-wmiobject Win32_TSIssuedLicense

if ($licenses -eq $null)
{
    write-host "no issued licenses. returning"
    return
}

#licenseStatus = 4 = revoked, 1 = temp, 2 = permanent
$activelicenses = @($licenses | where { $_.licenseStatus -eq 2 -and $_.IssueDate.SubString(0, 8) -le $issueDate })

if ($activeLicenses.Count -ge 1)
{
    if (!((Read-Host "WARNING:This will revoke up to $($activeLicenses.Count) cals, are you sure you want to continue?[y|n") -icontains "y"))
    {
        return
    }

    foreach ($lic in $activeLicenses)
    {
        write-host "----------------------------------"
        $lic
        write-host "----------------------------------"

        if (($keypacks | Where { $_.KeyPackId -eq $lic.KeyPackId -and $_.ProductType -eq 0 }))
        {
            write-host "revoking license:$($lic.sIssuedToComputer) $($lic.sIssuedToUser) $($lic.IssueDate)"
        
            if (!$test)
            {
                $ret = $lic.Revoke()
                write-host "----------------------------------"
                write-host "return value: $($ret.ReturnValue)"
                write-host "revokableCals: $($ret.RevokableCals)"
                write-host "next revoke allowed on: $($ret.NextRevokeAllowedOn)"
                write-host "----------------------------------"

                if ($ret.ReturnValue -ne 0)
                {
                    if (!((Read-Host "WARNING:error revoking cal, do you you want to continue?[y|n]") -icontains "y"))
                    {
                        return
                    }
                }

                if ($ret.RevokableCals -eq 0 -or ($ret.NextRevokeAllowedOn.Substring(0, 8) -gt [DateTime]::Now.ToString("yyyyMMdd")))
                {
                    write-host "unable to revoke any more cals until 'Next Revoke Allowed On' above in format yyyyMMdd. exiting"
                    return
                }
            }
        }
        else
        {
            write-host "license is not per device"
        }

    }
}
else
{
    write-host "no licenses to revoke"
}

write-host "----------------------------------" 
write-host "finished"
