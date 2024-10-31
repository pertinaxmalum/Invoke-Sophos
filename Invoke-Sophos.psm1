function Invoke-Sophos {

    <#
        .SYNOPSIS
            This PowerShell cmdlet provides access to the Sophos APIs. Specific APIs provided are Detections, Cases, XDR, Live Discover, Endpoint, Common and SIEM. Not all functionality of those APIs is included, however the core uses have been provided for. 

            ==To install==
            Put the three files with this cmdlet into the WindowsPowerShell folder of your user account from which you will run PowerShell: C:\Users\{{useraccount}}\Documents\WindowsPowerShell\Modules\Invoke-Sophos
            You will likely have to create some of those folders as part of this process. 
            This cmdlet can NOT be run from a shared instance of PowerShell cmdlets as it leverages DPAPI to encrypt the client id and secret at rest. This will be corrected in later versions.
    
        .DESCRIPTION
            This cmdlet can be used to run and retreive queries, both saved and manual, from the core APIs relating to threat hunting and threat detection in Sophos XDR. 
            Flow is controlled via parameter sets, meaning when you begin a query you must, in almost all cases, select one of the following switches first:
                -XDR
                -LiveDiscover
                -Endpoint
                -Detections
                -Cases
                -SIEM
            When running queryies you must specify the API set you wish to use (as above), the query, severity level or any of a number of other options you wish to run it against. 
            Additionally for queries that are likely to take more than 1 minute to fully return a result it it suggested you specify the MaxWaitTime using the -MaxWaitTime switch
            For clarity, see the use cases in the Examples section. 
			
		.PARAMETER PrepareConfig
			This will initialise the configuration file, which is an XML document holding the API credentials being used. This will leverage DPAPI via Get-Credential and Export-Clixml to store the API credentials at rest. Despite this it is still suggested to only use this cmdlet with this function from a hardended workstation and to operate with least privilege by having analysts use Forensic level API keys. 
			Please see: https://docs.sophos.com/central/customer/help/en-us/ManageYourProducts/GlobalSettings/APICredentials/index.html
			This only needs to be done once, or whenever you wish to add an additional key/value pair. It must be done for each user on a shared machine as well (currently not implemented) as DPAPI encryption is specific to the user. 
			e.g. Invoke-Sophos -PrepareConfig
		.PARAMETER WhoAmI
			Shows the Who Am I info from the API key used
			e.g. Invoke-Sophos -WhoAmI
		.PARAMETER GetTenants
			Returns tenant data in a powershell pscustomobject
			e.g. Invoke-Sophos -GetTenants
		.PARAMETER DisplayTenants
			Returns a table of the tenant data using Format-Table
			e.g. Invoke-Sophos -DisplayTenants
		.PARAMETER Subestate
			Allows the selection of the subestates or tenants, depending on preferred term. It is an array of strings, meaning you can supply multiple items which will be applied via regex to the tenants your API key grants you access to.
			Default is all available tenants, in which case you can just not use the -Subestate switch.
			To view your available tenants use: Invoke-Sophos -DisplayTenants
			Disabled and trial tenants are filtered out via a hard-coded mechanism.
			E.g. -Subestate endpoints,servers,dmz
		.PARAMETER Detections
			Invokes the Detection parameter set, direction flow to that API and limiting visible switches to relevant ones.
			e.g. Invoke-Sophos -subestate servers -Detections
		.PARAMETER Cases
			Invokes the Cases parameter set, direction flow to that API and limiting visible switches to relevant ones.
			e.g. Invoke-Sophos -subestate servers -Cases
		.PARAMETER LiveDiscover
			Invokes the LiveDiscover parameter set, direction flow to that API and limiting visible switches to relevant ones.
			e.g. Invoke-Sophos -subestate servers -LiveDiscover
		.PARAMETER Endpoint
			Invokes the Endpoint parameter set, direction flow to that API and limiting visible switches to relevant ones.
			e.g. Invoke-Sophos -subestate servers -Endpoint
		.PARAMETER SIEM
			Invokes the SIEM parameter set, direction flow to that API and limiting visible switches to relevant ones.
			e.g. Invoke-Sophos -subestate servers -SIEM
		.PARAMETER XDR
			Invokes the XDR parameter set, direction flow to that API and limiting visible switches to relevant ones.
			e.g. Invoke-Sophos -subestate servers -XDR
		.PARAMETER ListQueries
			Can be used with the Subestate and API/parameter set variable to list all available queries. 
			This will open another window with the query name, description and needed variables
			E.g. Invoke-Sophos -subestate Servers -XDR -ListQueries
		.PARAMETER QueryNumber
            Can be used with the Subestate variable to run a query against endpoint/s.
			In this example the query requires no variables. 
            E.g. Invoke-Sophos  -subestate Servers -XDR -QueryNumber 12
		.PARAMETER Variables
			Allows the passing in of variables as part of a saved query. Does not apply to manual queries. They must be passed in as a hashtable, as shown below, with a semi-colon between items 
			e.g. Invoke-Sophos -subestate servers -XDR -queryNumber 13 -variables @{username='joe.maliciousInsider';meta_hostname='laptop123'}
		.PARAMETER QueryID
            Runs the query by the ID specified. Sophos queries have the same query ID across all tenants observed, however bespoke queries do not. Use accordingly. If you wish to uniformly run the same query across all subestate reliably then use the -ManualQuery switch. 
            E.g. -QueryID 7fa15cc2-18d1-4896-b600-b405af758fbd
		.PARAMETER DisplayQuery
            Will display the contents of the query for examination prior to use
            E.g. Invoke-Sophos -LiveDiscover -Subestate servers -QueryNumber 10 -DisplayQuery
		.PARAMETER ManualQuery
			For use with the LiveDiscover and XDR APIs. This allows you to specify a bespoke query. 
			E.g. Invoke-Sophos -subestate server -ManualQuery "select distinct meta_hostname from xdr_data"
			E.g. Invoke-Sophos -subestate laptop -ManualQuery "select hostname from system_info" -matchEndpoint 'laptop01' 
		.PARAMETER From
			For use with XDR, LiveDiscover, Detections and Cases, this specifies the date from which you wish to search. If only this switch is used and -To is not it will attempt to search from then to the current time. If this exceeds 30 days the query will fail as that is the maximum time allowed.
			Conforms to the ISO 8601 time date and duration format: -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss
		.PARAMETER To
			For use with XDR, LiveDiscover, Detections and Cases, this specifies the date from which you wish to search. If only this switch is used and -To is not it will attempt to search from then to the current time. If this exceeds 30 days the query will fail as that is the maximum time allowed.
			Conforms to the ISO 8601 time date and duration format: -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss
			The following will get level 10 severity detections for the preceding 9 days, excluding yesterday
			e.g. Invoke-Sophos -subestate laptops -Detections -from '-P10D' -to '-P1D' -DetectionSeverity 10
		.PARAMETER MaxWaitTime
			Specifies the maximum time in seconds any query run - XDR, LiveDiscover or Detections - will be allowed to run for before trying to get whatever data has been found. Queries will return either at this time or when the query run status API indicates all queries have succeeded or failed. 
			XDR and Detection queries should be expected to return much faster than LiveDiscover queries.
			The default is 60 seconds, but can be set manually if you do not wish to wait and the query you are running will take some time to return. Be warned however if you are running very complex queries the WatchDog may enact restrictions in terms of memory or CPU usage
			.e.g Invoke-Sophos -subestate endpoints -Detections -DetectionSeverity 10 -MaxWaitTime 10
		.PARAMETER TargetAllEndpoints
			For use with the LiveDiscover API, this will target all endpoints in the selected tenants.
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -TargetAllEndpoints
		.PARAMETER usernameContains
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching username. 
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -usernameContains 'joe.malicious'
		.PARAMETER groupNameContains
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching group name 
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -groupNameContains 'domain controllers'
		.PARAMETER healthStatus
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching health status, options are "good","suspicious","bad","unknown"
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -healthStatus suspicious
		.PARAMETER hostnameContains
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching hostname, this is wildcarded by default. 
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -hostnameContains 'VM'
		.PARAMETER ids
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching IDs
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -ids 'dc3ce1af-642f-45f3-b91c-33892337cfd5'
		.PARAMETER ipAddresses
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching IP Addresses
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -ipAddresses '172.12.23.34'
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -ipAddresses '172.28.23.34,192.168.1,109'
		.PARAMETER lockdownStatus
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching lockdown status options are: "creatingWhitelist","installing","locked","notInstalled","registering","starting","stopping","unavailable","uninstalled","unlocked"
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -lockdownStatus locked
		.PARAMETER search
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints where the search parameter is found. This can be any value you wish, but which field it is applied to is controlled by the searchField switch below. 
		.PARAMETER searchField
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints with the matching search value, with the search applied to the field specified to by this switch. Options are: "hostname","groupName","osName","ipAddresses","associatedPersonName"
		.PARAMETER tamperProtectionEnabled
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints where the tamper protection is either true or false, depending on selection. Options are 'true' or 'false'
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -lockdownStatus true
		.PARAMETER type
			For use with the LiveDiscover API (and in future versions the Endpoint API, use -GetEndpointRaw for now)
			This will only run the query against endpoints where the type matches what is selected, options are: "computer","server","securityVm"
			e.g. Invoke-Sophos -subestate servers -LiveDiscover -queryNumber 12 -type securityVm
		.PARAMETER QueryName
            You can specify the name of the query to make it easy to understand the purpose of the run
			The cmdlet provides a default value generated at runtime if you do not populate this.
            E.g. -QueryName "Testing for CVE-1234-2022"
		.PARAMETER Format
            There are three options: CSV, GridView and Console. The default is Console. This can be used both with displaying a search result and with displaying the PreviousSearches switch. 
            e.g. -Format GridView
		.PARAMETER SavePath
            Can be used with '-Format CSV' to provide a save path. 
            E.g. '-Format CSV -SavePath C:\temp\sophosresults.csv' 
		.PARAMETER PreviousSearches
            Used to see the metadata of previous searches. Sophos holds this for about 20 minutes after a query is run. The Int specified after the switch gets that number of previous runs from each Subestate specified. The ID returned in the metadata can be used with the next command to get the search results.
            E.g. -PreviousSearches 1
		.PARAMETER GetResult
            Gets the results of a previous query run by ID. This must be specific to a Subestate as the IDs are unique to each one. A format should be specified, with the default being the console.
            e.g. -Getresults c6044b3e-398b-40db-88fa-168ef21ba278 -Format GridView
			
			If used in conjunction with the PreviousSearches switch it will return the data again. Useful if the previous query was recalled too early or not delivered in the right way e.g. console when the desired output was a Grid-View.
			e.g. Invoke-Sophos -subestate server -XDR -PreviousSearches 1 -GetResult true		
		.PARAMETER GetEndpointRaw
            This uses the Endpoint API to retreive data about the Endpoints monitored in Sophos
            They must be entered in hashtable format @{} with a key = value format with multiple value for the same key separated by a semicolon. 
            Possible values: sort, healthStatus, type, tamperProtectionEnabled, lockdownStatus, lastSeenBefore, lastSeenAfter, ids, isolationStatus, hostnameContains, associatedPersonContains, groupNameContains, search, searchFields, ipAddresses, cloud, fields, view, assignedToGroup, groupIds, macAddresses
            E.g. Invoke-Sophos -Subestate All -GetEndpoint @{associatedPersonContains="joe.malicious";ipAddresses="127.0.0.1,10.0.0.1";hostnameCotnains="vm1234";lastSeenAfter="01/01/2021"}
		.PARAMETER APICallDelay
			Sophos doesn't like being spammed with API calls, where needed this has been used to delay things. Default is 1 second. 
		.PARAMETER apiClientId
			Used with the apiClientSecret switch, this allows you to run commands with this cmdlet from the command line without having to store the credentials on disk. 
			e.g. Invoke-Sophos -WhoAmI -apiClientid '{{details here}}' -apiClientSecret '{{details here}}'
		.PARAMETER apiClientSecret
			Used with the apiClientId switch, this allows you to run commands with this cmdlet from the command line without having to store the credentials on disk. 
			e.g. Invoke-Sophos -WhoAmI -apiClientid '{{details here}}' -apiClientSecret '{{details here}}'			
		.PARAMETER GetEvents
			Uses the SIEM API to get the last 24 hours of events
			e.g. Invoke-Sophos -subestate servers -GetEvents
		.PARAMETER GetAlerts
			Uses the SIEM API to get the last 24 hours of events
			e.g. Invoke-Sophos -subestate servers -GetAlerts
		.PARAMETER AccessTokens
			I added this but honestly I have no idea what it's for
		.PARAMETER TagSubestate
			Data returned from Sophos as part of queries does not always retain the SubestateId and SubestateName it came from. When querying from multiple subetstate this can be confusing, so this switch will tag every single result from a Sophos query run with the subestate ID and name. This is not always done as it can add a little bit of time to query runs.
			e.g. Invoke-Sophos -subestate 
		.PARAMETER DeleteEndpoint
			Use with extreme caution. This is hard disabled in code presently 
			Can be used to delete endpoints, at scale, out of Sophos. 
		.PARAMETER SkipDeletionSafetyChecks    
			Skips the safety checks for the above option.
		.PARAMETER HealthCheck
			Returns a PsCustomObject of the health checks from the HealthCheck API. Options are "protection","policy","exclusions","tamperProtection","all"
			e.g. Invoke-Sophos -Subestate Subestate01 -HealthCheck all
			
			This is difficult to display neatly, however if you wish to see the report pass it to Convertto-Json thus:
			e.g. Invoke-Sophos -Subestate Subestate01 -HealthCheck all | ConvertTo-Json -Depth 10 
		.PARAMETER GetTamperProtection
			This will get the Tamper Protection password for a given machine. 
			This version does not currently support directly turning TP on/off, but future versions will. 
			e.g. Invoke-Sophos -Subestate servers -GetTamperProtection laptop1
		.PARAMETER GetCaseDetectionsById
			Not sure if this even works ...
		.PARAMETER CaseManagedBy
			Gets Cases depending on if they are managed by yourself or sophos. Options are: "self","sophos"
		.PARAMETER CaseType
			Gets Cases depending on the type. Options are: "hunt","investigation","incident","healthCheck","duplicate","postureImprovement","customerRequest","activeThreat","exposure","managedRisk","generalRequest"
			e.g. Invoke-Sophos -subestate server -CaseType hunt
		.PARAMETER CaseSeverity
			Gets Cases based on severity. Options are: "critical","high","medium","low","informational"
			e.g. Invoke-Sophos -subestate server -CaseSeverity critical
		.PARAMETER CaseStatus
			Get Cases by status. Options are: "actionRequired","closed","inProgress","inReview","investigating","new","onHold","resolved","takingAction","triage","waitingOnClient"
		.PARAMETER CaseAssignee
			Gets Cases by who they were assigned to. Does not currently work.
		.PARAMETER CaseName
			Gets Cases by name
		.PARAMETER CaseOverviewContains
			Get Cases by overview
		.PARAMETER CaseCreatedAfter
			Get Cases created after the given time
			Conforms to the ISO 8601 time date and duration format: -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss
		.PARAMETER CaseCreatedBefore
			Get Cases before after the given time
			Conforms to the ISO 8601 time date and duration format: -PT12H or -P7D or dd/MM/yyyy or dd/MM/yyyy HH:mm:ss
		.PARAMETER CaseEscalated
			Get Cases by if they were escalated or not. Possible options: true or false.
		.PARAMETER CaseVerdict
			Get Cases by verdict. Options: "falsePositive", "truePositive"
		.PARAMETER CaseSort
			Sort the Cases output. Options: "assignee:asc","assignee:desc","createdAfter:asc","createdAfter:desc","createdBefore:asc","createdBefore:desc","escalated:asc","escalated:desc","managedBy:asc","managedBy:desc","name:asc","name:desc","overviewContains:asc","overviewContains:desc","severity:asc","severity:desc","sort:asc","sort:desc","status:asc","status:desc","type:asc","type:desc","verdict:asc","verdict:desc"
		.PARAMETER GetCasesRaw
			Not currently in use, but left from previous iterations and to be reintroduced to allow more bespoke queries to be run.
		.PARAMETER DetectionCounts
			Gets a Detection breakdown by counts for the specified tenant/s. 
			Can be used with "from","to","DetectionResolution","detectionRule","DetectionSeverity","DetectionType","DetectionCategory","DetectionSource"
		.PARAMETER DetectionSeverity
			Get Detections by severity. Options are: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
			e.g. Invoke-Sophos -Detections -DetectionSeverity 10,8,5,1
		.PARAMETER DetectionCategory
			Get Detections by Category. Options: "cloud","endpoint", "email", "firewall", "iam", "network"
		.PARAMETER DetectionResolution
			For use with the DetectionCounts switch. Will resolve grouping by the selected of the following options: "day","hour", "minute". Default is Day. 
		.PARAMETER DetectionType
			Get Detections by Type. Options: "process","vulnerability", "threat"
		.PARAMETER DetectionSource
			Get Detections by Source. Unclear what a source is. 
		.PARAMETER DetectionMitreAttackTechnique
			Get Detections by MITRE ATT&CK tactic name. Options: "collection","commandControl", "credentialAccess","defenseEvasion","discovery","execution","exfiltration","impact","initialAccess","lateralMovement","persistence","privilegeEscalation","reconnaissance","resourceDevelopment","undefined"
		.PARAMETER DetectionUserName
			Filter Detections by UserName. This is an exact match. 
		.PARAMETER DetectionOperatingSystem
			Gets detections for a given Operating System. This is an exact match field. 
		.PARAMETER DetectionSortField
			 For use with the DetectionSortDirection switch. Options: "category","detectionRule","entity","severity","source","time","type","mitreAttack"
		.PARAMETER DetectionSortDirection
			Sort Detection output. Options: "asc","desc". For use with the DetectionSortField switch.
		.PARAMETER GetDetectionRaw
			Left in from development to later provide capacity for more bespoke detection queries. 
		.PARAMETER DisplayDebugMessaging
		
		.EXAMPLE			
			> Invoke-Sophos -XDR -ListQueries
			
			This will list all queries available for all Subestates, which is acheived by not using the -Subestate switch
		.EXAMPLE
			> Invoke-Sophos -XDR -Subestate DevNet -QueryNumber 1 -DisplayQuery
			
			This will display the query, indicated by QueryNumber 1, available in the XDR set of the tenants matching 'DevNet'
		.EXAMPLE
			> Invoke-Sophos -Detections -Subestate DMZ,DevNet -DetectionSeverity 10,9,8,7,6 -from '-P10D'
			
			This will get all Detections of severity 10,9,8,7,6  from the tenants matching 'DMZ' or 'DevNet' for the last 10 days. Maximum time in one query is 30 days. 
		.EXAMPLE
			> Invoke-Sophos -Cases -Subestate DMZ,DevNet,AWS -CaseCreatedAfter '-P3D'
			
			This will get all Cases from the indicated tenants created within the last 3 days
		.EXAMPLE
			> Invoke-Sophos -XDR -Subestate AWS,DevNet -ManualQuery "select * from xdr_data limit 1" -MaxWaitTime 20 -From '-P10D' -To '-P5D' 
			
			This will run and get a manual query, as specified, from the targeted tenants. The time range is from 10 days ago to 5 days ago.
			
			> Invoke-Sophos -XDR -Subestate AWS,DevNet -ManualQuery "select * from xdr_data limit 1" -MaxWaitTime 20 -From '01/10/2024' -To '05/10/2024' 
			
			A similar query, but with hard coded time range. 
			
			Maximum time spans are limited to 30 days for XDR, Detections and Cases. Additionally, only 90 days of data will be held at a maximum. 			
		.EXAMPLE
			> Invoke-Sophos -LiveDiscover -Subestate laptops -QueryNumber 12 -Variables @{IOC='psexec'} -TargetAllEndpoints -MaxWaitTime 120
			
			This query will run Query 12, 'BackgroundActivityModerator.01.0 - File execution from BAM' at time of writing, with a variable of IOC equalling 'psexec'. As this is a LiveDiscover you should allow ample time for it to run and return. However, be mindful that very complex queries may result in failure or be halted by the WatchDog. 
		.EXAMPLE
			> Invoke-Sophos -subestate server -LiveDiscover -PreviousSearches 1 -GetResult true
			
			This will get the previous 1 search run on the matching tenants via the LiveDiscover API. This can be used for XDR and LiveDiscover API calls. Future versions may include the Detections API. 
		.EXAMPLE
			> Invoke-Sophos -Subestate servers -SIEM -GetEvents
			
			This will get the previous 24 hours of SIEM API events.
			
			> Invoke-Sophos -Subestate servers -SIEM -GetAlerts
			
			This will get the previous 24 hours of SIEM API alerts.
		.EXAMPLE
			> $query = "select * from xdr_data where query_name = 'windows_event_successful_logon' and logon_type in (10,7)"
			> $result = invoke-sophos -XDR -Subestate servers -ManualQuery $query -MaxWaitTime 30 -From '-P30D' -Format console -TagSubestate
			
			Return a XDR query to a variable, looking for logins over the last 30 days, with the subestate of the logs tagged in every instance.
			
			> Invoke-sophos -XDR -Subestate servers -ManualQuery $query -MaxWaitTime 30 -From '-P30D' -Format GridView -TagSubestate
			
			The same query, but with the output in the PowerShell Grid-View, a good option for small to medium data sets. 
			
			> Invoke-sophos -XDR -Subestate servers -ManualQuery $query -MaxWaitTime 30 -From '-P30D' -Format console -TagSubestate -SavePath C:\temp\XDR_query.csv -Format CSV
			
			Again, the same query but this time with the output saved to a CSV file in temp
		.EXAMPLE
			If you wish to retrieve the meta data about an endpoint this can be done via the Endpoint API which is accessible in this cmdlet with the -GetEndpointRaw switch. This can be useful for locating a machine by IP, hostname, etc and if you require a given machine ID or status.
				
			Possible values: sort, healthStatus, type, tamperProtectionEnabled, lockdownStatus, lastSeenBefore, lastSeenAfter, ids, isolationStatus, hostnameContains, associatedPersonContains, groupNameContains, search, searchFields, ipAddresses, cloud, fields, view, assignedToGroup, groupIds, macAddresses

			pageSize and pageTotal are available option for if you wish to limit the size of the output, but they should otherwise be left alone as Invoke-Sophos will handle it as necessary to get all results. 

			Here is a multi-part example:

			> Invoke-Sophos -Subestate All -GetEndpoint @{associatedPersonContains="joe.malicious";ipAddresses="127.0.0.1,10.0.0.1";hostnameCotnains="laptop1";lastSeenAfter="01/01/2021"}
				
			To get it to show you everything you can tell it to show you everything it has seen since before tomorrow, though be warned this could be a large amount of data:
				
			> Invoke-Sophos -Subestate All -GetEndpoint @{lastSeenBefore='P1D'}  
				
			Specific example with return:         
			   
			> Invoke-Sophos -Subestate all -GetEndpoint @{associatedPersonContains="joe.malicious"}


			id                      : be6b55c0-363a-4484-8a4n-q36b34t3b5bn
			type                    : server
			tenant                  : @{id=0123456-b4d5-abcd-4578-987654gfd8}
			hostname                : server1
			health                  : @{overall=good; threats=; services=}
			os                      : @{isServer=True; platform=windows; name=Windows Server 2095; 
										majorVersion=10; minorVersion=1; build=10000}
			ipv4Addresses           : {10.0.0.1}
			macAddresses            : {}
			associatedPerson        : @{name=SCOTLAND\u123456; viaLogin=SCOTLAND\joe.malicious; 
										id=be6b55c0-363a-4484-8a4n-2j16ghe4d6aa4}
			tamperProtectionEnabled : True
			assignedProducts        : {@{code=coreAgent; version=1.1.1.1.1; status=installed}, 
										@{code=endpointProtection; version=1.1.1.1.1; status=installed}, 
										@{code=interceptX; version=1.1.1.1.1; status=installed}}
			lastSeenAt              : 2022-01-27T13:21:10.543Z
			lockdown                : @{status=notInstalled; updateStatus=notInstalled}

		.EXAMPLE
			Use the search and searchField switches to only target a sub-set of machines during a Live Discover query

			Below is an example that will search the osName for 'Windows 11' and return a manual query looking for the system information table. 

			Possible values are "hostname", "groupName", "osName", "ipAddresses" and "associatedPersonName"

			Invoke-Sophos -LiveDiscover -Subestate endpoints -searchField osName -search 'Windows 11' -ManualQuery "select * from system_info" -MaxWaitTime 30 -Format GridView

#>

       [CmdletBinding()]
    Param (
        
        [Parameter(Mandatory = $false, Position = 0)]
        [Array] $Subestate = '.',

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [switch] $Detections,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [switch] $Cases,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "LiveDiscover")]
        [switch] $LiveDiscover,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Endpoint")]
        [switch] $Endpoint,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "SIEM")]
        [switch] $SIEM,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "XDR")]
        [switch] $XDR,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Configuration")]
        [switch] $PrepareConfig,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Configuration")]
        [switch] $PurgeConfigs,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $ListQueries,

        [Parameter(Mandatory = $false, Position = 0)]
        [Int32] $QueryNumber,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $QueryID,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $DisplayQuery,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $RunSilent,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [switch] $TargetAllEndpoints,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [String] $usernameContains,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [String] $groupNameContains,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [ValidateSet("good","suspicious","bad","unknown", IgnoreCase = $true)]
        [Array] $healthStatus,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [string] $hostnameContains, #only 5?

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [string[]] $ids,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [string[]] $ipAddresses,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [ValidateSet("creatingWhitelist","installing","locked","notInstalled","registering","starting","stopping","unavailable","uninstalled","unlocked", IgnoreCase = $true)]
        [string[]] $lockdownStatus,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [String] $search,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [ValidateSet("hostname","groupName","osName","ipAddresses","associatedPersonName", IgnoreCase = $true)]
        [Array] $searchField,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [ValidateSet('true','false', IgnoreCase = $true)]
        [String] $tamperProtectionEnabled,

        [Parameter(Mandatory = $false, ParameterSetName = "LiveDiscover")]
        [Parameter(Mandatory = $false, ParameterSetName = "Endpoint")]
        [ValidateSet("computer","server","securityVm", IgnoreCase = $true)]
        [Array] $type,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $ManualQuery,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $QueryName,

        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateSet("GridView","CSV","Console","Json", IgnoreCase = $true)]
        [String] $Format,

        [Parameter(Mandatory = $false, Position = 0)]
        [Int32] $MaxWaitTime = 60,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "WhoAmI")]
        [Switch] $WhoAmI,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Organization")]
        [Switch] $GetTenants,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Organization")]
        [Switch] $DisplayTenants,
     
        [Parameter(Mandatory = $false, Position = 0)]
        [System.IO.FileInfo]$SavePath,

        [Parameter(Mandatory = $false, Position = 0)]
        [Int32]$PreviousSearches,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $GetResult,

        [Parameter(Mandatory = $false, Position = 0)]
        [Hashtable] $Variables,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Endpoint")]
        [Hashtable] $GetEndpointRaw,

        [Parameter(Mandatory = $false, Position = 0)]
        [Int32] $APICallDelay = 1,

        [Parameter(Mandatory = $false, Position = 0)]
        [String]$apiClientId,

        [Parameter(Mandatory = $false, Position = 0)]
        [String]$apiClientSecret,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "SIEM")]
        [Switch] $GetEvents,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "SIEM")]
        [Switch] $GetAlerts,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $AccessTokens,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $TagSubestate,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $SkipDeletionSafetyChecks,
        
        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "AccountHealthCheck")] 
        [ValidateSet("protection","policy","exclusions","tamperProtection","all", IgnoreCase = $true)]
        [String] $HealthCheck,     

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Endpoint")] 
        [String] $GetTamperProtection,

        [Parameter(Mandatory = $false, Position = 0)]
        [Hashtable] $GetCaseDetectionsById,

        [Parameter(Mandatory = $false, Position = 0)]
        [array] $DeleteEndpoint,

        [Parameter(Mandatory = $false, Position = 0)]
        [Switch] $DisplayDebugMessaging,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $From,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $To,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet("self","sophos", IgnoreCase = $true)]
        [String[]]$CaseManagedBy,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet("hunt","investigation","incident","healthCheck","duplicate","postureImprovement","customerRequest","activeThreat","exposure","managedRisk","generalRequest", IgnoreCase = $true)]
        [String[]]$CaseType,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet("critical","high","medium","low","informational", IgnoreCase = $true)]
        [String[]]$CaseSeverity,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet("actionRequired","closed","inProgress","inReview","investigating","new","onHold","resolved","takingAction","triage","waitingOnClient", IgnoreCase = $true)]
        [String[]]$CaseStatus,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [String]$CaseAssignee,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [String]$CaseName,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [String]$CaseOverviewContains,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [String]$CaseCreatedAfter,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [String]$CaseCreatedBefore,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet($true,$false, IgnoreCase = $true)]
        [String]$CaseEscalated,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet("falsePositive", "truePositive", IgnoreCase = $true)]
        [String]$CaseVerdict,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [ValidateSet("assignee:asc","assignee:desc","createdAfter:asc","createdAfter:desc","createdBefore:asc","createdBefore:desc","escalated:asc","escalated:desc","managedBy:asc","managedBy:desc","name:asc","name:desc","overviewContains:asc","overviewContains:desc","severity:asc","severity:desc","sort:asc","sort:desc","status:asc","status:desc","type:asc","type:desc","verdict:asc","verdict:desc", IgnoreCase = $true)]
        [String]$CaseSort,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Cases")]
        [Hashtable] $GetCasesRaw,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [switch] $DetectionCounts,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)]
        [int[]]$DetectionSeverity, # items must be unique

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet("cloud","endpoint", "email", "firewall", "iam", "network", IgnoreCase = $true)]
        [String[]]$DetectionCategory,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet("day","hour", "minute", IgnoreCase = $true)]
        [String[]]$DetectionResolution,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String] $DetectionRule, #0 ≤ length ≤ 300 matches ^[\p{L}\s.-]*$

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String] $DetectionDeviceName, #0 ≤ length ≤ 200 matches ^[\p{L}\s.-]*$

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet("process","vulnerability", "threat")]
        [String[]]$DetectionType, # items must be unique

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String] $DetectionSource, #0 ≤ length ≤ 200 matches ^[\p{L}\s.-]*$

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet("collection","commandControl", "credentialAccess","defenseEvasion","discovery","execution","exfiltration","impact","initialAccess","lateralMovement","persistence","privilegeEscalation","reconnaissance","resourceDevelopment","undefined", IgnoreCase = $true)]
        [String[]]$DetectionMitreAttackTechnique, # items must be unique

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String[]]$DetectionUserName, # Exact match # items must be unique

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String] $DetectionEntityType, #0 ≤ length ≤ 200 matches ^[\p{L}\s.-]*$

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String] $DetectionLocation, #0 ≤ length ≤ 100 matches ^[\p{L}\s.-]*$

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String[]]$DetectionOperatingSystem, # Exact match 

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String[]]$DetectionOperatingSystemName, #0 ≤ length ≤ 100 matches ^[\p{L}\s.-]*$

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet("category","detectionRule","entity","severity","source","time","type","mitreAttack", IgnoreCase = $true)]
        [String]$DetectionSortField,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [ValidateSet("asc","desc", IgnoreCase = $true)]
        [String]$DetectionSortDirection,

        [Parameter(Mandatory = $false, Position = 0, ParameterSetName = "Detections")]
        [String]$GetDetectionRaw

        ) 

    # Supporting modules
    Import-Module "$PSScriptRoot\Sophos Utils.psm1"

    Import-Module "$PSScriptRoot\Sophos API Controller Utils.psm1"

    # Variables and details
    $env:DisplayDebugMessaging = $DisplayDebugMessaging
    $env:SophosRunNoisy = !$RunSilent
    $env:MaxWaitTime = $MaxWaitTime
    $env:ParameterSetName = $PSCmdlet.ParameterSetName

    $authentication_uri = "https://id.sophos.com/api/v2/oauth2/token"
    $organisation_uri = "https://api.central.sophos.com/whoami/v1"
    $tenants_for_partners_uri = "https://api.central.sophos.com/partner/v1/tenants"
    $eu_endpoints_uri = "https://api-eu01.central.sophos.com/endpoint/v1/endpoints"
    $eu_endpoints_paginated_uri = "https://api-eu01.central.sophos.com/endpoint/v1/endpoints?pageFromKey="
    $env:APICallDelay = $APICallDelay
    $lastSeenAfter_correct_format = "`n1) 2019-09-23T12:02:01.700Z`n2) 2019-09-23T00:00:00.000Z`n3) 4 hours and 500 seconds from now, value is case-sensitive`n    PT4H500S`n4) one day ago`n    -P1D`n5) 2 hours from now`n    PT2H`n6) 20 minutes from now`n    PT20M`n7) 200 seconds ago`n    -PT200S`n"                    
    $lastSeenBefore_correct_format = "`n1) 2019-09-23T12:02:01.700Z`n2) 2019-09-23T00:00:00.000Z`n3) 3 days 4 hours 5 minutes and 0 seconds ago, value is case-sensitive`n    -P3DT4H5M0S`n4) one day from now`n    P1D`n5) 2 hours ago`n    -PT2H`n6) 20 minutes ago`n    -PT20M`n7) 200 seconds from now`n    PT200S`n"
    $valid_endpoint_api_params_details = @'
[{"Field":"pageSize","Details":"Int, default is 50"},{"Field":"pageTotal","Details":"$true or $false"},{"Field":"sort","Details":"unknown"},{"Field":"healthStatus","Details":"bad, good, suspicious, unknown"},{"Field":"type","Details":"computer, server, securityVm"},{"Field":"tamperProtectionEnabled","Details":"$true or $false"},{"Field":"lockdownStatus","Details":"creatingWhitelist, installing, locked, notInstalled, registering, starting, stopping, unavailable, uninstalled, unlocked"},{"Field":"lastSeenBefore","Details":"2019-09-23T12:02:01.700Z or -P3DT4H5M0S"},{"Field":"lastSeenAfter","Details":"2019-09-23T12:02:01.700Z or -P3DT4H5M0S"},{"Field":"ids","Details":"string"},{"Field":"isolationStatus","Details":"isolated, notIsolated"},{"Field":"hostnameContains","Details":"only matches first 10 characters"},{"Field":"associatedPersonContains","Details":"only matches first 10 characters"},{"Field":"groupNameContains","Details":"only matches first 10 characters"},{"Field":"search","Details":"search term, field dictated by next"},{"Field":"searchFields","Details":"default is all: hostname, groupName, associatedPersonName, ipAddresses, osName"},{"Field":"ipAddresses","Details":"ipAddresses='127.0.0.1,10.0.0.1'"},{"Field":"cloud","Details":"aws|azure|gcp, e.g. aws,azure:4975692a"},{"Field":"fields","Details":"The fields to return in a partial response"},{"Field":"view","Details":"basic, summary, full"},{"Field":"assignedToGroup","Details":"$true or $false"},{"Field":"groupIds","Details":"string (uuid)"},{"Field":"macAddresses","Details":"FG-6E-A1-4E-36-E2"}]
'@

    
    ######################
    # Manage To and From #
    ######################

    if ($from -or $to) {
        # Doing this as early as possible to eliminate issues with timespans exceeding 30 days

        if ($from) { $from = Test-DateTime -timeToTest $from ; $fromConvertedToDateTime = Convert-DateTime $from }

        if ($to) { $to = Test-DateTime -timeToTest $to ; $toConvertedToDateTime = Convert-DateTime $to}

        # Check time spans do not exceed 30 days
        if ($from) {

            if (!$to) {
                $time_span = New-TimeSpan -Start $fromConvertedToDateTime
            } else {
                $time_span = New-TimeSpan -Start $fromConvertedToDateTime -End $toConvertedToDateTime 
            }

            # LiveDiscove excluded from this check as it is not a hard limit and is dependent on the WatchDog constraints locally
            if ([math]::round($time_span.totalseconds) -gt 2592000 -and $PSCmdlet.ParameterSetName -ne 'LiveDiscover') { 
                Write-Host "[!] Time range must not exceed 30 days" -ForegroundColor Yellow
                break 
            }

        } elseif ($to) {
            # This check may no always be right, if we're going to use the from/to pair for createBefore and similar. Something to chew on. 
            Write-Host "[!] The -To switch must be used in conjunction with the -From switch" -ForegroundColor Yellow
        }
    }

    #############################
    # Generate Encrypted Object #
    if ($PrepareConfig) {

        Write-Host "
[*] Please enter your client ID that came with the credential as the username and the client secret as the password.  
[*] If you are unsure about this process see: https://developer.sophos.com/intro
[*] Right now this cmdlet only allows use via an organisation or partner level key. Future iterations may include tenant specific authentication."


        #some work needed for multiple keys here
        do {
            # gets the client id/secret pair
            $apiCredentialDetails = Get-Credential

            $keyType = Read-Host "Please select which kind of key you are using.
             
If you are unsure see the following page: https://docs.sophos.com/central/customer/help/en-us/ManageYourProducts/GlobalSettings/APICredentials/index.html

1) Service Principal Super Admin: Users with this role can perform all API operations with full CRUD (Create Read Update Delete) capabilities and have access to queries.
2) Service Principal Management: Users with this role can view and manage admins, roles, endpoints, and security policies but can't run or view queries.
3) Service Principal Forensics: Users with this role can create, view, run, and delete Live Discover queries.
4) Service Principal Read-Only: Users with this role can view all information in the account but can't add, modify, or remove information. They can't run Live Discover queries.
Enter (1, 2, 3 or 4)"

            switch ($keyType) {
                1 {$fileNameForCred = 'SPSA'}
                2 {$fileNameForCred = 'SPM'}
                3 {$fileNameForCred = 'SPF'}
                4 {$fileNameForCred = 'SPRO'}
                default {Write-Warning "[!] Invalid selection. Exiting."; return }
            }

            $filepath = "$($PSScriptRoot)\$($fileNameForCred).xml"

            $apiCredentialDetails | Export-Clixml -Path $filepath

            Read-Host "[?] Would you like to configure another ID? Y/N?"

        } while ($anotherCredential -in 'y','yes')

        return
    }

    ################
    # Purge Configs #
    if ($PurgeConfigs) {
        $xmlFiles = Get-ChildItem $PSScriptRoot -Filter *.xml

        Write-Warning "[!] Deleting files:"
        Write-Host "$($xmlFiles.FullName)"
        $confirm = Read-Host "Proceed (Y/N)"
        
        if($confirm -eq 'Y') { $xmlFiles | %{Remove-Item $_.fullname}} 

        return
       
    }


    ####################
    # get config files #
    if ($apiClientSecret -or $apiClientId){        
        if (!($apiClientSecret -and $apiClientId)) {Write-Warning "[!] Please supply client ID AND client secret"; return}

        $apiClientConfigArray = [pscustomobject]@{
            clientId = $apiClientId
            clientSecret = $apiClientSecret
        }

    } else {     
        
        $apiClientConfigArray = @()

        $xmlFiles = Get-ChildItem $PSScriptRoot -Filter *.xml

        foreach ($xmlFile in $xmlFiles) {

            $xmlObject = $xmlfile.fullname | Import-Clixml

            if (!$xmlObject -is [System.Management.Automation.PSCredential]) {continue}
            
            $apiClientConfigArray += [pscustomobject]@{
                clientId = $xmlObject.username
                clientSecret = $xmlObject.password
                
            }
        }
    }

    ##################
    # Authentication #
    ##################
    $tokenArray = @()

    foreach ($tenantConfig in $apiClientConfigArray) {

        $tokenToAddtoArray = New-Token -clientId $tenantConfig.clientId -clientSecret $tenantConfig.clientSecret

        $tokenArray += [pscustomobject]@{
            entity = $tenantConfig.clientId
            token = $tokenToAddtoArray
        }

    }

    # TODO - change all the code to use a token array rather than a single token?
    $token = $tokenArray.token


    ######################
    # WhoAmI and Tenants #
    ######################

    if ($whoami -or $GetTenants -or $DisplayTenants) {
        
        $WhoAmI_object = Get-WhoAmISophos -bearer_token $token

        if ($GetTenants -or $DisplayTenants) {
            $tenants = Get-Tenants -bearer_token $token -WhoAmI_Object $WhoAmI_object

            if ($DisplayTenants) {
                return $tenants.items | Format-Table
            } else {
                return $tenants.items
            }

        } else {
            return $WhoAmI_object
        }

    }

    ######################
    # get the subestates #
    ######################
    
    # Programatically builds an array of the subestate ID, subestate name and apiHost (the base for all URIs - specific to region)
    if ($Subestate) {
        $arrayTenantIdApiHostName = @()

        $tenants = Get-Tenants -bearer_token $token -WhoAmI_Object $(Get-WhoAmISophos -bearer_token $token)

        foreach ($tenant in $tenants.items) {
        
            # excludes non-production estates
            if ($tenant.billingType -eq 'trial' -or $tenant.status -ne 'active') { continue }

            $arrayTenantIdApiHostName += [pscustomobject]@{
                subestateId = $tenant.id
                subestateName = $tenant.showAs
                apiHost = $tenant.apiHost
            }
        }

    

        $subestateArrayForRequests = @()

        foreach ($estateToRegex in $Subestate) {
           $subestateArrayForRequests += $arrayTenantIdApiHostName | ?{$_.subestateName -match $estateToRegex}
        }

        # Remove duplicates, mildly complicated by it being a PsCustomObject
        $subestateArrayForRequests = $subestateArrayForRequests  | Group subestateId,subestateName,apihost | %{$_.group[0]}

        if (!$subestateArrayForRequests) {
            Write-Warning "[*] No subestates were selected. Selection is via regex. You may supply multiple which will be applied with an OR operator"
            Write-Host "[*] Possible Subestates:"
            $arrayTenantIdApiHostName.subestateName | ft
            return
        }
    }

    ################
    # Get endpoint #
    ################

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        if ($GetEndpointRaw) {

            $GetEndpoint_copy = Copy-Object -DeepCopyObject $GetEndpointRaw

            $final_response_object = @()

            $valid_params = "pageFromKey","pageSize","pageTotal","sort","healthStatus","type","tamperProtectionEnabled","lockdownStatus","lastSeenBefore","lastSeenAfter","ids","isolationStatus","hostnameContains","associatedPersonContains","groupNameContains","search","searchFields","ipAddresses","cloud","fields","view","assignedToGroup","groupIds","macAddresses"

            # Make sure the param key is valid

            foreach ($key in $GetEndpointRaw.keys) {

                if(!$($valid_params.Contains($key))) {
    
                    Write-Host "[!] GetEndpoint must be used with one or more of the following parameters:" -ForegroundColor red
                    $valid_endpoint_api_params_details | convertfrom-json | ft | out-string | Write-Host
                    return
                }
            
            }

            # check param values - validate dates are in correct format:
            foreach ($key in $GetEndpointRaw.Keys) {

                if($key -in "lastSeenBefore","lastSeenAfter") {
                
                    # Check if it's ISO 8601 compliant - e.g. -P30D
                    try{
                        [System.Xml.XmlConvert]::ToTimeSpan($GetEndpoint_copy[$key]) > $null
                    } catch { 
                        $not_valid_ISO_8601 = $true
                    }

                    # Check if it's a datetime value
                    try {
                        $GetEndpoint_copy[$key] = (Get-Date $GetEndpoint_copy[$key]).ToUniversalTime().ToString(‘yyyy-MM-ddTHH:mm:ss.000Z’)
                    } catch {
                        $not_valid_datetime = $true
                    }

                    if ($not_valid_ISO_8601 -and $not_valid_datetime) {
                    
                        Write-Host "[!] Invalid ISO 8601 format or invalid datetime format. The correct formatting is:" -ForegroundColor Red

                        if($key -eq 'lastSeenBefore') { $lastSeenBefore_correct_format }

                        if($key -eq 'lastSeenAfter') { $lastSeenAfter_correct_format }

                        return
                    }
                  
                }
            
            }

            foreach ($tenant in $subestateArrayForRequests) {

                Start-Sleep -Seconds $env:APICallDelay

                #$final_response_object += Get-SophosEndpoint -token $token -subestate_id $tenant_id -GetEndpoint $GetEndpoint_copy

                $final_response_object += Get-SophosEndpointEx -token $token -subestateid $tenant.subestateid -GetEndpointInternal $GetEndpoint_copy
            }

            return $final_response_object
        }


    }

    ####################
    # Delete Endpoints #
    ####################

    if ($DeleteEndpoint) {

    Write-Host "[!] Functionality Currently Disabled. Enable in code." -ForegroundColor Yellow

    <#
    if (!$SkipDeletionSafetyChecks) {
            $confirmationMessage = "You are about to carry out delete functionality. To confirm you wish to continue, type 'Delete' when asked."
            [System.Windows.Forms.MessageBox]::Show($confirmationMessage, "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) > $null

            $userInputConfirmation = Read-Host "Type 'Delete' to confirm"
        } else {
            $userInputConfirmation = 'Delete'
        }

        switch ($userInputConfirmation) {
            Delete {
                    Write-Host "[!] Carrying out deletions." -ForegroundColor DarkYellow

                    if ($DeleteEndpoint.tenantId) {
                        # this uses a field generated by another script which provide a manual control for 
                        $tenants = $DeleteEndpoint.tenantId | select -Unique
                    } elseif ($DeleteEndpoint.tenant) {
                        $tenants = $DeleteEndpoint.tenant.id | select -Unique 
                    }

                    if (!$tenants) { Write-Host "[!] No subestate or tenant selected. Aborting."; return } 

                    foreach ($tenantId in $tenants) {

                        if ($DeleteEndpoint.tenantId) {
                            $endpointObjectsByTenant = $DeleteEndpoint | ?{$_.tenantId -eq $tenantId}
                        } elseif ($DeleteEndpoint.tenant) {
                            $endpointObjectsByTenant = $DeleteEndpoint | ?{$_.tenant.Id -eq $tenantId}
                        }

                        $endpointObjectsByTenantbyIds = $endpointObjectsByTenant.id | select -Unique
                        
                        # Create body object for call - being done one at a time for safety
                        $bodyObjectForDeletionAPI = @{endpointIds = @($endpointObjectsByTenantbyIds)}

                        $deletion_result = Remove-Endpoint -token $token -endpointsToDelete $bodyObjectForDeletionAPI -subestate_id $tenantId

                        $endpoints_deleted = $deletion_result.endpointIds
                        
                        Write-Host "[*] The following endpoints have been deleted:"
                        
                        $endpoints_deleted

                    }
                }
            default {Write-Host "[!] No confirmation to delete. Aborting."; return }
        }
    #>
        return
        
    }

    ##########################
    # Get Unwanted Endpoints #
    ##########################

    # Provides control filters for the endpoint API to build a CSV file of unwanted 


    ##################################
    # Get tamper protection password #
    ##################################

    if ($GetTamperProtection) {

        $final_response_object = @()

        $GetEndpoint = @{hostnameContains=$($GetTamperProtection)}

        foreach ($tenant in $subestateArrayForRequests) {

            Start-Sleep -Seconds $env:APICallDelay

            $endpoint_data = Get-SophosEndpointEx -token $token -subestateid $tenant.subestateid -GetEndpointInternal $GetEndpoint

            if (!$endpoint_data) { continue }

            $final_response_object = Get-TamperProtection -subestate_id $tenant.subestateid -token $token -endpoint_id $endpoint_data.id
        }

        return $final_response_object

    }

    ########
    # SIEM #
    ########
    if ($PSCmdlet.ParameterSetName -eq 'SIEM') {

        ##############
        # Get Events #
        ##############
        if ($GetEvents) {
        
            $final_response_object_events = @()

            foreach ($tenant in $subestateArrayForRequests) {

                Start-Sleep -Seconds $env:APICallDelay

                $response = Get-Event -token $token -subestate_id $tenant.subestateid -from $from

                $response | %{
                    $_.items | Add-Member -MemberType NoteProperty -Name SubestateId -Value $tenant.subestateid
                    $_.items | Add-Member -MemberType NoteProperty -Name SubestateName -Value $tenant.subestateName
                    }

                $final_response_object_events += $response
            }

            return $final_response_object_events.items
        }

        ##############
        # Get Alerts #
        ##############
        if ($Getalerts) {
        
            $final_response_object_events = @()

            foreach ($tenant in $subestateArrayForRequests) {

                Start-Sleep -Seconds $env:APICallDelay

                $final_response_object_events += Get-Alert -token $token -subestate_id $tenant.subestateid -from $from
            }

            return $final_response_object_events.items
        }

    }

    ################
    # Health Check #
    ################

    if ($HealthCheck) {
        
        $final_response_object_events = @()

        foreach ($tenant in $subestateArrayForRequests) {

            Start-Sleep -Seconds $env:APICallDelay

            $final_response_object_events += Get-HealthCheck -token $token -subestate_id $tenant.subestateid -checktype $HealthCheck
        }

        return $final_response_object_events

    }

    #################
    # Access Tokens #
    #################

    if ($AccessTokens) {

        $final_response_object_events = @()

        foreach ($tenant in $subestateArrayForRequests) {

            Start-Sleep -Seconds $env:APICallDelay

            $final_response_object_events += Get-AccessTokens -token $token -subestate_id $tenant.subestateid
        }

        return $final_response_object_events

    }

    #########
    # Cases #
    #########

    if ($PSCmdlet.ParameterSetName -eq 'Cases') {

        if($CaseCreatedAfter) { $testDateResultAfter = Test-DateTime -timeToTest $CaseCreatedAfter} 
        if($CaseCreatedBefore) { $testDateResultBefore = Test-DateTime -timeToTest $CaseCreatedBefore} 
       
        $AmalgamatedCaseParameters = [pscustomobject]@{
            managedBy = $CaseManagedBy
            type = $CaseType
            severity = $CaseSeverity
            status = $CaseStatus
            assignee = $CaseAssignee
            name = $CaseName
            overviewContains = $CaseOverviewContains
            createdAfter = $CaseCreatedAfter
            createdBefore = $CaseCreatedBefore 
            escalated = $CaseEscalated
            verdict = $CaseVerdict
            sort = $CaseSort
        }

        $AmalgamatedCaseParametersCleaned = Remove-NullObjectsFromPsCustomObject $AmalgamatedCaseParameters        

        if ($GetCaseDetectionsById) {
        
            # parameter validation
            # Params:
            <#
                page	
                pageSize
                idContains
                ruleContains
                sort
                caseId
            #>

            $caseDetections = @()

            foreach ($tenant in $subestateArrayForRequests) {
            
                try {
                    $caseDetections += Get-CaseDetectionsById -subestate_id $tenant.subestateid -token $token -parameters $GetCaseDetectionsById 
                } catch { }

            }
        
            return $caseDetections
        }


        # some kind of validation of cases parameters, check if matches known fields and allows values. If not throw.

        $aggregatedCases = @()

        foreach ($tenant in $subestateArrayForRequests) {

            Start-Sleep -Seconds $env:APICallDelay

            if ($env:SophosRunNoisy) { Write-Host "[*] Getting Case data from $($tenant.subestateName)" }
            
            $aggregatedCasesInterim = Get-Cases -subestate_id $tenant.subestateid -token $token -parameters $AmalgamatedCaseParametersCleaned

            If ($aggregatedCasesInterim) {
                $aggregatedCasesInterim.items | %{ $_ | Add-Member -MemberType NoteProperty -Name 'SubestateId' -Value $tenant.SubestateId }
                $aggregatedCasesInterim.items | %{ $_ | Add-Member -MemberType NoteProperty -Name 'SubestateName' -Value $tenant.subestateName }

            }

            $aggregatedCases += $aggregatedCasesInterim

        }

        return $aggregatedCases.items
    }

    ##############
    # Detections #
    ##############

    if ($PSCmdlet.ParameterSetName -eq 'Detections') {

        ##########################
        # Detection API Preamble #
        ##########################

        # gathers the Detection parameters
        # Before merging Case into this, keep in mind it uses the same name of params but with different possible values. 
        $AmalgamateDetectionParameters = [pscustomobject]@{
            severity = $DetectionSeverity
            category = $DetectionCategory
            detectionRule = $DetectionRule
            deviceName = $DetectionDeviceName
            type = $DetectionType
            source = $DetectionSource
            mitreAttackTechnique = $DetectionMitreAttackTechnique
            username = $DetectionUserName
            entityType = $DetectionEntityType
            location = $DetectionLocation
            from = $fromConvertedToDateTime
            to = $toConvertedToDateTime
            resolution = $DetectionResolution
            operatingSystem = $DetectionOperatingSystem
            operatingSystemName = $DetectionOperatingSystemName
            sort = $(if($DetectionSortDirection -or $DetectionSortField) {@{direction=$DetectionSortDirection;field=$DetectionSortField}}else{$null})
        }
        
        $AmalgamateDetectionParametersCleaned = Remove-NullObjectsFromPsCustomObject $AmalgamateDetectionParameters

        ####################
        # Detection Counts #
        ####################

        if ($DetectionCounts){

            if ($fromConvertedToDateTime -xor $toConvertedToDateTime) {
                Write-Host "[!] For DetectionCounts if From or To is supplied the other must be as well" -ForegroundColor Yellow
                Return
            }
            
            $fieldsAllowedInCountsAPI = @("from","to","resolution","detectionRule","severity","type","category","source")

            $AmalgamateDetectionParametersCleaned.psobject.properties.name | ?{$_ -notin $fieldsAllowedInCountsAPI} | %{$AmalgamateDetectionParametersCleaned.psobject.Properties.Remove($_)}

            $AmalgamateDetectionParametersCleanedLimitedToCountFields = $AmalgamateDetectionParametersCleaned
            
            $allDetectionCounts = @()
        
            foreach ($tenant in $subestateArrayForRequests) {
                $result = Get-DetectionCounts -token $token -subestate_id $tenant.subestateid -parameters $AmalgamateDetectionParametersCleanedLimitedToCountFields

                if ($result) { 
                    $result | Add-Member -MemberType NoteProperty -Name 'SubestateId' -Value $tenant.subestateid 
                    $result | Add-Member -MemberType NoteProperty -Name 'SubestateName' -Value $tenant.subestateName
                }
                $allDetectionCounts += $result 
            }

            if ($DetectionCountsReport) {
                <# do work here that amalgamates the various fields into a single report #> 
                Write-Host "Not written this code yet"
            } else {
                return $allDetectionCounts
            }
        }
        
        ######################
        # Run Detection Jobs #
        ######################

        $fieldsAllowedInRunJobAPI = @("severity","category","detectionRule","deviceName","type","source","mitreAttackTechnique","username","entityType","location","from","to","operatingSystem","operatingSystemName","sort")

        $AmalgamateDetectionParametersCleaned.psobject.properties.name | ?{$_ -notin $fieldsAllowedInRunJobAPI} | %{$AmalgamateDetectionParametersCleaned.psobject.Properties.Remove($_)}

        $AmalgamateDetectionParametersCleanedLimitedToRunJobFields = $AmalgamateDetectionParametersCleaned

        $detectionJobs = @()

        foreach ($tenant in $subestateArrayForRequests) {
            
            if ($env:SophosRunNoisy) { Write-Host "[*] Sending query run to $($tenant.subestateName)" }

            $result = Invoke-DetectionsPost -token $token -subestate_id $tenant.subestateid -detectionParameters $AmalgamateDetectionParametersCleanedLimitedToRunJobFields 
            if ($result) { 
                $result | Add-Member -MemberType NoteProperty -Name 'SubestateId' -Value $tenant.subestateid 
                $result | Add-Member -MemberType NoteProperty -Name 'SubestateName' -Value $tenant.subestateName 
            }
            $detectionJobs += $result
        }

        # Sanity check the right number of jobs have been started
        if ($Subestate_IDs_Array.count -gt $detectionJobs.count) { 
            Write-Warning "Not all jobs have been successfully started"
        }

        if ($env:SophosRunNoisy) { Write-Host "[*] Waiting a maximum time of $($env:MaxWaitTime) seconds" }

        ############
        # Get Runs #
        ############

        # Waits until all jobs are complete OR maxwaitime is exceeded while cycling job status
        # returns true if all jobs successful 
        $jobStatus = Test-SophosRunCompletion -jobTypeLiveDiscoverXdrDetection 'detection' -token $token -jobsToTest $detectionJobs

        if (!$jobStatus) { 
            Write-Warning "Not all jobs were successful. Waiting an additional short period before trying to get results"
            Start-Sleep -Seconds 10
        }
        

        ##################################
        # Job Run Status Verbose Output  #
        ##################################

        if ($Verbose) {
            Write-Host "[*] Run Status"
            $detectionJobStatus | select * -ExcludeProperty runSpaceId | Format-Table | Out-String | Write-Host
        }

        ############
        # Get Data #
        ############

        $detectionRunResults = @()

        foreach ($tenant in $subestateArrayForRequests) {
            $DetectionRunIdBySubestate = $detectionJobs | ?{$_.SubestateId -eq $tenant.SubestateId} 
            $result = Get-DetectionsResultsByRunId -token $token -subestate $tenant -detectionRunId $DetectionRunIdBySubestate.id
            if ($result) { 
                $result.items | %{ $_ | Add-Member -MemberType NoteProperty -Name 'SubestateId' -Value $tenant.SubestateId }
                $result.items | %{ $_ | Add-Member -MemberType NoteProperty -Name 'SubestateName' -Value $tenant.subestateName }
            }
            $detectionRunResults += $result
        }


        return $detectionRunResults.items
    }
    
    #################################
    # Get the query/function to run #
    #################################
    
    ########################
    # Saved Query: list em #

    # This will generate a list for the user to select a query number from. If multi estate it will have repeats. 
    # not sure this test will work 
    if (($ListQueries -or $QueryNumber -or $queryID) -and -not $ManualQuery) {
        $linenumber = 1
        $items_to_return = $null

        foreach ($tenant in $subestateArrayForRequests) {

            Start-Sleep -Seconds $env:APICallDelay
        
            if ($XDR) {
                $response = Get-XDRSavedQueries -token $token -subestate_id $tenant.subestateid
            } else {
                $response = Get-SavedQueries -token $token -tenant_id $tenant.subestateid
            } 

            $items_to_return += $response.items
        }

        if (-not $QueryNumber -and -not $queryID) {
            # This will display a numbered output of the available queries to the user. They should select via number. 
            $items_to_return | `
            ForEach-Object {New-Object psObject -Property @{'Number'=$linenumber;'Name'= $_.Name;'SupportedOSes' = $_.supportedOSes;'Variables' = $_.variables;'Description' = $_.Description};$linenumber ++} | `
            Select Number,Name,supportedOSes,Variables,Description | Out-GridView
        }

        if ($ListQueries) { return }

        if ($DisplayQuery) {
            $items_to_return[$QueryNumber - $linenumber]
            return
        }
    } #end of list queries functionality
    
    if ($QueryNumber -or $QueryID) {
        
        # This will put the query the user wishes to run into the query_to_run variable. 
        if ($QueryNumber -and $QueryID) {
            return "[!] Cannot have both QueryNumber and QueryID switches set. Please only use one."
        } elseif ($QueryNumber) {
            $query_to_run = $items_to_return[$QueryNumber - $linenumber]
        } elseif ($QueryID) {
            $query_to_run = $response.items | ?{$_.id -eq $QueryID}
        }

        # We will always need the queryID, so get it here if we don't already
        # if (!$QueryID) { $QueryID = $query_to_run.id }

        # Will need to make changes from here.
        
        # Check if Variables parameters has values, if not then return saying this query has variables and they must be supplied with the query
        # a key point is we just have to handle saved queries here
        # We may need to change the invoke-sophossearch so that it accepts a queryid and variables value and take different action if it's there. 

        if ($query_to_run.variables) {
            $print_variables = $query_to_run.variables
            if ($Variables) {
                # check correct number of variables
                if ($Variables.Count -ne $print_variables.count) { Write-Host "[!] Incorrect number of variables"; return } 

                # check correct names of variables
                $comparison_result = Compare-Object -ReferenceObject $($Variables.keys) -DifferenceObject $query_to_run.variables.name
                if ( $comparison_result ) { Write-Host "[!] Incorrectly named variables"; return }

                # check datatypes (convert dateTime to unix)
                $variables_of_datetime_type = $query_to_run.variables | ?{$_.datatype -eq "dateTime"}
                
                foreach ($variable in $variables_of_datetime_type) {
                    $Variables.$($variable.name) = Get-Date $($Variables.$($variable.name)) -UFormat %s
                }

                # finally, expand, if necessary, the $query_to_run.variables object to include values and put them in
                $query_to_run.variables | Add-Member -MemberType NoteProperty -Name Value -Value "" -ErrorAction SilentlyContinue

                for ($counter = 0; $counter -lt ($query_to_run.variables).count; $counter++) {
                    $variable_name = $query_to_run.variables.getvalue($counter)
                    $query_to_run.variables.getvalue($counter).value = $Variables.$($variable_name.name)
                }

                # Keep this separate for now - not needed but might help keep things neat
                $Variables_for_request = $query_to_run.variables

                # Message user and, for the QueryID searches convert the variables to JSON. The Invoke-SophosSearch depends on this or it'll not be brackted properly
                Write-Host "[*] The query $($query_to_run.name) will be run with the following variables (datetimes have been converted to Unix)"
                $Variables_for_request | select * | Format-Table | Out-String | Write-Host
                Start-Sleep -Seconds $env:APICallDelay
                $Variables_for_request = $variables_of_datetime_type | ConvertTo-Json

                # separate out the template - this'll be used in QueryNumber searches as the actual SQL being sent. 
                $query_template = $query_to_run.template

                # Try and make the request safe to send (convertto-json doesn't work properly for this, unhelpfully)
                $query_template = variable_tidier -Variables $Variables -query_template $query_template

            } 
            #elseif wasn't working for some reason. 
            if (!$Variables) {
                Write-Host "[*] Variables Required:" | Out-String
                $print_variables | select name,datatype | Format-Table | Out-String | Write-Host
                return 
            }
        } else {
            # We come here if there are no variables required.  
            $query_template = $query_to_run.template
            
            $query_template = variable_tidier -Variables $Variables -query_template $query_template

            Write-Host "[*] The query $($query_to_run.name) will be run. It requires no paramaters"
            Start-Sleep -Seconds $env:APICallDelay
        }

    }

    ################
    # Manual Query #
    
    if ($ManualQuery) {
        $query_template = $ManualQuery

        $query_template = variable_tidier -query_template $query_template -Variables $Variables
    }

    ##############
    # Query name #
    if (!$QueryName) {
        if ($query_to_run.name){
            $QueryName = $query_to_run.name
        } else {
            # Just says unnamed query and the date time
            $QueryName = "Unnamed Query $(get-date -Format %d-M-yy-HH:mm:ss)"
        }
    }

    ##########################
    # Re-get Previous Result #
    if ($PreviousSearches -and $GetResult) {
        
        # Get object that shows the ID of the previous result and add in subestate
        $allPreviousSearchMetaDataObject = @()
        
        foreach ($estate in $subestateArrayForRequests) {
            
            if ($XDR) {
                [array]$previousResultObject = Get-XDRQueryRuns -first $PreviousSearches -token $token -subestate $estate.subestateId
            } else {
                [array]$previousResultObject = Get-SophosQueriesRun -first $PreviousSearches -bearer_token $token -subestate $estate.subestateId
            } 

            if ($previousResultObject) {
                $previousResultObject | %{
                    Add-Member -InputObject $_ -MemberType NoteProperty -Name SubestateId -Value $estate.subestateId
                    Add-Member -InputObject $_ -MemberType NoteProperty -Name SubestateName -Value $estate.subestateName
                }

                $allPreviousSearchMetaDataObject += $previousResultObject
            }

            

        }

        # Get the results using the IDs in the objects
        $allPreviousSearchResults = @()

        foreach ($resultObjectToGet in $allPreviousSearchMetaDataObject) {
            
            if ($XDR) {
                $singleResultFromSingleSubestate = Get-XDRResults -query_id $resultObjectToGet.id -subestate_id $resultObjectToGet.subestateId -token $token -WaitTime $MaxWaitTime
            } else {
                $singleResultFromSingleSubestate = Get-LiveDiscoverResult -queryId $resultObjectToGet.id -subestate $resultObjectToGet -token $token
            }

            if ($TagSubestate) {
                $singleResultFromSingleSubestate | %{
                    $_ | Add-Member -MemberType NoteProperty -Name SubestateId -Value $resultObjectToGet.subestateId
                    $_ | Add-Member -MemberType NoteProperty -Name SubestateName -Value $resultObjectToGet.subestateName
                }
            }

            $allPreviousSearchResults += $singleResultFromSingleSubestate
        }

        return $allPreviousSearchResults
    }

    ####################
    # PreviousSearches #

    if ($PreviousSearches) {
        $previous_search_results = @()
        foreach ($estate in $subestateArrayForRequests) {
            
            if ($XDR) {
                [array]$placeholder_prior_to_estate_addition = Get-XDRQueryRuns -first $PreviousSearches -token $token -subestate $estate.subestateId
            } else {
                [array]$placeholder_prior_to_estate_addition = Get-SophosQueriesRun -first $PreviousSearches -bearer_token $token -subestate $estate.subestateId
            } 

            # skip if no results from this subestate
            if (!$placeholder_prior_to_estate_addition) { continue }

            $placeholder_prior_to_estate_addition | %{
                Add-Member -InputObject $_ -MemberType NoteProperty -Name SubestateId -Value $estate.subestateId
                Add-Member -InputObject $_ -MemberType NoteProperty -Name SubestateName -Value $estate.subestateName
            }


            $previous_search_results += $placeholder_prior_to_estate_addition
        }

        if (!$previous_search_results) { return "[*] No Results Found" }

        $output = $previous_search_results | SELECT ID,SubestateName,SubestateId,CreatedAt,Status,Result,Name,ResultCount

        Out-SophosResult -format $Format -results $output -savepath $SavePath

        return # no need to continue from here
    }

    #############
    # GetResult #
    if ($GetResult) {
        if ($subestateArrayForRequests.count -gt 1) { throw "The GetResult switch can only be used with a single subestate, given by the Subestate switch" }
        
        if ($XDR) {
            $output = Get-XDRResults -query_id $GetResult -subestate_id $subestateArrayForRequests.subestateId -token $token -WaitTime $MaxWaitTime
        } else {
            $output = Get-sophosResult -query_id $GetResult -subestate $subestateArrayForRequests.subestateId -bearer_token $token -WaitTime $MaxWaitTime
        }

        Out-SophosResult -format $Format -results $output -savepath $SavePath

        return # no need to continue from here
    }

    #############
    # XDR Block #
    #############
    if ($PSCmdlet.ParameterSetName -eq 'XDR') {

    ###################
    # Generate filter #

        # Note, one additional filter that can be added on for XDR is Ids - but this would either need raw Ids OR could use result of endpointAPI call
        # however it is limited to 1000
    
        if ($XdrMatchEndpoints) { #add this switch

            # foreach - do endpoint API call getting ID
            
            # Assign
            $xdrFilterObject = $resolvedEndpointIds # must be array # must not exceed 1000 items

        }

        if ($XdrEndpointIds) { # add this switch
            # do nothing? Validate no more than 1k? 
            $xdrFilterObject = $xdrEndpointIds # must be array
        }

    ##############
    # Send query #

        # new
        $arrayXdrRunsAndIds = @() 
        foreach ($tenant in $subestateArrayForRequests) {
            
            if ($env:SophosRunNoisy) { Write-Host "[*] Sending query run to $($tenant.subestateName)" }

            $xdrQueryRunResponse = Invoke-XDRRun `
                -subestateIdForQueryRun $tenant `
                -token $token `
                -XDRRunFilters $xdrFilterObject `
                -XDRQueryRunTemplate $query_template `
                -queryRunName $QueryName `
                -xdrFrom $from `
                -xdrTo $to

            if ($xdrqueryRunResponse) {
                Add-Member -InputObject $xdrQueryRunResponse -MemberType NoteProperty -Name subestateId -Value $tenant.subestateId
                Add-Member -InputObject $xdrQueryRunResponse -MemberType NoteProperty -Name subestateName -Value $tenant.subestateName

                $arrayXdrRunsAndIds += $xdrQueryRunResponse
            }

        }

        
        if (!$arrayXdrRunsAndIds) { Write-Warning "[!] No jobs were successfully started. Exiting." ; return}

        if ($env:SophosRunNoisy) { Write-Host "[*] Waiting a maximum time of $($env:MaxWaitTime) seconds" }

    ###############
    # Wait period #

        $jobStatus = Test-SophosRunCompletion -jobTypeLiveDiscoverXdrDetection 'XDR' -token $token -jobsToTest $arrayXdrRunsAndIds

    ########################
    # Get results of query #
        
        $xdrRunResultsItems = @()
        foreach ($xdrRun in $arrayXdrRunsAndIds){
            $xdrRunResultsItemsInterim = Get-XdrResultsEx -queryId $xdrRun.id -subestate $xdrRun -token $token
            #$xdrRunResultsItemsInterim = Get-XdrResults -subestate_id $xdrRun.subestateId -token $token -query_id $xdrRun.id -waittime $MaxWaitTime

            if($xdrRunResultsItemsInterim) {
                if ($TagSubestate) {
                    $xdrRunResultsItemsInterim | %{
                        $_ | Add-Member -MemberType NoteProperty -Name SubestateId -Value $xdrRun.subestateId
                        $_ | Add-Member -MemberType NoteProperty -Name SubestateName -Value $xdrRun.subestateName
                    }
                }

                $xdrRunResultsItems += $xdrRunResultsItemsInterim

            }

        }
    

    ########################
    # Get Query Run Status #
        $xdrRunStatusResults = foreach ($entry in $arrayXdrRunsAndIds) { 

	        Get-RunStatus -token $token -tenant_id $entry.subestateId -run_id $entry.id -XDR $XDR |`
            select @{n='Subestate';e={$entry.subestateName}},result,status,createdat,finishedat,from,to,ID
	
	    }

        Write-Host "`n`n[*] Query Run Status"
        $xdrRunStatusResults | Format-Table | Out-String | Write-Host

    ########################
    # Print and/or display #

        Out-SophosResult -format $Format -results $xdrRunResultsItems -savepath $SavePath

    }

    #######################
    # Live Discover Block #
    #######################
    if ($PSCmdlet.ParameterSetName -eq 'LiveDiscover') {

    ###################
    # Generate filter #
    

        $lastSeenBefore = $to
        $lastSeenAfter = $from 

        $filterForLiveDiscoverQueryRunFinal = [pscustomobject]@{}
        
        # Check if filter is just everything 
        if ($TargetAllEndpoints) {
            Add-Member -InputObject $filterForLiveDiscoverQueryRunFinal -MemberType NoteProperty -Name all -Value $true
        } else {
           
            $filterForLiveDiscoverQueryRun = [pscustomobject]@{
	            associatedPersonContains = $usernameContains
	            groupNameContains = $groupNameContains
	            healthStatus = $healthStatus
	            hostnameContains = $hostnameContains
	            ids = $computerIds
	            ipAddresses = $ipAddresses
	            lastSeenAfter = $lastSeenAfter
	            lastSeenBefore = $lastSeenBefore
	            lockdownStatus = $lockdownStatus
	            os = "" # this is more complex and will require some doing
	            search = $search
	            searchFields = $searchField
	            tamperProtectionEnabled = $tamperProtectionEnabled
	            type = $type 
            }

            $filterForLiveDiscoverQueryRunPrepared = Remove-NullObjectsFromPsCustomObject $filterForLiveDiscoverQueryRun

            if ($filterForLiveDiscoverQueryRunPrepared.count -gt 5) { 
                Write-Error "You can only use upto 5 filters when performing a Live Discover query"
            }

            # To make the API call work with a filter you must provide a hashtable of filters, wrapped in an array, which is itself wrapped in a hashtable where the key is 'filters'
            # This will be appended to a hashtable with a key value of 'matchEndpoints' later on
            $filterForLiveDiscoverQueryRunFinal = @{filters = @($filterForLiveDiscoverQueryRunPrepared) }

               
        }

    ##############
    # Send query #
       

        $liveDiscoverQueryRunsIds = @()

        foreach ($subestate in $subestateArrayForRequests) {

            Start-Sleep -Seconds $env:APICallDelay

            if ($env:SophosRunNoisy) { Write-Host "[*] Sending query run to $($subestate.subestateName)" }

            $queryRunResponse  = Invoke-LiveDiscoverRun `
                -subestateIdForQueryRun $subestate `
                -token $token `
                -liveDiscoverRunFilters $filterForLiveDiscoverQueryRunFinal `
                -liveDiscoverQueryRunTemplate $query_template `
                -queryRunName $QueryName
            
            if ($queryRunResponse) {
                Add-Member -InputObject $queryRunResponse -MemberType NoteProperty -Name subestateId -Value $subestate.subestateId
                Add-Member -InputObject $queryRunResponse -MemberType NoteProperty -Name subestateName -Value $subestate.subestateName

                $liveDiscoverQueryRunsIds += $queryRunResponse
            }
        }

        if (!$liveDiscoverQueryRunsIds) { Write-Warning "[!] No jobs were successfully started. Exiting." ; return}

        if ($env:SophosRunNoisy) { Write-Host "[*] Waiting a maximum time of $($env:MaxWaitTime) seconds" }

    ###############
    # Wait period #
    

        $jobStatus = Test-SophosRunCompletion -jobTypeLiveDiscoverXdrDetection 'LiveDiscover' -token $token -jobsToTest $liveDiscoverQueryRunsIds


    ########################
    # Get results of query #
    
        $liveDiscoverResults = @()
        $liveDiscoverResultsEndpointStatus = @()
        $liveDiscoverResultsEndpointStatusGrouped = @()
        
        foreach ($liveDiscoverRun in $liveDiscoverQueryRunsIds) {
            
            $liveDiscoverResults += Get-LiveDiscoverResult -queryId $liveDiscoverRun.id -subestate $liveDiscoverRun -token $token
            # TODO sanity check / notification of null result? 


            # Get the status of the endpoints at the same time, otherwise the status will not accurately reflect the search results
            $liveDiscoverResultsEndpointStatus = Get-SophosQueryRunEndpoints -subestate $liveDiscoverRun.subestateId -bearer_token $token -query_id $liveDiscoverRun.id

            # group for display of status
            $liveDiscoverResultsEndpointStatusGrouped += Group-EndpointStatusResult -status $liveDiscoverResultsEndpointStatus -subestateName $liveDiscoverRun.subestateName

            # This can be time consuming, best to check if needed and not be default
            if ($tagSubestate) {
                $liveDiscoverResults | %{$_ | Add-Member -MemberType NoteProperty -Name Subestate -Value $liveDiscoverRun.subestateName}
            }

        }



    ########################
    # Get Query Run Status #

        $run_results = foreach ($entry in $liveDiscoverQueryRunsIds) { 
            Get-RunStatus -token $token -tenant_id $entry.subestateId -run_id $entry.id -XDR $false |`
            select @{n='Subestate';e={$entry.subestateName}},result,status,createdat,resultCount,@{n='performance';e={$_.performance.score}},ID
	    }

        Write-Host "`n`n[*] Query Run Status"
        $run_results | Format-Table | Out-String | Write-Host


        Write-Host "[*] Query Run Endpoints Status"
       
        # Step 1: Collect all unique property names
        $allPropertyNames = $liveDiscoverResultsEndpointStatusGrouped  | ForEach-Object { $_.psobject.properties.name } | Sort-Object -Unique 

        $sorted_allPropertyNames = $allPropertyNames | Sort-Object { 
            if ($_ -eq 'subestateName') {
                return [int]::MinValue
            } else {
                return $_
            }
        }

        # Step 2: Create a custom Format-Table view with all property names
        #$all_results_of_queries.endpointStatus  | Select-Object -Property $sorted_allPropertyNames | Format-List | Out-String | Write-Host
        Convert-StatusObjects $liveDiscoverResultsEndpointStatusGrouped | Format-Table | Out-String | Write-Host

    ########################
    # Print and/or display #

        Out-SophosResult -format $Format -results $liveDiscoverResults -savepath $SavePath

    } # end of LiveDiscover block



} #end of function

