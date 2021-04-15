# Script principal contenant toutes les fonctions

$VMs = 'g2-web-02','g2-web-03','g2-web-04'

function connect_vsphere
{
    Write-Output "Connection to vSphere"
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    Connect-VIServer -Server 10.54.2.1 -Protocol https -User root -Password 'Pa$$w0rd'
}

function disconnect_vsphere
{
    Disconnect-VIServer -Server 10.54.2.1 -Confirm:$false
}

function getvm_ip($vmname)
{
    $success = $False
    Do{
        $ip_addr = (Get-VM -Name $vmname).Guest.IPAddress[0]
        if([ipaddress]::TryParse($ip_addr,[ref][ipaddress]::Loopback) -eq $True)
        {
            $success = $True
        }
    }Until($success -eq $True)
    $ip_addr
}

function createvm_vsphere($vmarray)
{
    foreach ($vmname in $vmarray)
    {
        New-VM -Name $vmname -VmFilePath "[datastore1] $vmname/$vmname.vmx"
        Start-VM -VM $vmname
    }
}

function is_iis_up($vmname)
{
    $ip = getvm_ip($vmname)
    $status_code = $false
    Do{
        $Response = Invoke-WebRequest -Uri http://$ip -Headers @{"Host"="g2.eni"}
        if ($Response.StatusCode -eq 200)
        {
            $status_code = $true
        }
        Start-Sleep -Seconds 5
    }Until($status_code -eq $true)
    $status_code
}

function get_ha_conf_version()
{
    $credentials_ha = "dataplaneapi:password"
    $encoded_credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credentials_ha))
    $headers = @{ Authorization = "Basic $encoded_credentials" }
    $Response = Invoke-WebRequest -Uri http://10.54.2.2:5555/v2/services/haproxy/configuration/version -Method GET -Headers $headers
    $version_ha = $Response.Content
    $version_ha = $version_ha -as [int]
    $version_ha
}

function add_to_ha($vmname)
{
    getvm_ip($vmname)
    $version_ha = get_ha_conf_version
    $params = @{"address"=getvm_ip($vmname);
    "check"="enabled";
    "name"="$vmname";
    "port"=80
    }
    $credentials_ha = "dataplaneapi:password"
    $encoded_credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credentials_ha))
    $headers = @{ Authorization = "Basic $encoded_credentials" }
    $Response = Invoke-WebRequest -Uri http://10.54.2.2:5555/v2/services/haproxy/configuration/servers?backend=poolweb"&"version=$version_ha -Method POST -Body ($params|ConvertTo-Json) -ContentType "application/json" -Headers $headers
    $Response.StatusCode
}

function upscale($vmarray)
{
    createvm_vsphere($vmarray)
    Start-Sleep 30
    foreach ($vmname in $vmarray) 
    {
        if (is_iis_up($vmname) -eq 200)
        {
            add_to_ha($vmname)
        }
    }
}

connect_vsphere

upscale($VMs)

disconnect_vsphere