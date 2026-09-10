# Release History

## [v9.1.0.1006]
> Release Date: 2026-xx-xx
 - [Changed] Gatered additional NSX Manager Node details for management domain

## [v9.1.0.1005]
> Release Date: 2026-06-30
 - [Fixed] L3 Multi-Rack Workload Domain deployments
 - [Fixed] VCF Managment Networks details with Deferred Deployments

## [v9.1.0.1004]
> Release Date: 2026-06-26
 - [Changed] Altered function parameters to better facilitate calls from VMware.PlatformTools module and pipeline testing

## [v9.1.0.1003]
> Release Date: 2026-06-26
- [Changed] Error reporting to be more informative
- [Fixed] Error in 9.1 deferred proxy custom portgroup information scraping
- [Fixed] Allowed for Excel styleid variances in New-NetworkPoolJsonFile
- [Fixed] Conditional logic for scraping storage networks

## [v9.1.0.1002]
> Release Date: 2026-06-24
- [Fixed] Error in 9.1 processing unnecessary gateway_cidrs

## [v9.1.0.1001]
> Release Date: 2026-06-17
- [Fixed] Management CTGW form factor lookup

## [v9.1.0.1000]
> Release Date: 2026-06-12
- [Added] Support for dual P&P Versions
- [Added] Added Day-N Functions for 9.1
- [Added] Added userPromptBypass to functions to support direct calls from PlatformTools
- [Changed] Management Domain JSON function updated to support 9.1

## [v9.0.0.1013]
> Release Date: 2026-03-xx
- [Fixed] WLD Sizing References

## [v9.0.0.1012]
> Release Date: 2026-02-20
- [Added] Ability to bypass interactive questions on New-EdgeJSONFile for automation purposes
- [Changed] Supported P&P File updaated to match current published version

## [v9.0.0.1011]
> Release Date: 2026-02-04
- [Added] Support for onboard change control to increase range of versions the workbook content transfer process can support
- [Added] Ability to transparently handle versions of P&P that do not impact automation
- [Added] Support for LAG in VCF Installer Management Domain Bringup File
- [Changed] Altered logic to handle situations where no excel files are present in folder more elegantly
- [Fixed] Appliance size retrieval from P&P
- [Fixed] References to outdated named cells
- [Fixed] Workload datacenter name for workload domain deployment now calculated vs using Day-N configuration value
- [Fixed] Issue in multi-az host commissioning

## [v9.0.0.1010]
> Release Date: 2025-11-12
- [Added] Support for auto-generated passwords in management domain
- [Fixed] Bug in edge cluster deployment using ip pools for edges
- [Fixed] Edge snat being to true for ACTIVE_ACTIVE clusters
- [Fixed] 9.0.0.0 set as version for Day-N deployments, even when later versions is selected

## [v9.0.0.1009]
> Release Date: 2025-10-10
- [Added] Support for VCF 9.0.1.0
- [Changed] Changed default snat setting for edge json file
- [Changed] Removed unneccessary wsan configuration on windows machine
- [Changed] Supported P&P Workbook version updates to v1.9.0.006
- [Fixed] Not gathering IP Pools spec correctly for management domain JSON
- [Fixed] Not honouring CEIP setting for management domain JSON
- [Fixed] Management domain network pool name now based off of provided domain name rather than internal value

## [v9.0.0.1008]
> Release Date: 2025-09-18
- [Changed] Handle single DNS and NTP server entries for management domain bringup
- [Fixed] FTT not being added in OSA management domains
- [Fixed] vCenter and VCF Operations appliance sizes not being correctly retrieved

## [v9.0.0.1007]
> Release Date: 2025-09-02
- [Fixed] Bug where HA Deployment Model was not being honoured correctly

## [v9.0.0.1006]
> Release Date: 2025-08-21
- [Fixed] Bug where Edge JSON creation for workload domain was keying off management domain choice

## [v9.0.0.1005]
> Release Date: 2025-08-21
- [Changed] Supported P&P Workbook version updates to v1.9.0.005
- [Fixed] Menu items showing as enabled when should be disabled

## [v9.0.0.1004]
> Release Date: 2025-08-13
- [Added] Tested on for Ubuntu, Debian and MacOS. May work with other linux variants, but untested
- [Added] Generation of JSON for Single Operation of Stretched Compute Only Cluster
- [Added] `Set-VCFJsonGenerationPrequisites` cmdlet that installs additional PowerShell Module dependencies
- [Changed] Removed dependency on PowerVCF PowerShell Module
- [Changed] Handling of DVS Datapath mode based on settings in P&P workbook
- [Fixed] VCF Operations Appliance size being populated as `False`

## [v9.0.0.1003]
> Release Date: 2025-xx-xx
- [Changed] Revert Console Title to original value on exit
- [Changed] Display Module vs generic VCF Version

## [v9.0.0.1002]
> Release Date: 2025-07-01
- [Added] Initial Release
