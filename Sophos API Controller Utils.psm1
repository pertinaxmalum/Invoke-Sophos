Import-Module "$PSScriptRoot\Sophos Utils.psm1" 

# Variables
$authentication_uri = "https://id.sophos.com/api/v2/oauth2/token"
$organisation_uri = "https://api.central.sophos.com/whoami/v1"
$tenants_for_partners_uri = "https://api.central.sophos.com/partner/v1/tenants"
$eu_endpoints_uri = "https://api-eu01.central.sophos.com/endpoint/v1/endpoints"
$eu_endpoints_paginated_uri = "https://api-eu01.central.sophos.com/endpoint/v1/endpoints?pageFromKey="

function Get-SophosAuth($secureString) {
    $secure_token = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)

    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secure_token)
}

function New-Token ($clientId, $clientSecret) {

    if ($clientSecret -is [System.Security.SecureString]){
        $clientSecretPlain = Get-SophosAuth -secureString $clientSecret
    } else {
        $clientSecretPlain = $clientSecret
    }
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")

    $body = @{
        grant_type = 'client_credentials'
        scope = 'token'
        client_id = $($clientId)
        client_secret = $($clientSecretPlain)

    }

    $response = Invoke-RestMethod -uri "https://id.sophos.com/api/v2/oauth2/token" -Method 'POST' -Headers $headers -Body $body

    $token = $($response.access_token)

    return $token
}

function Group-EndpointStatusResult ($status,$subestateName) {

    #fair warning there's chatGPT code in this function
    
    # Initialize a hashtable to store the grouped data
    $groupedData = @{}

    # Go through statusMessage and remove unnecessary unique data to improve groupings
    foreach ($stat in $status) {
        if ($stat.statusMessage) {
            $stat.statusMessage = $stat.statusMessage -replace '.*(CPU exceeds watchdog boundary 30% CPU limit).*','$1'
            $stat.statusMessage = $stat.statusMessage -replace '.*(watchdog boundary limit exceeded private bytes).*','$1'
        }
    }

    # Iterate over each type of message
    foreach ($message in 'result', 'status', 'statusMessage') {
        # Group the status data by the message type
        $groupedStatus = $status | Group-Object $message

        # Iterate over each group
        foreach ($group in $groupedStatus) {
            $key = if ($group.Name) { "$($message)_$($group.Name)" } else { "$($message)_noResponse" }
            $count = $group.Count

            # Add the count to the corresponding key in the hashtable
            if (-not $groupedData.ContainsKey($key)) {
                $groupedData[$key] = 0
            }
            $groupedData[$key] += $count
        }
    }

    # Create a custom object with the desired structure
    $statusReport = [PSCustomObject]@{
        subestateName = $subestateName
    }

    # Add the dynamic properties to the custom object
    foreach ($key in $groupedData.Keys) {
        Add-Member -InputObject $statusReport -MemberType NoteProperty -Name $key -Value $groupedData[$key]
    }

    # Remove unwanted fields
    $statusReport = $statusReport | Select-Object -Property * -ExcludeProperty result_notAvailable, statusMessage_noResponse

    return $statusReport
}

function variable_tidier($Variables, $query_template) {
    
    if($Variables) {
        foreach ($var in $Variables.GetEnumerator()) {
            $query_template = $query_template -replace "\`$\`$$($var.name)\`$\`$",$($var.value)
        }
    }

    $query_template = $query_template -replace "\/\*([\s\S]*?)\*\/","" #remove multiline comments https://stackoverflow.com/questions/2458785/regex-to-remove-multi-line-comments
    $query_template = $query_template -replace "--.*","" # remove comments as removal of newlines makes them problematic. Doesn't remove multiline comments
    #$query_template = $query_template -replace "[^\x00-\x7F]","" # Remove non-ASCII characters, might break something? - could THEORETICALLY use a capture group and just wildcard whatever it is, but who knows if that'll even work. 
    $query_template = $query_template -replace '(\r|\n|\t)', ' ' # Make it into one line - the newline characters break transmission

    return $query_template
}

function Copy-Object {
    # Got this functionality from somewhere. Stackoverflow? 
    param($DeepCopyObject)
    $memStream = new-object IO.MemoryStream
    $formatter = new-object Runtime.Serialization.Formatters.Binary.BinaryFormatter
    $formatter.Serialize($memStream,$DeepCopyObject)
    $memStream.Position=0
    $formatter.Deserialize($memStream)
}

function Convert-StatusObjects {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Objects
    )

    <#
        First, get all subestate names, then get all field names that aren't subestate names
        Then basically, you're creating a hash table, with the keys being the status e.g. result_failed and the subestates e.g. 32
        status = 'result_failed', ScotsSvr = 38, ScotsEP01 = 3, etc
        That hashtable is then stuck into an array to hold it, which is then displayed
    #>

    # Extract unique sources
    $sources = $Objects | Select-Object -ExpandProperty subestateName -Unique

    # Extract unique status keys
    $statusKeys = $Objects | ForEach-Object { $_.PSObject.Properties.Name } | Where-Object { $_ -ne 'subestateName' } | Sort-Object -Unique

    # Initialize the result array
    $result = @()

    # Populate the result array with the status keys and dynamic source values
    foreach ($statusKey in $statusKeys) {
        $row = [ordered]@{ Status = $statusKey }

        foreach ($source in $sources) {
            $value = ($Objects | Where-Object { $_.subestateName -eq $source } | Select-Object -ExpandProperty $statusKey -ErrorAction SilentlyContinue) -join ''
            $row[$source] = $value
        }

        $result += [PSCustomObject]$row
    }

    # Output the result array
    return $result
}

function Remove-NullObjectsFromPsCustomObject ($psCustomObject) {
    # Doesn't handle nested objects being empty, e.g. if object.innerobject is empty, it'll keep it
    foreach ($key in $($psCustomObject.psobject.Properties.name)) {
        if($psCustomObject.$key -in $null,'') {
            $psCustomObject.psobject.Properties.Remove($key)
        }
    }

    return $psCustomObject
}

function Convert-DateTime($timeToConvert) {
    try{
        $timeToConvert = (Get-Date $timeToConvert).ToUniversalTime().ToString(‘yyyy-MM-ddTHH:mm:ss.000Z’)
    } catch {
        try {
            $SecondsToToModifyDateWith = ([System.Xml.XmlConvert]::ToTimeSpan($timeToConvert)).totalseconds
            if ($timeToConvert -eq '-P30D') { $SecondsToToModifyDateWith = $SecondsToToModifyDateWith +  30} #stupid work around for when doing max time range goes slightly over 30 days
            $timeToConvert = ((get-date).AddSeconds($SecondsToToModifyDateWith).ToUniversalTime()).ToString(‘yyyy-MM-ddTHH:mm:ss.000Z’)
        } catch {
            Write-Host "[!] The time range supplied does not match the ISO 8601 format. Must be like -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss. The date range must also not exceed 30 days." -ForegroundColor Red
            break
        }            
    }

    return $timeToConvert
}

function Test-DateTime($timeToTest) {
        try{
            $timeToTest = (Get-Date $timeToTest).ToUniversalTime().ToString(‘yyyy-MM-ddTHH:mm:ss.000Z’)
            return $timeToTest
        } catch {
            try {
                $XmlTimeConvertionTest = ([System.Xml.XmlConvert]::ToTimeSpan($timeToTest))
                return $timeToTest
            } catch {
                Throw "[!] The time range supplied does not match the ISO 8601 format. Must be like -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss. The date range must also not exceed 30 days."
            
            }            
        }

        Throw "[!] The time range supplied does not match the ISO 8601 format. Must be like -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss. The date range must also not exceed 30 days."
}

function Test-SophosRunCompletion ($jobTypeLiveDiscoverXdrDetection, $token, $jobsToTest) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()

        do {
            $jobRunsStatusTrackingObject = @()

            foreach ($job in $jobsToTest) {
                # sanity sleep
                Start-Sleep -Seconds $env:APICallDelay
                
                # Get job status, handles 3 types of runs
                $thisJobStatus = switch ($jobTypeLiveDiscoverXdrDetection){
                    detection {Get-DetectionsByRunId -token $token -subestate_id $job.SubestateId -detectionRunId $job.id}

                    xdr {Get-XDRQueryRunById -token $token -subestate_id $job.SubestateId -query_id $job.id}

                    LiveDiscover {Get-LiveDiscoverQueryRunById -token $token -subestate_id $job.SubestateId -query_id $job.id}

                }
                    

                # Add to aggregated job status object
                $jobRunsStatusTrackingObject += $thisJobStatus
            }

        } while (
            # result: succeeded, canceled, failed, notAvailable, timedOut
            # status: finished, pending, started

            # if incomplete, true
            $jobRunsStatusTrackingObject.status -ne 'finished' -and
            # time constraint, using maxTime variable (set here but should be set above) 
            $timer.Elapsed.TotalSeconds -lt $env:MaxWaitTime
                
        )

        $timer.Stop()

        if ($timer.Elapsed.TotalSeconds -ge $env:MaxWaitTime) {
            Write-Warning "Timer elapsed on search"
            $finalStatus = $false
        }

        # failure checks
        if ($jobRunsStatusTrackingObject.result -ne 'succeeded') {
            Write-Warning "Result may indicate failure$(if($jobTypeLiveDiscoverXdrDetection -eq 'LiveDiscover'){", however this is not unexpected behaviour for LiveDiscover queries"})"
            # Bit odd to do it this way, should make it more inline with XDR and LD but doing this for now
            if($jobTypeLiveDiscoverXdrDetection -eq 'detection') {
                $jobRunsStatusTrackingObject | select * -ExcludeProperty runSpaceId | Format-Table | Out-String | Write-Host
            }
            $finalStatus = $false
        } else {
            $finalStatus = $true 
        }

        return $finalStatus
}

function Out-SophosResult ($format,$results,$savepath){

    if ($format -eq 'CSV' -and !$savepath){
        Write-Warning "[!] You must specify a location to save to using the -SavePath switch"
    }

    switch ($Format) {
        "GridView" { $results | Out-GridView }
        "CSV" { $results | Export-Csv $SavePath -NoTypeInformation -Force }
        "JSON" { $results | ConvertTo-Json -Depth 100}
        "Console" { return $results }
        Default { return $results } 
    }
}

