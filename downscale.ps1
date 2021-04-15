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

function remove_from_ha($vmname)
{
    $version_ha = get_ha_conf_version
    $credentials_ha = "dataplaneapi:password"
    $encoded_credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credentials_ha))
    $headers = @{ Authorization = "Basic $encoded_credentials" }
    $Response = Invoke-WebRequest -Uri http://10.54.2.2:5555/v2/services/haproxy/configuration/servers/$vmname"?"backend=poolweb"&"version=$version_ha -Method DELETE -Headers $headers
    $Response.StatusCode
}

function deletevm_vsphere($vmarray)
{
    foreach ($vmname in $vmarray)
    {
        remove_from_ha($vmname)
        Stop-VMGuest -VM $vmname -Confirm:$false
    }
    foreach ($vmname in $vmarray)
    {
        $stopped = $false
        Do{
            $vmtest = Get-VM -Name $vmname
            $powerstatevm = $vmtest.PowerState
        }Until($powerstatevm -eq 'PoweredOff')
        Write-Output "Removing $vmname"
        Remove-VM -VM $vmname -Confirm:$false
    }
}

function downscale($vmarray)
{
    deletevm_vsphere($vmarray)
}

connect_vsphere

downscale($VMs)

disconnect_vsphere