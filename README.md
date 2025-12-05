
# VCF.JSONGenerator

[![PS Version](https://img.shields.io/powershellgallery/v/VCF.JSONGenerator?label=Version)](https://www.powershellgallery.com/packages/VCF.JSONGenerator)
[![PS Downloads](https://img.shields.io/powershellgallery/dt/VCF.JSONGenerator?label=Downloads)](https://www.powershellgallery.com/packages/VCF.JSONGenerator)
[![GitHub Glone](https://img.shields.io/badge/dynamic/json?color=success&label=Clones&query=count&url=https://gist.githubusercontent.com/nathanthaler/cd078a6cd4cc8bbf8bcf859ad2dd4f18/raw/clone.json&logo=github)](https://gist.githubusercontent.com/nathanthaler/cd078a6cd4cc8bbf8bcf859ad2dd4f18/raw/clone.json)
[![License](https://img.shields.io/badge/License-Broadcom-green.svg)](LICENSE.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Changelog](https://img.shields.io/badge/Changelog-Read-blue)](CHANGELOG.md)

## Author

Thank you for your interest in the project. Whether it's a bug report, enhancement, correction, or
additional documentation, I greatly value feedback and contributions from our community.

Name            | Role         | GitHub                                                          |
----------------|--------------|-----------------------------------------------------------------|
Ken Gould       | Creator      | [:fontawesome-brands-github:](https://github.com/feardamhan)    |

## Overview

VCF.JSONGenerator is provided as is, as a companion tool for the VCF 9.0 Planning & Preparation (P&P) workbook. Its intent is to help automate the task of creation JSON payloads for submission to the VCF management components.

## Support Platforms
- Windows (tested with Server 2022 Datacenter edition)
- Ubuntu (tested with 24.02)
- Debian (tested with 11)
- MacOS (tested with 15.5)

## Dependencies
VCF.JSON Generator has the following dependencies
- ImportExcel PowerShell Module
- VMware.PowerCLI or VCF.PowerCLI PowerShell Module

Dependent modules and PowerCLI configuration settings may be configured using the `Set-VCFJsonGenerationPrequisites` cmdlet. This will detect installed modules, and if not present will install them. While VCF.JSONGenerator can leverage either VMware.PowerCLI or VCF.PowerCLI, it will install VCF.PowerCLI if neither are present due to it being the newer version of the module.

## General Use
VCF.JSON Generator creates JSON files by reading data from a populated VCF 9.0 P&P workbook. After installing the module, navigate to the folder containing your P&P workbook(s) and use `Start-VCFJsonGeneration`. Use option 1 to discover and load a P&P workbook. Sections and Options with sections will be dynamically enabled/disabled based on the settings in the chosen file.

Not all configuration options within the P&P workbook are supported yet. They will gradually be included over time.

**_NOTE:_** VCF.JSONGenerator does not automate the pre-requisites for any of the JSON File, nor does it submit the JSON payload to an API endpoint. It is the users responsibility to configure pre-requisites by following the VCF documentation and to submit the JSON to the API in their own desired manner.

## Interactive Mode
In many cases, a fully functional JSON payload requires the inclusion of unique identifiers for items such SDDC Manager object IDS, vCenter and NSX object IDs, or SSH fingerprints. In such cases, the user is asked if they want to retrive these programmatically. If this option is chosen, the user is prompted to provide credentials to the relevant running systems from which IDs need to be retrieved. If interactive mode is not selected, the corresponding files are populated with text in the format '<-- ENTER THE ID OF XXXXXXXXXX -->' to allow the user to retroactively populate those fields prior to submitting the JSON to the relevant VCF API Endpoint.

## Supported & Unsupported Permutations
The following are the list of tested / supported permutations.

### VCF Installer JSON File
- When P&P operation is configured to be `Deploy a new VCF fleet` or `Deploy a VCF Instance in an existing VCF fleet`
- [Supported/Tested]
    - Deploy a new VCF Fleet
    - Simple Deployment Model
    - Highly Available Deployment Model
    - Deployment of VCF Operations and VCF Automation Day-N
    - Deployment of VCF Operations with VCF Autuomation
    - Joining an existing VCF Fleet
    - Deployment of VSAN-OSA and VSAN-ESA based Management Clusters
    - Auto generated passwords
- [Supported/UnTested]
    - Deployment leveraging existing components

### General Features
- Are enabled for all relevant operations
- [Supported/Tested]
    - Network Pool Creation for vSAN HCI Cluster
    - Network Pool Creation for vSAN Storage Cluster with Storage Client Traffic
    - Host Commissioning vSAN HCI
    - Host Commissioning vSAN Storage Cluster with Storage Client Traffic
    - Stretched Cluster (that has been deployed as part of a workload domain or as an additional cluster)
        - [Supported/Tested]
            - Single-Rack / Layer-2 Multi-Rack HCI Cluster
            - Single-Rack / Layer-2 Multi-Rack Storage Cluster
            - Single-Rack / Layer-2 Multi-Rack Compute Only Cluster
        - [Unsupported]
            - Multi-Rack / Layer-2 Multi-Rack HCI Cluster
            - Multi-Rack / Layer-2 Multi-Rack Storage Cluster
            - Multi-Rack / Layer-2 Multi-Rack Compute Only Cluster

### Workload Domains
- First workload domain when P&P Operation is set to `Deploy a new VCF fleet` or `Deploy a VCF Instance in an existing VCF fleet`
- Additional workload domains can be done when P&P Operation is set to `Create VI Workload Domain`
- [Supported/Tested]
    - Workload Domain With Single-Rack / Layer-2 Multi-Rack HCI Cluster
    - Workload Domain With Layer-3 Multi-Rack HCI Cluster
- [Unsupported]
    - Workload Domain With Multi-Rack Compute Only Cluster
    - Workload Domain With Multi-Rack Storage Cluster

### Clusters
- When P&P Operation is set to `Create Cluster`
- Additional vSphere Clusters
    - [Supported/Tested]
        - Single-Rack / Layer-2 Multi-Rack HCI Cluster
        - Single-Rack / Layer-2 Multi-Rack Storage Cluster
        - Single-Rack / Layer-2 Multi-Rack Compute Only Cluster
        - Layer-3 Multi-Rack HCI Cluster
        - Layer-3 Multi-Rack Compute Only Cluster
        - Stretching of existing Single-Rack HCI Cluster
        - Stretching of existing Single-Rack Storage Cluster
        - Stretched Compute Only Cluster in a single operation
    - [Unsupported]
        - Multi-Rack Storage Cluster

### Edge Clusters
- For any domain type
- [Supported/Tested]
    - Centralized Connectivity with BGP
    - IP List / IP Pool / DHCP Edge TEPs Addressing
- [Unsupported]
    - Static Routes
    - Auto generated passwords


### Day-N Fleet Management Deployments
- [Supported/Tested]
    - VCF Identify Broker (Appliance Mode)
    - VCF Operations and Automation (via SDDC Manager Workflow)
        - Simple Deployment Model
        - Highly Available Deployment Model
    - VCF Operations for Logs (via Fleet Manager)
        - Simple Deployment Model
        - Highly Available Deployment Model
    - VCF Operations for Networks (via Fleet Manager)
        - Simple Deployment Model
        - Highly Available Deployment Model
    - All of the above on
        - Shared Management Network
        - Dedicated VLAN network
        - NSX Overlay Network
        - NSX VLAN segment

## Troubleshooting
- There is a very tight coupling between the version of the Planning & Preparation file you use and the version of the VCF.JSONGenerator Powershell Module. Bug resolution may involve a change to either or both of these elements. Please ensure that all required values in the Planning & Preparation workbook are populated in the desired format. In time, depending on the appetite for this module, I may introduce input format validation and cross-checking
