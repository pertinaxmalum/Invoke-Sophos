# Variables
$authentication_uri = "https://id.sophos.com/api/v2/oauth2/token"
$organisation_uri = "https://api.central.sophos.com/whoami/v1"
$tenants_for_partners_uri = "https://api.central.sophos.com/partner/v1/tenants"
$eu_endpoints_uri = "https://api-eu01.central.sophos.com/endpoint/v1/endpoints"
$eu_endpoints_paginated_uri = "https://api-eu01.central.sophos.com/endpoint/v1/endpoints?pageFromKey="

function Remove-NullObjectsFromPsCustomObject ($psCustomObject) {
    # Doesn't handle nested objects being empty, e.g. if object.innerobject is empty, it'll keep it
    foreach ($key in $($psCustomObject.psobject.Properties.name)) {
        if($psCustomObject.$key -in $null,'') {
            $psCustomObject.psobject.Properties.Remove($key)
        }
    }

    return $psCustomObject
}

function Get-WhoAmISophos ($bearer_token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $($bearer_token)")

    $response = Invoke-RestMethod 'https://api.central.sophos.com/whoami/v1' -Method Get -Headers $headers

    return $response
}

function Get-Tenants ($bearer_token,$WhoAmI_Object) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer $bearer_token")

    $response = If ($WhoAmI_Object.idType -eq 'organization') 
        {
            $headers.Add("X-Organization-ID", $WhoAmI_Object.id)
            Invoke-RestMethod 'https://api.central.sophos.com/organization/v1/tenants' -Method 'GET' -Headers $headers
        }
        elseif ($WhoAmI_Object.idType -eq 'partner')  {
            $headers.Add("X-Partner-ID", "$WhoAmI_Object.id")
            Invoke-RestMethod 'https://api.central.sophos.com/partner/v1/tenants' -Method 'GET' -Headers $headers
        }

    $response
}

function Get-SophosQueriesRun ($first, $bearer_token, $subestate) {
    # PowerShell - check what queries have been run
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate)")
    $headers.Add("Authorization", "Bearer $($bearer_token)")

    $response = Invoke-RestMethod 'https://api-eu01.central.sophos.com/live-discover/v1/queries/runs' -Method 'GET' -Headers $headers
    return $response.items | select -First $First
}

function Get-LiveDiscoverResult ($queryId, $subestate, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate.subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")

    
    $response = $null #just in case ...

    $returnedResultItems = @()

    do {

        if ($response) { Start-Sleep -Seconds $env:APICallDelay }

        $urlAddition = if($response.pages.nextKey) {"?pageTotal=true&pageFromKey=$($response.pages.nextKey)"}

        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/live-discover/v1/queries/runs/$($queryId)/results$($urlAddition)" -Method 'GET' -Headers $headers

        $returnedResultItems += $response.items

    } while ($response.pages.nextKey)

    if ($returnedResultItems -and $env:SophosRunNoisy) {
        Write-Host "[*] Found results for search in $($subestate.SubestateName)" -ForegroundColor Cyan
    } elseif ($env:SophosRunNoisy) {
        Write-Host "[*] No results for search in $($subestate.SubestateName)" -ForegroundColor Yellow
    }


    return $returnedResultItems
}

function Get-XdrResultsEx ($queryId, $subestate, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate.subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")

    
    $response = $null #just in case ...

    $returnedResultItems = @()

    $possibleTrappedErrors = @()

    do {

        if ($response) { Start-Sleep -Seconds $env:APICallDelay }

        $urlAddition = if($response.pages.nextKey) {"&pageFromKey=$([System.Web.HttpUtility]::UrlEncode($response.pages.nextKey))"}

        try {
            $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($queryId)/results?pageTotal=true&pageSize=2000$($urlAddition)" -Method 'GET' -Headers $headers
        } catch {
            # Sometimes the XDR get results produces an error, bad server request, and the reason is not entirely clear. We just retry. 
            Write-Debug "XDR Query Run Get Encountered Error when trying to query $("https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($queryId)/results?pageSize=2000$($urlAddition)"). Retrying with lower limit."
            
            Start-Sleep -Seconds 10

            $nextkey = [System.Web.HttpUtility]::UrlEncode($response.pages.nextKey)
            
            try {
                $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($queryId)/results?pageTotal=true&pageSize=100&$($nextkey)" -Method 'GET' -Headers $headers
            } catch {
                $quickRunCheck = Get-XDRQueryRunById -query_id $queryId -subestate_id $subestate.subestateId -token $token

                if($quickRunCheck -ne 'succeeded') {
                    $quickStatus = $quickRunCheck.status
                    $quickResult = $quickRunCheck.result
                    Write-Warning "Query run did not finish. Result: $($quickResult) and Status: $($quickStatus). You will need to retry."
                }
            }
        }

        # To handle a rare error where Sophos returns a response Windows cannot convert due to Case-Sensitivity Mismatch
        if($response.items -and $response) {
            $returnedResultItems += $response.items
        } elseif ($response -isnot [System.Management.Automation.PSCustomObject]) {
            $returnedResultItems += $response
            # sometimes Sophos returns a dictionary object with keys with the same name but different capitalisation, causing Invoke-RestMethod to return JSON rather than PsCustomObject
            try { 
                $returnedResultItems += $response | ConvertFrom-Json
            } catch {
                $possibleTrappedErrors += $_.exception.message
            }
        }

    } while ($response.pages.nextKey -and $returnedResultItems.count -lt $response.pages.items)

    
    if($possibleTrappedErrors) {
        Write-Warning "Sophos returned an output that cannot be properly handled. Known issues are: Case-Sensitivity Mismatch in dictionary objects. Attempting to return data regardless."
        $aggregatedTrappedErrors = $possibleTrappedErrors | select -Unique
        foreach ($error in $aggregatedTrappedErrors) {
            Write-Warning "$($error)"
        }
    }

    if ($returnedResultItems -and $env:SophosRunNoisy) {
        Write-Host "[*] Found results for search in $($subestate.SubestateName)" -ForegroundColor Cyan
    } elseif ($env:SophosRunNoisy) {
        Write-Host "[*] No results for search in $($subestate.SubestateName)" -ForegroundColor Yellow
    }

    return $returnedResultItems
}

function Get-SophosQueryRunEndpoints ($subestate, $bearer_token, $query_id) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate)")
    $headers.Add("Authorization", "Bearer $($bearer_token)")

    $body_object = @{
        page = 1
        pageSize = 500
        pageTotal = $true
    }

    $return_object = @()

    do {
                
        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/live-discover/v1/queries/runs/$($query_id)/endpoints" -Method 'GET' -Headers $headers -Body $body_object

        $return_object += $response.items

        $returned_pages_object = $response.pages

        $body_object.page += 1 
                        
    } while($returned_pages_object.current -lt $returned_pages_object.total)

    return $return_object

}

function Invoke-LiveDiscoverRun ($subestateIdForQueryRun, $token, $liveDiscoverRunFilters, $liveDiscoverQueryRunTemplate, $queryRunName) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestateIdForQueryRun.subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")
    $headers.add("Content-Type", "application/json")

    $liveDiscoverRunApiCallObject = [pscustomobject]@{
	    matchEndpoints = $liveDiscoverRunFilters
	    adHocQuery = $(if($liveDiscoverQueryRunTemplate) {@{template=$liveDiscoverQueryRunTemplate;name=$queryRunName}})
	    savedQuery = $(if($savedquery) {@{}})
	    variables = @()
    }

    $liveDiscoverRunApiCallObjectToSend = Remove-NullObjectsFromPsCustomObject $liveDiscoverRunApiCallObject

    $liveDiscoverRunApiCallObjectToSendInJson = $liveDiscoverRunApiCallObjectToSend | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/live-discover/v1/queries/runs" -Method 'Post' -Headers $headers -body $liveDiscoverRunApiCallObjectToSendInJson
    } catch {
        
        $errorContent = $_.ErrorDetails.Message | ConvertFrom-Json

        if (!($errorContent.error -eq "resourceNotFound" -and $errorContent.message -eq "No resolved endpoints found in query submission request")) {
            throw $_
        } else {
            Write-Warning "[*] No resolved endpoints for subestate $($subestateIdForQueryRun.subestateName)"
        }

    }

    return $response

}

function Invoke-XDRRun ($subestateIdForQueryRun, $token, $XDRRunFilters, $XDRQueryRunTemplate,$queryRunName,$xdrFrom,$xdrTo) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestateIdForQueryRun.subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")
    $headers.add("Content-Type", "application/json")

    $xdrRunApiCallObject = [pscustomobject]@{
	    matchEndpoints = $XDRRunFilters
	    adHocQuery = $(if($XDRQueryRunTemplate) {@{template=$XDRQueryRunTemplate;name=$queryRunName}})
	    savedQuery = $(if($savedquery) {@{}})
        from = $xdrFrom
        to = $xdrTo
	    variables = @()
    }

    $xdrRunApiCallObject = Remove-NullObjectsFromPsCustomObject $xdrRunApiCallObject

    $xdrRunApiCallObjectInJson = $xdrRunApiCallObject | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod 'https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs' -Method 'Post' -Headers $headers -Body $xdrRunApiCallObjectInJson

    return $response
}

function Get-LiveDiscoverQueryRunById ($query_id, $subestate_id, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/live-discover/v1/queries/runs/$($query_id)" -Method 'GET' -Headers $headers
   
    return $response
}

function Get-SavedQueries ($token, $tenant_id) {

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$tenant_id")
    $headers.Add("Authorization", "Bearer $token")
        
    $response = Invoke-RestMethod 'https://api-eu01.central.sophos.com/live-discover/v1/queries?pageSize=250' -Method 'GET' -Headers $headers

    return $response
}

function Get-XDRSavedQueries($subestate_id, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod 'https://api-eu01.central.sophos.com/xdr-query/v1/queries?pageSize=250' -Method 'GET' -Headers $headers

    return $response
}

function Get-XDRQuery($subestate_id, $token, $query_id) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/$($query_id)" -Method 'GET' -Headers $headers
    
    return $response
}

function Get-XDRQueryRuns ($first, $subestate_id, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod 'https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs' -Method 'GET' -Headers $headers
    
    if (!$First) {$First = ($response.items).length}
    
    return $response.items | select -First $First
}

function Get-XDRQueryRunById ($query_id, $subestate_id, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($query_id)" -Method 'GET' -Headers $headers
   
    return $response
}

function Get-XDRResults ($subestate_id, $token, $query_id, $waittime) {

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    # Object to return result in - separated due to while loop
    $returned_object = ""


    # do while with try catch to anticipate when 400 error - seems to happen when the request has insufficient time to run before retrieval 
    $fail_counter = 0
    do {
        # Check status of run
        $this_run = Get-XDRQueryRunById -query_id $query_id -subestate_id $subestate_id -token $token
        $run_result = $this_run.result
        
        $Failed = $false
        $fail_counter++ # trying this here as not working below

        try { 
            $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($query_id)/results?pageSize=2000" -Method 'GET' -Headers $headers
        } catch { 
            $failed = $true 
          

            # instead, run test and assess if query has failed. If it has set failed to false and fail_counter to max

            Write-Host "[*] WaitTime insufficient, resulting in error. Waiting for $($waittime) additional seconds." -ForegroundColor Yellow
            Start-Sleep -Seconds $waittime
        }

    } while ($Failed -and $fail_counter -lt 3 -and $run_result -eq 'notAvailable')
    
    #Check run again
    $this_run = Get-XDRQueryRunById -query_id $query_id -subestate_id $subestate_id -token $token
    $run_result = $this_run.result

    if ($run_result -in ('failed', 'canceled', 'timedOut')) {
        Write-Host "[!] Run not successful with result $($run_result)" -ForegroundColor Red
    }   
    
    $returned_object = $response.items

    # Check for another page - op ad to response object of items
    while ($response.pages.nextKey) {
        Start-Sleep -Seconds $env:APICallDelay
        try {            
            $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($query_id)/results?pageSize=2000&pageTotal=true&pageFromKey=$($response.pages.nextKey)" -Method 'GET' -Headers $headers -ErrorAction Stop
        } catch {
            $nextkey = [System.Web.HttpUtility]::UrlEncode($response.pages.nextKey)
            $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$($query_id)/results?pageSize=2000&pageTotal=true&pageFromKey=$($nextkey)" -Method 'GET' -Headers $headers
        }
        $returned_object += $response.items
    }

    return $returned_object

}

function Get-SophosEndpointEx ($token, $subestateId, $getEndpointInternal) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")

    if (!$getEndpointInternal.pageSize) { $getEndpointInternal.pageSize = 500}
    
    $returnedEndpointData = @()

    do {
        if ($response) { Start-Sleep -Seconds $env:APICallDelay }

        $urlParametersToAdd = ($getEndpointInternal.GetEnumerator() |  %{"$([System.Web.HttpUtility]::UrlEncode($_.key))=$([System.Web.HttpUtility]::UrlEncode($_.value))"}) -join "&"

        $url = 'https://api-eu01.central.sophos.com/endpoint/v1/endpoints' + $(if($urlParametersToAdd) {"?$($urlParametersToAdd)"})

        $response = Invoke-RestMethod -Uri $url -Method 'GET' -Headers $headers

        $returnedEndpointData += $response.items

        $getEndpointInternal.pageFromKey = $response.pages.nextKey

    } while ($response.pages.nextKey)

    return $returnedEndpointData

}

function Get-Event($subestate_id, $token, $from) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    try {
        if($from) {$from_unix = get-date (get-date $from) -UFormat %s}
        $from_unix_url_safe = "&from_date=$($from_unix)"
    } catch {
        Write-Host "[!] Error with date format. Must be like dd/MM/yyyy or dd/MM/yyyy HH:mm:ss"
    }

    $multi_response_object = @()

    do {
        
        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/siem/v1/events?limit=1000$(if($from){$from_unix_url_safe})$next_cursor" -Method 'GET' -Headers $headers

        $multi_response_object += $response

        $next_cursor = "&cursor=$($response.next_cursor)"

    } while ($response.has_more -eq 'True')

    return $multi_response_object
}

function Get-Alert ($subestate_id, $token, $from) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    try {
        if($from) {$from_unix = get-date (get-date $from) -UFormat %s}
        $from_unix_url_safe = "&from_date=$($from_unix)"
    } catch {
        Write-Host "[!] Error with date format. Must be like dd/MM/yyyy or dd/MM/yyyy HH:mm:ss"
    }

    $multi_response_object = @()

    do {
        
        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/siem/v1/alerts?limit=1000$(if($from){$from_unix_url_safe})$next_cursor" -Method 'GET' -Headers $headers

        $multi_response_object += $response

        $next_cursor = "&cursor=$($response.next_cursor)"

    } while ($response.has_more -eq 'True')

    return $multi_response_object
}

function Get-TamperProtection($subestate_id, $token, $endpoint_id) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/endpoint/v1/endpoints/$($endpoint_id)/tamper-protection" -Method 'GET' -Headers $headers

    return $response
}

function Get-HealthCheck($subestate_id, $token, $checktype) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/account-health-check/v1/health-check$(if($checktype -ne 'all'){"?checks=$checktype"})" -Method 'GET' -Headers $headers

    return $response
}

function Get-AccessTokens($subestate_id, $token) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api.central.sophos.com/accounts/v1/access-tokens" -Method 'GET' -Headers $headers

    return $response
}

function Get-RunStatus ($token, $tenant_id, $run_id, $xdr) {

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$tenant_id")
    $headers.Add("Authorization", "Bearer $token")
    
    if ($XDR) {    
        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/xdr-query/v1/queries/runs/$run_id" -Method 'GET' -Headers $headers
    } else { 
        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/live-discover/v1/queries/runs/$run_id" -Method 'GET' -Headers $headers
    }
    return $response
}

function Get-Cases ($subestate_id, $token, $parameters) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")
    
    $parameters | Add-Member -MemberType NoteProperty -Name page -Value 1 -Force
    $parameters | Add-Member -MemberType NoteProperty -Name pageSize -Value 2000 -Force

    $returnAllPages = @()

    do {

        $urlParametersToAdd = ($parameters.psobject.Properties | %{"$([System.Web.HttpUtility]::UrlEncode($_.name))=$([System.Web.HttpUtility]::UrlEncode($_.value))"}) -join "&"

        $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/cases/v1/cases$(if($urlParametersToAdd){"?$($urlParametersToAdd)"})" -Method Get -Headers $headers

        $returnAllPages += $response

        $parameters.page++

    } while ($response.pages.current -lt $response.pages.total -and $response.pages)

    return $returnAllPages
}

function Get-CaseDetectionsById ($subestate_id, $token, $parameters) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")
    
    $caseId = $parameters.caseId

    $parameters = $parameters.GetEnumerator() | ?{$_.name -ne 'caseId'}

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/cases/v1/cases/$($caseId)/detections" -Method 'GET' -Headers $headers -Body $parameters

    return $response
}

function Get-CaseDetectionsDetailsByDetectionId ($subestate_id, $token, $parameters,$detectionId) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")
    
    $caseId = $parameters.caseId

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/cases/v1/cases/$($caseId)/detections/$($detectionId)" -Method 'GET' -Headers $headers 

    return $response
}

function Update-SophosCase ($subestate, $token, $caseId, $UpdateCaseAssignee, $UpdateCaseName, $UpdateCaseOverview, $UpdateCaseSeverity, $UpdateCaseStatus, $UpdateCaseType) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate.subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")

    $parameters = [pscustomobject]@{
      assignee = $UpdateCaseAssignee
      name = $UpdateCaseName
      overview = $UpdateCaseOverview
      severity = $UpdateCaseSeverity
      status = $UpdateCaseStatus
      type = $UpdateCaseType
    }

    $parametersToSend = Remove-NullObjectsFromPsCustomObject $parameters | ConvertTo-Json
    
    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/cases/v1/cases/$($caseId)" -Method Patch -Headers $headers -Body $parametersToSend

    return $response

}

function Invoke-DetectionsPost ($token, $subestate_id, $detectionParameters) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Accept", "application/json")

    $detectionParametersJson = $detectionParameters | ConvertTo-Json

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/detections/v1/queries/detections" -Method Post -Headers $headers -Body $detectionParametersJson

    return $response

}

function Get-DetectionsByRunId ($token, $subestate_id, $detectionRunId) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/detections/v1/queries/detections/$($detectionRunId)" -Method Get -Headers $headers

    return $response
}

function Get-DetectionsResultsByRunId ($token, $subestate, $detectionRunId) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate.subestateId)")
    $headers.Add("Authorization", "Bearer $($token)")

    $urlParameters = [pscustomobject]@{
        page = 1
        pageSize = 2000
    }

    $returnAllPages = @()

    do {
        try {
            $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/detections/v1/queries/detections/$($detectionRunId)/results?page=$($urlParameters.page)&pageSize=$($urlParameters.pageSize)" -Method Get -Headers $headers

            $returnAllPages += $response

            $urlParameters.page++
        } catch {
            $message = $_
            if ($env:DisplayDebugMessaging) { Write-Warning "DEBUG: Call failed: $message" }
        }

    } while ($response.pages.current -lt $response.pages.total -and $response.pages)

    if ($returnAllPages -and $env:SophosRunNoisy) {
        Write-Host "[*] Found results for search in $($subestate.SubestateName)" -ForegroundColor Cyan
    } elseif ($env:SophosRunNoisy) {
        Write-Host "[*] No results for search in $($subestate.SubestateName)" -ForegroundColor Yellow
    }

    return $returnAllPages
}

function Get-DetectionCounts ($token, $subestate_id, $parameters) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    # concatenate the URL params
    $urlParametersToAdd = ($parameters.psobject.Properties | %{"$([System.Web.HttpUtility]::UrlEncode($_.name))=$([System.Web.HttpUtility]::UrlEncode($_.value))"}) -join "&"
    
    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/detections/v1/queries/detections/counts$(if($urlParametersToAdd){"?$($urlParametersToAdd)"})" -Method Get -Headers $headers

    return $response

}

function Remove-Endpoint ($token, $endpointsToDelete, $subestate_id) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Tenant-ID", "$($subestate_id)")
    $headers.Add("Authorization", "Bearer $($token)")

    $json_endpointsToDelete = $endpointsToDelete | ConvertTo-Json -Depth 2 

    $response = Invoke-RestMethod "https://api-eu01.central.sophos.com/endpoint/v1/endpoints/delete" -Method Post -Headers $headers -body $json_endpointsToDelete -ContentType "application/json"

    #Write-Warning "This function is currently hard disabled. Modify code to enable. No endpoints were deleted."

    return $response
}
