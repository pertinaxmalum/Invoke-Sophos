# Set lookback days here. Do not exceed 30. 
$days = 14

# Query_names of concern or interst 
$query = @"
select * from xdr_data where query_name in 
(
'threat_stickykeys_registry_backdoor',
'windows_event_acl_set_on_admin_accounts_dc',
'windows_event_ad_persistence_adminsdholder_attribute_dc',
'windows_event_ad_user_assigned_control_rights',
'windows_event_audit_log_cleared',
'windows_event_consumers',
'windows_event_dcshadow_dc',
'windows_event_domain_dpapi_key_extraction_dc',
'windows_event_domain_policy_changed_dc',
'windows_event_dos_attack_detected',
'windows_event_dsrm_account_password_change_attempt_dc',
'windows_event_group_policy_privileged_groups_dc',
'windows_event_invalid_logon_brute_force',
'windows_event_kerberoasting_indicator_dc',
'windows_event_kerberos_policy_changed_dc',
'windows_event_kerberos_relay_up',
'windows_event_msds_allowedtodelegateto_modification',
'windows_event_petit_potam_detection_dc',
'windows_event_replay_attack',
'windows_event_replication_user_backdoor_dc',
'windows_event_sam_account_spoofing_dc',
'windows_event_uac_bypass_registry',
'windows_powershell_logging_suspicious_keywords',
'windows_event_sid_history_added_to_account_dc',
'windows_event_sid_history_failed_adding_to_account_dc'
)
"@


Write-Host "[*] XDR Known Threats" -ForegroundColor Red
$output = Invoke-Sophos `
    -ManualQuery $query `
    -from "-P$($days)D" `
    -Format Console `
    -MaxWaitTime 60 `
    -XDR -TagSubestate



# Get Events
$events = Invoke-Sophos -SIEM -GetEvents
    

# Get Cases
$cases = Invoke-Sophos -CaseCreatedAfter $timePeriod -Cases

# Get Detections
$detections = Invoke-Sophos -Detections -DetectionSeverity 10,9,8,7,6 -from $timePeriod

cls

$severityOrder = @{
    'high' = 1
    'medium' = 2
    'low' = 3
}

$objects = $events | ?{$_.group -in 'runtime_detections','web','malware' -or $_.severity -in 'medium','high'}

# Sort the objects
$sortedObjects = $objects | Sort-Object @{
    Expression = { [datetime]::Parse($_.When) }
    Ascending = $false
}

Write-Host "==XDR Behaviour Detections==" -ForegroundColor Green
$output | `
    select `
        subestateName, `
        calendar_time,`
        meta_hostname,`
        meta_username,`
        username,`
        query_name,
        @{name='description';expression={if($_.description){$_.description}elseif($_.ioc_detection_description){$_.ioc_detection_description}}} `
        | Sort calendar_time | ft


Write-Host "==Recent Cases==" -ForegroundColor Green
$cases | select subestateName,@{name='severity';expression={$_.initialDetection.severity}},createdat,id,updatedat,name | sort Updatedat,severity -Descending | ft

$aggregatedDetections = @()

foreach ($detection in $detections) {
        
    $subestate = $detection.subestateName

    $aggregatedDetections += $detection | select `
        subestateName, `
        @{n='severity';e={$_.severity}}, `
        @{name='Machine';expression={$_.device.entity}},`
        @{n='sensorGeneratedAt';e={$_.sensorGeneratedAt}},`
        @{n='detectionRule';e={$_.detectionRule}}

} 

Write-Host "==Recent Detections==" -ForegroundColor Green
$aggregatedDetections | sort sensorGeneratedAt,severity -Descending | ft

    Write-Host "==Recent Events==" -ForegroundColor Green
$sortedObjects | select SubestateName,severity,location,when,name
