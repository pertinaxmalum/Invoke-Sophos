# Usage instructions

Intro to getting Sophos API key:
https://developer.sophos.com/intro

This tool works best if you get a Forensic or Super Admin key at the organisation/partner level (you’re likely ‘organization’) and not at the tenant/subestate level. 
If you dole out the Super Admin key be mindful of who you give it to as it is quite a powerful level of authorisation.

The Forensic key will work for most things, but not everything. Specifically Cases, so it will throw unhandled exceptions if you try to access the cases API with a non-admin key.

For reference:
https://docs.sophos.com/central/customer/help/en-us/ManageYourProducts/GlobalSettings/APICredentials/index.html 

# Installation
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

# DESIGN DECISIONS
    - All queries are manual queries. You can use saved queries, but because it's across multiple subestates with possibly mismatched query IDs it pulls the SQL from 1 estate and runs it across all of them specified. 
    - Default MaxWaitTime is 60 seconds. It can be modified using -MaxWaitTime switch. 
    - DPAPI via Get-Credential and Export-CliXML used to handle at-rest crypto of API keys. Best easy option in PowerShell that doesn't rely on non-core functionality. 
    - API token passed around as a variable for now instead of env var, to leave scope to have it done as an array that allow different keys for different estates. Right now it needs an org/partner level key
    - Default APICallDelay is 1 second

# Log 

Debug/Issues:
    - to enable system wide install add handling for errors for XML config files that can't be decoded i.e. everyone can have their secret in the same folder
    - unmanaged error when the Detection (and Case?) switch is used with no params - just handle but inform user no params being used
    
TODO
Invoke-Sophos: 
- Two DeleteEndpoints, one for from CSV and one from command line
- User output during runs ( just missing 'getting result'
- Retry: Could do with being specific ordinal rather than -Last, change value to being an indice
- GT 90 days: Do a 'from' that if someone puts 'Full' or 'all' will searching the previous 90 days and aggregate data into a single result. 
- paramset handling: not sure how 
- Exprt GetQueryRunStatus: Add in GetQueryRunStatus switch that takes an ID and lets you check the status of a query run. Ideally this functionality could also be acheived using the PreviousSearches switch where we specify how far back we wish to go and does actions such as get status or as is the case now the results
- XDR, add in endpoint ID option via endpoint lookup. Mind 1k limit (segmented searches or hard limit?)
- code flow (paramset and switch) Use parameterSet variable in a switch to fully control which sections of code execute. Put things like To/From before that, and output functionality after
- Incomplete search handling: For when queries don't have adequate time to run and are unfinished that should be super clear to the user, includes XDR, Detection and Cases. LiveDiscover is a given
- Variable display in ListQueries: Fix the variable display int he ListQueries so it does 'name: x type : y description: z | name: x type : y description: z' etc
- Variable tidier: See how much of the variable tidier is still needed when we're converting things to JSON
- DisplayDebugMessaging: Stick more of the verbose text under verbose - though be cautious about stuff that constitutes errors or warnings, e.g. empty results. This would let me be more detailed in what it's doing ...
- Saved queries: Could have it use the queryId to run queries, but it would need to check that the template was the same in all subestates and perhaps throw an error if it wasn't? Though the user might want it that way Hard to say ... if they're using an actual queryId then it can be presumed they want that Id run, so do that. Run it in whichever subestate that queryId exists?
- WaitTimes: Implement a backoff algorithm for this as well?





