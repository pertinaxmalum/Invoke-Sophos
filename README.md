Usage instructions:

Intro to getting Sophos API key:
https://developer.sophos.com/intro

This tool works best if you get a Forensic or Super Admin key at the organisation/partner level (you’re likely ‘organization’) and not at the tenant/subestate level. 
If you dole out the Super Admin key be mindful of who you give it to as it is quite a powerful level of authorisation.

The Forensic key will work for most things, but not everything. Specifically Cases, so it will throw unhandled exceptions if you try to access the cases API with a non-admin key.

For reference:
https://docs.sophos.com/central/customer/help/en-us/ManageYourProducts/GlobalSettings/APICredentials/index.html 

INSTALL:
This has been tested on Windows 10 and 11, outside of those environments you’re on your own, mostly, as I have limited capacity to test it there. 
Put the three files with this cmdlet into the WindowsPowerShell folder of your user account from which you will run PowerShell: 

  C:\Users\{{useraccount}}\Documents\WindowsPowerShell\Modules\Invoke-Sophos

You will likely have to create some of those folders as part of this process. 
Once you’ve done that and you have your client ID and client secret handy, open a new PowerShell window and run the following command:

	Invoke-Sophos -PrepareConfig

This will open a Windows credential prompt. It is for the client ID and secret, NOT your AD credentials so please don’t enter them there. It will walk you through a simple process, when indicating the type of key select either 1 or 3, depending on if you got a Super Admin or Forensic key respectively. 

From a PowerShell command line run:

	Get-Help Invoke-Sophos

I know reading documentation is dull, but it explains most things somewhat well and has several examples on how to use it. Keep in mind they’re very simple examples and aren’t really to show case the full extent of what can be done. 

DESIGN DECISIONS:
    - All queries are manual queries. You can use saved queries, but because it's across multiple subestates with possibly mismatched query IDs it pulls the SQL from 1 estate and runs it across all of them specified. 
    - Default MaxWaitTime is 60 seconds. It can be modified using -MaxWaitTime switch. 
    - DPAPI via Get-Credential and Export-CliXML used to handle at-rest crypto of API keys. Best easy option in PowerShell that doesn't rely on non-core functionality. 
    - API token passed around as a variable for now instead of env var, to leave scope to have it done as an array that allow different keys for different estates. Right now it needs an org/partner level key
    - Default APICallDelay is 1 second

########################
# Log 

Debug/Issues:
    - to enable system wide install add handling for errors for XML config files that can't be decoded i.e. everyone can have their secret in the same folder
    - unmanaged error when the Detection (and Case?) switch is used with no params - just handle but inform user no params being used
    
TODO
Invoke-Sophos: 
    - Two DeleteEndpoints, one for from CSV and one from command line 
    - Get API endpoints progrmatically
        Pull it from the whoami/tenant data and save in an enviornment variable
    - User output during runs
        Mimic what you've done originally and output that you're calling subestates etc for XDR/LD/Detections
    - Retry:
        Could do with being specific ordinal rather than -Last, change value to being an indice
    - GT 90 days:
        Do a 'from' that if someone puts 'Full' or 'all' will searching the previous 90 days and aggregate data into a single result. 
        - Alternative to this is that it could subdivide the query into 30 day chunks and do searches based on that. <= 90 days, gives warning it may take a while
    - paramset handling:
        Put in handling for searchField and search switches only working in LR and not XDR (parameter set)
        Try and group the sections together by Parameter set, so one section that does the full flow of LiveDiscover, another for XDR, etc rather than the phases broken up
    - Exprt GetQueryRunStatus:
        Add in GetQueryRunStatus switch that takes an ID and lets you check the status of a query run
        Ideally this functionality could also be acheived using the PreviousSearches switch where we specify how far back we wish to go and does actions such as get status or as is the case now the results
        Possibly this could be an array rather than a count? E.g 1..5 would get the previous 5 results from the ta
    - Group in searchFields
        GET /endpoint-groups from -getendpoint to allow use of group in searchfields 
    - code flow (paramset and switch)
        Use parameterSet variable in a switch to fully control which sections of code execute. Put things like To/From before that, and output functionality after
    - Incomplete search handling:
        For when queries don't have adequate time to run and are unfinished that should be super clear to the user, includes XDR, Detection and Cases. LiveDiscover is a given
        - Additionally, add in WaitTime to those so that the user can manually control that if needed
    - Variable display in ListQueries
        Fix the variable display int he ListQueries so it does 'name: x type : y description: z | name: x type : y description: z' etc
    - Variable tidier:
        See how much of the variable tidier is still needed when we're converting things to JSON
    - PowerShell standards:
        Rename all functions to be inline with powershell standards
    - DisplayDebugMessaging
        Stick more of the verbose text under verbose - though be cautious about stuff that constitutes errors or warnings, e.g. empty results 
        This would let me be more detailed in what it's doing ...
    - Saved queries 
        Could have it use the queryId to run queries, but it would need to check that the template was the same in all subestates and perhaps throw an error if it wasn't? Though the user might want it that way
        Hard to say ... if they're using an actual queryId then it can be presumed they want that Id run, so do that. Run it in whichever subestate that queryId exists?
    - WaitTimes
        Implement a backoff algorithm for this as well?





