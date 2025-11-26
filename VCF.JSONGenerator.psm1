#1.9.0.005 /1820
#1.9.0.006 /1820
#1.9.0.007 /1821

$Global:version = ((Get-InstalledModule VCF.JSONGenerator).version -as [STRING])
$Global:baseSupportedUserVersion = [INT]("190005")
$Global:supportedAutomationVersion = [INT]("1821")
If ($PSEdition -eq 'Core') {
    #$PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck",$true)
    $Script:PSDefaultParameterValues = @{
        "invoke-restmethod:SkipCertificateCheck" = $true
        "invoke-webrequest:SkipCertificateCheck" = $true
    }
}
else
{
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@

    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

Function Set-VCFJsonGenerationPrequisites
{
    LogMessage -type INFO -message "Trusting PSGallery"
    Set-PSRepository PSGallery -InstallationPolicy Trusted | Out-null       
    
    LogMessage -type INFO -message "Confirming presence of ImportExcel PowerShell Module"
    $importExcelPresent = Get-InstalledModule -name ImportExcel -ErrorAction SilentlyContinue
    If (!($importExcelPresent)) { Install-Module -name ImportExcel -confirm:$false}
    LogMessage -type INFO -message "Confirming presence of VMware.PowerCLI or VCF.PowerCLI PowerShell Module"
    $vmwarePowerCliPresent = Get-InstalledModule -name VMware.PowerCLI -ErrorAction SilentlyContinue
    $vcfPowerCliPresent = Get-InstalledModule -name VCF.PowerCLI -ErrorAction SilentlyContinue
    If ((!($vmwarePowerCliPresent)) -and (!($vcfPowerCliPresent))) {Install-Module -name VCF.PowerCLI -confirm:$false}

    If ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
    {
        LogMessage -type INFO -message "Confirming presence of OpenSSL utility"
        $installedSoftware = Get-InstalledSoftware
        If (!($installedSoftware -match "OpenSSL"))
        {
           LogMessage -Type WARNING -Message "OpenSSL not detected. This will prevent the retrieval of SSH fingerprints in interactive mode"
           LogMessage -Type NOTE -Message "To enable interactive mode, please install OpenSSL and ensure its installation path is added to the system PATH variable"
        }
    }

    LogMessage -type INFO -message "Setting PowerCLI Configuration appropriately"
    Start-Job -ScriptBlock { Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -WarningAction SilentlyContinue -InformationAction SilentlyContinue } *>$null
    Get-Job | Wait-Job | Remove-Job | Out-Null
    Start-Job -ScriptBlock { Set-PowerCLIConfiguration -DisplayDeprecationWarnings $false -Confirm:$false -WarningAction SilentlyContinue -InformationAction SilentlyContinue } *>$null
    Get-Job | Wait-Job | Remove-Job | Out-Null
    Start-Job -ScriptBlock { Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False -WarningAction SilentlyContinue -InformationAction SilentlyContinue } *>$null
    Get-Job | Wait-Job | Remove-Job | Out-Null
    Start-Job -ScriptBlock { Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false -WarningAction SilentlyContinue -InformationAction SilentlyContinue } *>$null
    Get-Job | Wait-Job | Remove-Job | Out-Null
    Start-Job -ScriptBlock { Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -Confirm:$false -WarningAction SilentlyContinue -InformationAction SilentlyContinue } *>$null
    Get-Job | Wait-Job | Remove-Job | Out-Null
}
Export-ModuleMember -function Set-VCFJsonGenerationPrequisites

Function Start-VCFJsonGeneration
{
    # Common Functions
    Function New-JsonGenerationMenu
    {
        $disabledColour = "DarkGray"
        $enabledColour = "White"
        Do {
            Clear-Host
            $headingItem01 = "Load Workbook (Enabled)"
            $menuItem01 = "Choose Planning & Preparation Workbook to use for JSON Generation"
            $menuItem02 = "Transfer contents from older Planning & Preparation Workbook to current version"

            $menuItem10 = "Management Domain JSON for use in VCF Installer"
            If ($managementObject)
            {
                $headingItem02 = "Management Domain JSON Generation (Enabled)"
                $managementMenuItemColour = $enabledColour
                
                If ($managementObject.stretchCluster.required)
                {
                    If ($managementObject.networkPoolCreationRequired -eq $false)
                    {
                        $menuItem11 = "Network Pool for AZ2 (Disabled: Pool not required)"
                        $managementMenuNetworkPoolColour = $disabledColour
                    }
                    else
                    {
                        $menuItem11 = "Network Pool for AZ2"
                        $managementMenuNetworkPoolColour = $enabledColour
                    }
                    $menuItem12 = "Commission AZ2 Hosts"
                    $menuItem13 = "Stretch Initial Cluster"
                    $managementMenuStretchedClusterColour = $enabledColour
                }
                else
                {
                    $menuItem11 = "Network Pool for AZ2 (Disabled: Pool not required)"
                    $menuItem12 = "Commission AZ2 Hosts (Disabled: Stretch cluster not selected)"
                    $menuItem13 = "Stretch Initial Cluster (Disabled: Stretch cluster not selected)"
                    $managementMenuNetworkPoolColour = $disabledColour
                    $managementMenuStretchedClusterColour = $disabledColour
                }
                If ($managementObject.edgeCluster)
                {
                    $menuItem14 = "Edge Cluster"
                    $managementMenuEdgeClusterColour = $enabledColour    
                }
                else
                {
                    $menuItem14 = "Edge Cluster (Disabled: Edges not required)"
                    $managementMenuEdgeClusterColour = $disabledColour
                }
            }
            else
            {
                $headingItem02 = "Management Domain JSON Generation (Disabled: Not applicable based on loaded workbook)"
                $managementMenuItemColour = $disabledColour
                $menuItem11 = "Network Pool for AZ2"
                $managementMenuNetworkPoolColour = $disabledColour
                $menuItem12 = "Commission AZ2 Hosts"
                $managementMenuStretchedClusterColour = $disabledColour
                $menuItem13 = "Stretch Initial Cluster"
                $managementMenuStretchedClusterColour = $disabledColour
                $menuItem14 = "Edge Cluster"
                $managementMenuEdgeClusterColour = $disabledColour
            }

            If ($workloadObject)
            {
                $headingItem03 = "Workload Domain JSON Generation (Enabled)"
                $workloadMenuItemColour = $enabledColour
                If ($workloadObject.networkPoolCreationRequired -eq $false)
                {
                    $menuItem20 = "Network Pool (Disabled: Pool not required)"
                }
                else
                {
                    $menuItem20 = "Network Pool"
                }
                $menuItem21 = "Commission Hosts"

                If ($workloadObject.stretchCluster.required)
                {
                    if ($workloadObject.rackInformation.multiRackChosen -eq "Y")
                    {
                        $menuItem23 = "Stretch Initial Cluster (Disabled: Not supported with Multi-Rack cluster)"
                        $workloadMenuStretchedClusterColour = $disabledColour
                    }
                    else
                    {
                        $menuItem23 = "Stretch Initial Cluster"
                        $workloadMenuStretchedClusterColour = $enabledColour
                    }
                }
                else
                {
                    $menuItem23 = "Stretch Initial Cluster (Disabled: Stretch cluster not selected)"
                    $workloadMenuStretchedClusterColour = $disabledColour
                }
                If ($workloadObject.edgecluster)
                {
                    $menuItem24 = "Edge Cluster"
                    $workloadMenuEdgeClusterColour = $enabledColour    
                }
                else
                {
                       $menuItem24 = "Edge Cluster"
                       $workloadMenuEdgeClusterColour = $disabledColour
                }
            }
            else
            {
                $headingItem03 = "Workload Domain JSON Generation (Disabled: Not applicable based on loaded workbook)"
                $workloadMenuItemColour = $disabledColour
                $workloadMenuStretchedClusterColour = $disabledColour
                $workloadMenuEdgeClusterColour = $disabledColour
                $menuItem20 = "Network Pool"
                $menuItem21 = "Commission Hosts"
                $menuItem22 = "Workload Domain JSON for use in SDDC Manager"
                $menuItem23 = "Stretch Initial Cluster"
                $menuItem24 = "Edge Cluster"
            }
            
            If ($clusterObject)
            {
                $headingItem04 = "Cluster Creation JSON Generation (Enabled)"
                #Network Pool Option
                If ($clusterObject.networkPoolCreationRequired -eq $false)
                {
                    $menuItem30 = "Network Pool (Disabled: Pool reuse selected)"
                    $clusterMenuNetworkPoolColour = $disabledColour
                }
                else
                {
                    $menuItem30 = "Network Pool"
                    $clusterMenuNetworkPoolColour = $enabledColour
                }
                #Cluster Options
                If ($clusterObject.determinedClusterConfig -eq "Single-Rack HCI")
                {
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem34 = "Single-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    $menuItem35 = "Multi-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    If ($clusterObject.stretchCluster.required)
                    {
                        $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster"
                        $clusterMenuStretchedColour = $enabledColour
                    }
                    else
                    {
                        $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster (Disabled: Not applicable based on loaded workbook)"
                        $clusterMenuStretchedColour = $disabledColour
                    }
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $enabledColour
                    $clusterMenuSingleRackStorageColour = $disabledColour
                    $clusterMenuSingleRackComputeColour = $disabledColour
                    $clusterMenuMultiRackHCIColour = $disabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $disabledColour
                }
                elseif ($clusterObject.determinedClusterConfig -eq "Single-Rack vSAN Storage")
                {
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster"
                    $menuItem34 = "Single-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook (Future)"
                    $menuItem35 = "Multi-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    If ($clusterObject.stretchCluster.required)
                    {
                        $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster"
                        $clusterMenuStretchedColour = $enabledColour
                    }
                    else
                    {
                        $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster (Disabled: Not applicable based on loaded workbook)"
                        $clusterMenuStretchedColour = $disabledColour    
                    }
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $disabledColour
                    $clusterMenuSingleRackStorageColour = $enabledColour
                    $clusterMenuSingleRackComputeColour = $disabledColour
                    $clusterMenuMultiRackHCIColour = $disabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $disabledColour
                }
                elseIf ($clusterObject.determinedClusterConfig -eq "Single-Rack Compute Only")
                {
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem34 = "Single-Rack Compute Only Cluster"
                    $menuItem35 = "Multi-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster (Disabled: Not Supported)"
                    $clusterMenuStretchedColour = $disabledColour
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $disabledColour
                    $clusterMenuSingleRackStorageColour = $disabledColour
                    $clusterMenuSingleRackComputeColour = $enabledColour
                    $clusterMenuMultiRackHCIColour = $disabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $disabledColour
                }
                elseIf ($clusterObject.determinedClusterConfig -eq "Stretched Compute Only")
                {
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem34 = "Single-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem35 = "Multi-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    $menuItem38 = "Single Operation $($clusterObject.determinedClusterConfig) Cluster"
                    $clusterMenuStretchedColour = $enabledColour
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $disabledColour
                    $clusterMenuSingleRackStorageColour = $disabledColour
                    $clusterMenuSingleRackComputeColour = $disabledColour
                    $clusterMenuMultiRackHCIColour = $disabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $disabledColour
                }
                elseIf ($clusterObject.determinedClusterConfig -eq "Multi-Rack HCI")
                { 
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem34 = "Single-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem35 = "Multi-Rack HCI Cluster"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster (Disabled: Not supported)"
                    $clusterMenuStretchedColour = $disabledColour
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $disabledColour
                    $clusterMenuSingleRackStorageColour = $disabledColour
                    $clusterMenuSingleRackComputeColour = $disabledColour
                    $clusterMenuMultiRackHCIColour = $enabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $disabledColour
                }
                elseif ($clusterObject.determinedClusterConfig -eq "Multi-Rack vSAN Storage")
                {
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem34 = "Single-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem35 = "Multi-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook) (Future)"
                    $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster (Disabled: Not supported)"
                    $clusterMenuStretchedColour = $disabledColour
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $disabledColour
                    $clusterMenuSingleRackStorageColour = $disabledColour
                    $clusterMenuSingleRackComputeColour = $disabledColour
                    $clusterMenuMultiRackHCIColour = $disabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $disabledColour
                }
                elseIf ($clusterObject.determinedClusterConfig -eq "Multi-Rack Compute Only")
                {
                    $menuItem31 = "Commission Hosts"
                    $menuItem32 = "Single-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem33 = "Single-Rack vSAN Storage Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem34 = "Single-Rack Compute Only Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem35 = "Multi-Rack HCI Cluster (Disabled: Not applicable based on loaded workbook)"
                    $menuItem36 = "Multi-Rack vSAN Storage Cluster (Disabled: Not supported)"
                    $menuItem37 = "Multi-Rack Compute Only Cluster"
                    $menuItem38 = "Stretch $($clusterObject.determinedClusterConfig) Cluster (Disabled: Not supported)"
                    $clusterMenuStretchedColour = $disabledColour
                    $clusterMenuCommissionHostsColour = $enabledColour
                    $clusterMenuSingleRackHCIColour = $disabledColour
                    $clusterMenuSingleRackStorageColour = $disabledColour
                    $clusterMenuSingleRackComputeColour = $disabledColour
                    $clusterMenuMultiRackHCIColour = $disabledColour
                    $clusterMenuMultiRackStorageColour = $disabledColour
                    $clusterMenuMultiRackComputeColour = $enabledColour
                }
            }
            else
            {
                $headingItem04 = "Cluster Creation JSON Generation (Disabled: Not applicable based on loaded workbook)"
                $menuItem30 = "Network Pool"
                $menuItem31 = "Commission Hosts"
                $menuItem32 = "Single-Rack HCI Cluster"
                $menuItem33 = "Single-Rack vSAN Storage Cluster"
                $menuItem34 = "Single-Rack Compute Only Cluster"
                $menuItem35 = "Multi-Rack HCI Cluster"
                $menuItem36 = "Multi-Rack vSAN Storage Cluster"
                $menuItem37 = "Multi-Rack Compute Only Cluster"
                $menuItem38 = "Stretch Cluster"
                $clusterMenuNetworkPoolColour = $disabledColour
                $clusterMenuCommissionHostsColour = $disabledColour
                $clusterMenuSingleRackHCIColour = $disabledColour
                $clusterMenuSingleRackStorageColour = $disabledColour
                $clusterMenuSingleRackComputeColour = $disabledColour
                $clusterMenuMultiRackHCIColour = $disabledColour
                $clusterMenuMultiRackStorageColour = $disabledColour
                $clusterMenuMultiRackComputeColour = $disabledColour
                $clusterMenuStretchedColour = $disabledColour
            }

            $headingItem05 = "Additional Components JSON Generation"
            
            If ($workbookProfile.opsAutomationDayNDeployment -eq "Selected")
            {
                $menuItem40 = "VCF Operations and Automation Post Bringup"
                $opsAndAutomationDayNColour = $enabledColour
            }
            elseif ($workbookProfile.opsAutomationDayNDeployment -eq "Unselected")
            {
                $menuItem40 = "VCF Operations and Automation Post Bringup (Disabled: Not applicable based on loaded workbook)"
                $opsAndAutomationDayNColour = $disabledColour
            }
            else 
            {
                $menuItem40 = "VCF Operations and Automation Post Bringup"
                $opsAndAutomationDayNColour = $disabledColour
            }

            If ($workbookProfile.logsDayNDeployment -eq "Include")
            {
                $menuItem41 = "VCF Operations for Logs"
                $logsDayNColour = $enabledColour
            }
            elseif ($workbookProfile.logsDayNDeployment -eq "Exclude")
            {
                $menuItem41 = "VCF Operations for Logs (Disabled: Not applicable based on loaded workbook)"
                $logsDayNColour = $disabledColour
            }
            else
            {
                $menuItem41 = "VCF Operations for Logs"
                $logsDayNColour = $disabledColour
            }

            If ($workbookProfile.networksDayNDeployment -eq "Include")
            {
                $menuItem42 = "VCF Operations for Networks"
                $networksDayNColour = $enabledColour
            }
            elseif ($workbookProfile.networksDayNDeployment -eq "Exclude")
            {
                $menuItem42 = "VCF Operations for Networks (Disabled: Not applicable based on loaded workbook)"
                $networksDayNColour = $disabledColour
            }
            else
            {
                $menuItem42 = "VCF Operations for Networks"
                $networksDayNColour = $disabledColour
            }

            If ($workbookProfile.idbDayNDeployment -eq "Identity Broker Appliance")
            {
                $menuItem43 = "VCF Identity Broker Appliance"
                $idbDayNColour = $enabledColour
            }
            elseif ($workbookProfile.idbDayNDeployment -in "Identity Broker (Embedded)","Exclude")
            {
                $menuItem43 = "VCF Identity Broker Appliance (Disabled: Not applicable based on loaded workbook)"
                $idbDayNColour = $disabledColour
            }
            else
            {
                $menuItem43 = "VCF Identity Broker Appliance"
                $idbDayNColour = $disabledColour
            }
            
            If ($workbookProfile) 
            {
                $specificationText = $workbookProfile.deploymentSpecification
                $instanceText = $workbookProfile.instance
                $operationText = $workbookProfile.granularOperation
                $workbookText = $workbookProfile.chosenWorkBook
            }
            else
            {
                $specificationText = "None"
                $instanceText =  "None"
                $operationText =  "None"
                $workbookText =  "None"
            }

            Write-Host ""; Write-Host " VCF JSON Generator Utility ($version)" -ForegroundColor Yellow
            Write-Host " *************************************** " -ForegroundColor Yellow
            Write-Host " Workbook Loaded: " -nonewline -ForegroundColor Cyan
            Write-Host "$workbookText" -ForegroundColor Green
            Write-Host " Deployment Specification: " -nonewline -ForegroundColor Cyan
            Write-Host "$specificationText" -nonewline -ForegroundColor Green
            Write-Host " | Instance: " -nonewline -ForegroundColor Cyan
            Write-Host "$instanceText"  -nonewline -ForegroundColor Green
            Write-Host " | Operation: " -nonewline -ForegroundColor Cyan
            Write-Host "$operationText" -ForegroundColor Green
            
            Write-Host ""; Write-Host -Object " $headingItem01" -ForegroundColor Yellow
            Write-Host -Object " 01. $menuItem01" -ForegroundColor White
            Write-Host -Object " 02. $menuItem02" -ForegroundColor White
            
            Write-Host ""; Write-Host -Object " $headingItem02" -ForegroundColor Yellow
            Write-Host -Object " 10. $menuItem10" -ForegroundColor $managementMenuItemColour
            Write-Host -Object " 11. $menuItem11" -ForegroundColor $managementMenuNetworkPoolColour
            Write-Host -Object " 12. $menuItem12" -ForegroundColor $managementMenuStretchedClusterColour
            Write-Host -Object " 13. $menuItem13" -ForegroundColor $managementMenuStretchedClusterColour
            Write-Host -Object " 14. $menuItem14" -ForegroundColor $managementMenuEdgeClusterColour
            
            Write-Host ""; Write-Host -Object " $headingItem03" -ForegroundColor Yellow
            Write-Host -Object " 20. $menuItem20" -ForegroundColor $workloadMenuItemColour
            Write-Host -Object " 21. $menuItem21" -ForegroundColor $workloadMenuItemColour
            Write-Host -Object " 22. $menuItem22" -ForegroundColor $workloadMenuItemColour
            Write-Host -Object " 23. $menuItem23" -ForegroundColor $workloadMenuStretchedClusterColour
            Write-Host -Object " 24. $menuItem24" -ForegroundColor $workloadMenuEdgeClusterColour

            Write-Host ""; Write-Host -Object " $headingItem04" -ForegroundColor Yellow
            Write-Host -Object " 30. $menuItem30" -ForegroundColor $clusterMenuNetworkPoolColour
            Write-Host -Object " 31. $menuItem31" -ForegroundColor $clusterMenuCommissionHostsColour
            Write-Host -Object " 32. $menuItem32" -ForegroundColor $clusterMenuSingleRackHCIColour
            Write-Host -Object " 33. $menuItem33" -ForegroundColor $clusterMenuSingleRackStorageColour
            Write-Host -Object " 34. $menuItem34" -ForegroundColor $clusterMenuSingleRackComputeColour
            Write-Host -Object " 35. $menuItem35" -ForegroundColor $clusterMenuMultiRackHCIColour
            Write-Host -Object " 36. $menuItem36" -ForegroundColor $clusterMenuMultiRackStorageColour
            Write-Host -Object " 37. $menuItem37" -ForegroundColor $clusterMenuMultiRackComputeColour
            Write-Host -Object " 38. $menuItem38" -ForegroundColor $clusterMenuStretchedColour
            
            Write-Host ""; Write-Host -Object " $headingItem05" -ForegroundColor Yellow
            Write-Host -Object " 40. $menuItem40" -ForegroundColor $opsAndAutomationDayNColour
            Write-Host -Object " 41. $menuItem41" -ForegroundColor $logsDayNColour
            Write-Host -Object " 42. $menuItem42" -ForegroundColor $networksDayNColour
            Write-Host -Object " 43. $menuItem43" -ForegroundColor $idbDayNColour
            
            Write-Host -Object ''
            $MenuInput = Read-Host -Prompt ' Select Option (or Q to go Quit)'
            $MenuInput = $MenuInput -replace "`t|`n|`r",""
            If ($MenuInput -like "0*") {$MenuInput = ($MenuInput -split("0"),2)[1]}
            Switch ($MenuInput)
            {
                1 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > Load Planning & Preparation Workbook  > $menuItem01" -Foregroundcolor Cyan; Write-Host -Object ''
                    Show-PnPFilesInFolder
                    Get-PnPInputFileInputs
                    anykey
                }
                2 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > Load Planning & Preparation Workbook  > $menuItem02" -Foregroundcolor Cyan; Write-Host -Object ''
                    New-TransferExcelContents
                    anykey
                }
                10 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem10" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($managementObject -and $sharedInstanceObject)
                    {
                        New-ManagementDomainJsonFile -instanceObject $managementObject -sharedInstanceObject $sharedInstanceObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                11 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem11" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($managementObject)
                    {
                        New-NetworkPoolJsonFile -instanceObject $managementObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                12 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem12" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($managementObject)
                    {
                        New-RackBasedHostCommissioning -instanceObject $managementObject -az "az2"
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                13
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem13" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($managementObject) -and ($managementObject.stretchCluster.required))
                    {
                        New-StretchedClusterJsonFile -instanceObject $managementObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                14
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem14" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($managementObject.edgecluster)
                    {
                        New-EdgeJSONFile -instanceObject $managementObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                20 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem20" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($workloadObject)
                    {
                        New-NetworkPoolJsonFile -instanceObject $workloadObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                21 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem21" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($workloadObject)
                    {
                        New-RackBasedHostCommissioning -instanceObject $workloadObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                22 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem22" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($workloadObject)
                    {
                        New-WorkloadDomainJsonFile -instanceObject $workloadObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                23
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem23" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($workloadObject) -and ($workloadObject.stretchCluster.required))
                    {
                        New-StretchedClusterJsonFile -instanceObject $workloadObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                24
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem24" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($workloadObject.edgecluster)
                    {
                        New-EdgeJSONFile -instanceObject $workloadObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                30 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem30" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.networkPoolCreationRequired -eq $true)
                    {
                        New-NetworkPoolJsonFile -instanceObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                31 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem31" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject)
                    {
                        New-RackBasedHostCommissioning -instanceObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                32 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem32" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.determinedClusterConfig -eq "Single-Rack HCI")
                    {
                        New-L2vSphereClusterJsonFile -clusterObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                33 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem33" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.determinedClusterConfig -eq "Single-Rack vSAN Storage")
                    {
                        New-L2vSphereClusterJsonFile -clusterObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                34 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem34" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.determinedClusterConfig -eq "Single-Rack Compute Only")
                    {
                        New-L2vSphereClusterJsonFile -clusterObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                35 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem35" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.determinedClusterConfig -eq "Multi-Rack HCI")
                    {
                        New-L3vSphereClusterJsonFile -clusterObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                <# 36 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem36" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.determinedClusterConfig -eq "Multi-Rack vSAN Storage")
                    {
                        New-L3vSphereClusterJsonFile -clusterObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                } #>
                37 {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem37" -Foregroundcolor Cyan; Write-Host -Object ''
                    If ($clusterObject.determinedClusterConfig -eq "Multi-Rack Compute Only")
                    {
                        New-L3vSphereClusterJsonFile -clusterObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                38
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem38" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($clusterObject) -and ($($clusterObject.determinedClusterConfig -eq "Stretched Compute Only")))
                    {
                        New-SingleOperationStretchedComputeClusterJsonFile -clusterObject $clusterObject
                    }
                    elseIf (($clusterObject) -and ($clusterObject.stretchCluster.required) -and ($($clusterObject.determinedClusterConfig -notlike "Multi*")))
                    {
                        New-StretchedClusterJsonFile -instanceObject $clusterObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                40
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem40" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($sharedInstanceObject) -and ($workbookProfile.opsAutomationDayNDeployment -eq "Selected"))
                    {
                        New-DayNOpsAndAutomationJsonFile -sharedInstanceObject $sharedInstanceObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                41
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem41" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($sharedInstanceObject) -and ($workbookProfile.logsDayNDeployment -eq "Include"))
                    {
                        New-DayNLogsJsonFile -sharedInstanceObject $sharedInstanceObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                42
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem42" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($sharedInstanceObject) -and ($workbookProfile.networksDayNDeployment -eq "Include"))
                    {
                        New-DayNNetworksJsonFile -sharedInstanceObject $sharedInstanceObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }
                43
                {
                    Clear-Host; Write-Host `n " Version $utilityBuild > VCF JSON File Generation > $menuItem43" -Foregroundcolor Cyan; Write-Host -Object ''
                    If (($sharedInstanceObject) -and ($workbookProfile.idbDayNDeployment -eq "Identity Broker Appliance"))
                    {
                        New-DayNIdbJsonFile -sharedInstanceObject $sharedInstanceObject
                    }
                    else
                    {
                        LogMessage -type ERROR -message "Please load a relevant Planning & Preparation Workbook and try again"
                    }
                    anykey
                }

                Q {
                    $Host.UI.RawUI.WindowTitle = $Global:originalWindowTitle
                    Break
                }
            }
        }
        Until ($MenuInput -eq 'Q')
    }

    #Execute
    Clear-Host
    If ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
    {
        Set-ConsoleParameters
    }
    Remove-Variable workbookProfile -scope Global -ErrorAction SilentlyContinue
    Remove-Variable chosenWorkBook -scope Global -ErrorAction SilentlyContinue
    Remove-Variable sharedInstanceObject -scope Global -ErrorAction SilentlyContinue
    Remove-Variable managementObject -scope Global -ErrorAction SilentlyContinue
    Remove-Variable workloadObject -scope Global -ErrorAction SilentlyContinue
    Remove-Variable clusterObject -scope Global -ErrorAction SilentlyContinue
    New-JsonGenerationMenu
}
Export-ModuleMember -function Start-VCFJsonGeneration

Function Set-ConsoleParameters
{
    $ErrorActionPreference = "Stop"
    #Set-Item wsman:\localhost\client\trustedhosts * -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Change size, buffer and Background
        If ($Env:OS = "Windows_NT")
        {
        #ideal dimensions
        $Height = 60
        $Width = 190

        $console = $host.ui.rawui
        $ConBuffer  = $console.BufferSize
        $ConSize = $console.WindowSize
        
        $currWidth = $ConSize.Width
        $currHeight = $ConSize.Height
        
        # if height is too large, set to max allowed size
        if ($Height -gt $host.UI.RawUI.MaxPhysicalWindowSize.Height) {
            $Height = $host.UI.RawUI.MaxPhysicalWindowSize.Height
        }
        
        # if width is too large, set to max allowed size
        if ($Width -gt $host.UI.RawUI.MaxPhysicalWindowSize.Width) {
            $Width = $host.UI.RawUI.MaxPhysicalWindowSize.Width
        }
        
        # If the Buffer is wider than the new console setting, first reduce the width
        If ($ConBuffer.Width -gt $Width ) {
        $currWidth = $Width
        }
        # If the Buffer is higher than the new console setting, first reduce the height
        If ($ConBuffer.Height -gt $Height ) {
            $currHeight = $Height
        }
        # initial resizing if needed
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.size($currWidth,$currHeight)
        
        # Set the Buffer
        $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.size($Width,2000)
        
        # Now set the WindowSize
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.size($Width,$Height)

        $ConColour = $Console.BackgroundColor
        $Console.BackgroundColor = "Black"
        $Global:originalWindowTitle = $Host.UI.RawUI.WindowTitle
        $Host.UI.RawUI.WindowTitle = "VCF JSON Generator Utility $version"
        }
}

Function anyKey
{
    Write-Host ''; Write-Host -Object ' Press any key to continue/return to menu...' -ForegroundColor Yellow; Write-Host '';
    If ($headlessPassed){
        $response = if (!$clioptions) { Read-Host } else { "" }
    } else {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}

Function LogMessage
{
    Param (
        [Parameter (Mandatory = $true)] [AllowEmptyString()] [String]$message,
        [Parameter (Mandatory = $false)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION","ADVISORY","NOTE","QUESTION","WAIT")] [String]$type = "INFO",
        [Parameter (Mandatory = $false)] [String]$colour,
        [Parameter (Mandatory = $false)] [Switch]$skipnewline
    )

    If (!$colour) {
        $colour = "92m" #Green
    }

    If ($type -eq "INFO")
    {
        $messageColour = "92m" #Green
    }
    elseIf ($type -in "ERROR","EXCEPTION")
    {
        $messageColour = "91m" # Red
    }
    elseIf ($type -in "WARNING","ADVISORY","QUESTION")
    {
        $messageColour = "93m" #Yellow
    }
    elseIf ($type -in "NOTE","WAIT")
    {
        $messageColour = "97m" # White
    }

    If (!$threadTag) {$threadTag = "..."; $threadColour = "97m"}

    $ESC = [char]0x1b
    $timestampColour = "97m"

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    $threadTag = $threadTag.toUpper()
    If ($skipnewline)
    {
        Write-Host -NoNewline "$ESC[${timestampcolour} [$timestamp]$ESC[${threadColour} [$threadTag]$ESC[${messageColour} [$type] $message$ESC[0m"
    }
    else
    {
        Write-Host "$ESC[${timestampcolour} [$timestamp]$ESC[${threadColour} [$threadTag]$ESC[${messageColour} [$type] $message$ESC[0m"
    }
}

Function catchWriter
{
    Param (
        [Parameter (mandatory = $true)] [PSObject]$object
    )
    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    LogMessage -Type EXCEPTION -Message "Error at Script Line $lineNumber"
    LogMessage -Type EXCEPTION -Message "Relevant Command: $lineText"
    LogMessage -Type EXCEPTION -Message "Error Message: $errorMessage"
}

Function Get-InstalledSoftware
{
    $software = @()
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env:COMPUTERNAME)
    $apps = $reg.OpenSubKey("SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall").GetSubKeyNames()
    foreach ($app in $apps) {
        $program = $reg.OpenSubKey("SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$app")
        $name = $program.GetValue('DisplayName')
        $software += $name
    }
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env:COMPUTERNAME)
    $apps = $reg.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall").GetSubKeyNames()
    foreach ($app in $apps) {
        $program = $reg.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$app")
        $name = $program.GetValue('DisplayName')
        $software += $name
    }
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('CurrentUser', $env:COMPUTERNAME)
    $apps = $reg.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall").GetSubKeyNames()
    foreach ($app in $apps) {
        $program = $reg.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$app")
        $name = $program.GetValue('DisplayName')
        $software += $name
    }
    Return $software
}

Function Get-VCFHostDetails {
    [CmdletBinding(DefaultParametersetname = "Default")]

    Param (
        [Parameter (Mandatory = $false, ParameterSetName = "fqdn")] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false, ParameterSetName = "status")] [ValidateSet('ASSIGNED', 'UNASSIGNED_USEABLE', 'UNASSIGNED_UNUSEABLE', IgnoreCase = $false)] [String]$Status,
        [Parameter (Mandatory = $false, ParameterSetName = "id")] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        New-VCFBearerAuthHeader # Set the Accept and Authorization headers.
        $uri = "https://$sddcManager/v1/hosts"

        Switch ( $PSCmdlet.ParameterSetName ) {
            "id" {
                # Add id to uri.
                $uri += "/$id"
            }
            "status" {
                # Add status to uri.
                $uri += "?status=$status"
            }
        }

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers

        Switch ( $PSCmdlet.ParameterSetName ) {
            "id" {
                # When there is an id, it is directly the response.
                $response
            }
            "fqdn" {
                # When there is an fqdn, we need to filter the response.
                $response.elements | Where-Object { $_.fqdn -eq $fqdn }
            }
            Default {
                $response.elements
            }
        }
    } Catch {
        ResponseException -object $_
    }
}

Function Get-VCFNetworkPoolDetails {
    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$name,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        New-VCFBearerAuthHeader # Set the Accept and Authorization headers.
        if ( -not $PsBoundParameters.ContainsKey("name") -and ( -not $PsBoundParameters.ContainsKey("id"))) {
            $uri = "https://$sddcManager/v1/network-pools"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response.elements
        }
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$sddcManager/v1/network-pools/$id"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response
        }
        if ($PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$sddcManager/v1/network-pools"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response.elements | Where-Object { $_.name -eq $name }
        }
    } Catch {
        ResponseException -object $_
    }
}

Function Get-VCFPersonalityDetails {
    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        New-VCFBearerAuthHeader # Set the Accept and Authorization headers.
        if ( -not $PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$sddcManager/v1/personalities"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response.elements
        }
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$sddcManager/v1/personalities/$id"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response
        }
    } Catch {
        ResponseException -object $_
    }
}

Function Get-VCFWorkloadDomainDetails {

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$name,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$endpoints
    )

    Try {
        New-VCFBearerAuthHeader # Set the Accept and Authorization headers.
        if ($PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$sddcManager/v1/domains"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response.elements | Where-Object { $_.name -eq $name }
        }
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$sddcManager/v1/domains/$id"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response
        }
        if ( -not $PsBoundParameters.ContainsKey("name") -and ( -not $PsBoundParameters.ContainsKey("id"))) {
            $uri = "https://$sddcManager/v1/domains"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response.elements
        }
        if ( $PsBoundParameters.ContainsKey("id") -and ( $PsBoundParameters.ContainsKey("endpoints"))) {
            $uri = "https://$sddcManager/v1/domains/$id/endpoints"
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            $response.elements
        }
    } Catch {
        ResponseException -object $_
    }
}

Function New-VCFToken {
    
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$skipCertificateCheck
    )

    if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        $creds = Get-Credential # Request Credentials
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }

    if ($PsBoundParameters.ContainsKey("skipCertificateCheck")) {
        if (-not("placeholder" -as [type])) {
            add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Placeholder {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Placeholder.ReturnTrue);
    }
}
"@
}
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [placeholder]::GetDelegate()
    }

    $Global:sddcManager = $fqdn
    $headers = @{"Content-Type" = "application/json" }
    $uri = "https://$sddcManager/v1/tokens" # Set URI for executing an API call to validate authentication
    $body = '{"username": "' + $username + '","password": "' + $password + '"}'

    Try {
        # Checking authentication with SDDC Manager
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck # PS Core has -SkipCertificateCheck implemented
            $Global:accessToken = $response.accessToken
            $Global:refreshToken = $response.refreshToken.id
        } else {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body
            $Global:accessToken = $response.accessToken
            $Global:refreshToken = $response.refreshToken.id
        }
        if ($response.accessToken) {
            Write-Output "Successfully Requested New API Token From SDDC Manager: $sddcManager"
        }
    } Catch {
        ResponseException -object $_
    }
}

Function Filter-X509()
{
    begin
    {
        $doOutput = $false
    }
    process
    {
        if ( $_.Contains("-----BEGIN CERTIFICATE-----") )
        {
            $doOutput = $true
        }
        if ($doOutput)
        {
            Write-Output $_
        }
        if ( $_.Contains("-----END CERTIFICATE-----") )
        {
            $doOutput = $false
        }
    }
    end
    {
        if ($doOutput)
        {
            throw "still printing certificate"
        }
    }
}

Function cidrToMask 
{
    Param (
        [Parameter (Mandatory = $true)] [String]$cidr
    )

    $subnetMasks = @(
        ($32 = @{ cidr = "32"; mask = "255.255.255.255" }),
        ($31 = @{ cidr = "31"; mask = "255.255.255.254" }),
        ($30 = @{ cidr = "30"; mask = "255.255.255.252" }),
        ($29 = @{ cidr = "29"; mask = "255.255.255.248" }),
        ($28 = @{ cidr = "28"; mask = "255.255.255.240" }),
        ($27 = @{ cidr = "27"; mask = "255.255.255.224" }),
        ($26 = @{ cidr = "26"; mask = "255.255.255.192" }),
        ($25 = @{ cidr = "25"; mask = "255.255.255.128" }),
        ($24 = @{ cidr = "24"; mask = "255.255.255.0" }),
        ($23 = @{ cidr = "23"; mask = "255.255.254.0" }),
        ($22 = @{ cidr = "22"; mask = "255.255.252.0" }),
        ($21 = @{ cidr = "21"; mask = "255.255.248.0" }),
        ($20 = @{ cidr = "20"; mask = "255.255.240.0" }),
        ($19 = @{ cidr = "19"; mask = "255.255.224.0" }),
        ($18 = @{ cidr = "18"; mask = "255.255.192.0" }),
        ($17 = @{ cidr = "17"; mask = "255.255.128.0" }),
        ($16 = @{ cidr = "16"; mask = "255.255.0.0" }),
        ($15 = @{ cidr = "15"; mask = "255.254.0.0" }),
        ($14 = @{ cidr = "14"; mask = "255.252.0.0" }),
        ($13 = @{ cidr = "13"; mask = "255.248.0.0" }),
        ($12 = @{ cidr = "12"; mask = "255.240.0.0" }),
        ($11 = @{ cidr = "11"; mask = "255.224.0.0" }),
        ($10 = @{ cidr = "10"; mask = "255.192.0.0" }),
        ($9 = @{ cidr = "9"; mask = "255.128.0.0" }),
        ($8 = @{ cidr = "8"; mask = "255.0.0.0" }),
        ($7 = @{ cidr = "7"; mask = "254.0.0.0" }),
        ($6 = @{ cidr = "6"; mask = "252.0.0.0" }),
        ($5 = @{ cidr = "5"; mask = "248.0.0.0" }),
        ($4 = @{ cidr = "4"; mask = "240.0.0.0" }),
        ($3 = @{ cidr = "3"; mask = "224.0.0.0" }),
        ($2 = @{ cidr = "2"; mask = "192.0.0.0" }),
        ($1 = @{ cidr = "1"; mask = "128.0.0.0" }),
        ($0 = @{ cidr = "0"; mask = "0.0.0.0" })
    )
    $foundMask = $subnetMasks | Where-Object { $_.'cidr' -eq $cidr }
    Return $foundMask.mask
}

Function New-RackDisplayObject
{
    Param (
        [Parameter (mandatory = $true)] [Array]$instanceObject,
        [Parameter (Mandatory = $false)] [String]$az
    )
    $rackArray = @(($instanceObject.$($az) | get-member -type NoteProperty).name)
    $rackDisplayObject=@()
    $rackIndex = 1
    $rackDisplayObject += [pscustomobject]@{
            'id'    = "ID"
            'name' = "Rack"
        }
    $rackDisplayObject += [pscustomobject]@{
            'id'    = "--"
            'name' = "------"
        }
    Foreach ($rackInstance in $rackArray)
    {
        $rackDisplayObject += [pscustomobject]@{
            'id'    = $rackIndex
            'name' = $rackInstance
        }
        $rackIndex++
    }
    Return $rackDisplayObject
}

Function New-BasicAuthHeader
{
    Param(
    [Parameter (Mandatory=$true)]
    [String] $username,
    [Parameter (Mandatory=$true)]
    [String] $password
    )
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password))) # Create Basic Authentication Encoded Credentials
    $headers = @{"Accept" = "application/json"}
    $headers.Add("Authorization", "Basic $base64AuthInfo")
    
    Return $headers
}

Function New-VCFBearerAuthHeader {
    $Global:headers = @{"Accept" = "application/json" }
    $Global:headers.Add("Authorization", "Bearer $accessToken")
}

Function Get-NsxTransportZones {
    Param (
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtUsername,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtPassword,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtManagerFqdn
    )

        $headers = New-BasicAuthHeader -username $nsxtUsername -password $nsxtPassword

        #Get Transport Zones
        Try{
            $uri="https://$nsxtManagerFqdn/policy/api/v1/infra/sites/default/enforcement-points/default/transport-zones"
            $transportZones = (Invoke-WebRequest -Method GET -URI $uri -ContentType application/json -headers $headers).content | ConvertFrom-Json
            Return $transportZones.results
        }
        Catch {
            catchwriter -object $_
        }
}

Function Get-NsxComputeCollections {
    Param (
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtUsername,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtPassword,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtManagerFqdn
    )

        $headers = New-BasicAuthHeader -username $nsxtUsername -password $nsxtPassword

        #Get Transport Zones
        Try{
            $uri="https://$nsxtManagerFqdn/api/v1/fabric/compute-collections"
            $computeCollections = (Invoke-WebRequest -Method GET -URI $uri -ContentType application/json -headers $headers).content | ConvertFrom-Json
            Return $computeCollections.results
        }
        Catch {
            catchwriter -object $_
        }
}

Function Get-NsxVpcConnectivityProfiles {
    Param (
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtUsername,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtPassword,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtManagerFqdn
    )

    $headers = New-BasicAuthHeader -username $nsxtUsername -password $nsxtPassword

    #Get Transport Zones
    Try{
        $uri="https://$nsxtManagerFqdn/policy/api/v1/orgs/default/projects/default/vpc-connectivity-profiles"
        $vpcConnectivityProfiles = (Invoke-WebRequest -Method GET -URI $uri -ContentType application/json -headers $headers).content | ConvertFrom-Json
        Return $vpcConnectivityProfiles.results
    }
    Catch {
        catchwriter -object $_
    }
}

Function Get-NsxTransitGateways {
    Param (
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtUsername,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtPassword,
        [Parameter (Mandatory=$true)][ValidateNotNullOrEmpty()][String]$nsxtManagerFqdn
    )

    $headers = New-BasicAuthHeader -username $nsxtUsername -password $nsxtPassword

    #Get Transport Gateways
    Try{
        $uri="https://$nsxtManagerFqdn/policy/api/v1/orgs/default/projects/default/transit-gateways"
        $transitGateways = (Invoke-WebRequest -Method GET -URI $uri -ContentType application/json -headers $headers).content | ConvertFrom-Json
        Return $transitGateways.results
    }
    Catch {
        catchwriter -object $_
    }
}

# PnP Scraping Functions
Function Show-PnPFilesInFolder
{
    #Get All xlsx Files
    $xlsxFiles = (Get-ChildItem *.xlsx).name

    #Select Source File
    $Global:xlsxDisplayObject=@()
        $xlsxIndex = 1
        $Global:xlsxDisplayObject += [pscustomobject]@{
                'ID'    = "ID"
                'FileName' = "File Name"
            }
        $Global:xlsxDisplayObject += [pscustomobject]@{
                'ID'    = "--"
                'FileName' = "------------------"
            }
        Foreach ($xlsxFile in $xlsxFiles)
        {
            $Global:xlsxDisplayObject += [pscustomobject]@{
                'ID'    = $xlsxIndex
                'FileName' = $xlsxFile
            }
            $xlsxIndex++
        }

    #Get Source File	
    $xlsxDisplayObject | format-table -Property @{Expression=" "},id,FileName -autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r","`n") }
}

Function Get-PnPInputFileInputs
{
    Do
    {
        Write-Host ""; Write-Host " Choose the ID of VCF Planning & Preparation Workbook to create JSON content from (or C to cancel): " -ForegroundColor Yellow -nonewline
        $xlsxSelection = Read-Host
    } Until (($xlsxSelection -in $xlsxDisplayObject.ID) -OR ($xlsxSelection -eq "c"))
    If ($xlsxSelection -eq "c") {Break}
    $chosenWorkBook = ($xlsxDisplayObject | Where-Object {$_.id -eq $xlsxSelection}).FileName
    If ([System.Environment]::OSVersion.Platform -ne 'Win32NT')
    {
        $Global:WarningPreference = "SilentlyContinue"
    }
    $pnpWorkbook = Open-ExcelPackage -path $chosenWorkBook
    If ([System.Environment]::OSVersion.Platform -ne 'Win32NT')
    {
        $Global:WarningPreference = "Continue"
    }
    If ($pnpWorkbook.Workbook.Names["pnp_version_history"].Value -eq $Global:supportedAutomationVersion)
    {
        Remove-Variable workbookProfile -scope Global -ErrorAction SilentlyContinue
        Remove-Variable chosenWorkBook -scope Global -ErrorAction SilentlyContinue
        Remove-Variable sharedInstanceObject -scope Global -ErrorAction SilentlyContinue
        Remove-Variable managementObject -scope Global -ErrorAction SilentlyContinue
        Remove-Variable workloadObject -scope Global -ErrorAction SilentlyContinue
        Remove-Variable clusterObject -scope Global -ErrorAction SilentlyContinue
        $Global:workbookProfile = New-Object -type psobject
        $Global:workbookProfile | Add-Member -NotePropertyName 'granularOperation' -NotePropertyValue $pnpWorkbook.Workbook.Names["vcf_granular_option_chosen"].Value
        $Global:workbookProfile | Add-Member -NotePropertyName 'deploymentSpecification' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_domain_deployment_type_chosen"].Value
        $Global:workbookProfile | Add-Member -NotePropertyName 'instance' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_domain_chosen"].Value
        $Global:workbookProfile | Add-Member -NotePropertyName 'chosenWorkbook' -NotePropertyValue $chosenWorkBook
        $Global:workbookProfile | Add-Member -NotePropertyName 'clusterResult' -NotePropertyValue $pnpWorkbook.Workbook.Names["cluster_result"].Value
        If ($workbookProfile.granularOperation -eq "Deploy a new VCF fleet")
        {
            $Global:workbookProfile | Add-Member -NotePropertyName 'opsAutomationDayNDeployment' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_domain_ops_automation_later_chosen"].Value
            $Global:workbookProfile | Add-Member -NotePropertyName 'idbDayNDeployment' -NotePropertyValue $pnpWorkbook.Workbook.Names["flt_vidb_chosen"].Value
            $Global:workbookProfile | Add-Member -NotePropertyName 'logsDayNDeployment' -NotePropertyValue $pnpWorkbook.Workbook.Names["flt_logs_chosen"].Value
            $Global:workbookProfile | Add-Member -NotePropertyName 'networksDayNDeployment' -NotePropertyValue $pnpWorkbook.Workbook.Names["flt_net_chosen"].Value
        }
        If ($workbookProfile.granularOperation -eq "Create Cluster")
        {
            $Global:clusterObject = New-ClusterObject -pnpWorkbook $pnpWorkbook
        }
        elseIf ($workbookProfile.granularOperation -eq "Create VI Workload Domain")
        {
            $Global:workloadObject = New-WorkloadInstanceObject -pnpWorkbook $pnpWorkbook
        }
        else
        {
            $Global:sharedInstanceObject = New-SharedInstanceObject -pnpWorkbook $pnpWorkbook
            $Global:managementObject = New-ManagementInstanceObject -pnpWorkbook $pnpWorkbook
            If ($pnpWorkbook.Workbook.Names["wld_domain_chosen"].Value -in "Deploy Workload Domain with a Single-Rack / Multi-Rack Layer 2 Cluster","Deploy Workload Domain with a Multi-Rack Layer 3 Cluster")
            {
                $Global:workloadObject = New-WorkloadInstanceObject -pnpWorkbook $pnpWorkbook
            }        
        }
    }
    else{
        LogMessage -type ERROR -message "The Planning & Preparation Workbook version you supplied is not the version supported by this version of VCF.JSONGenerator"
        LogMessage -type ERROR -message "Please source the latest version from the Broadcom website"
    }
    Close-ExcelPackage $pnpWorkbook -NoSave -ErrorAction SilentlyContinue
}

Function New-TransferExcelContents
{    
    #Get Source File
    Show-PnPFilesInFolder
    Do
    {
        Write-Host ""; Write-Host " Choose the ID of the older VCF Planning & Preparation Workbook containing the source data (or C to cancel): " -ForegroundColor Yellow -nonewline
        $sourceFile = Read-Host
    } Until (($sourceFile -in $xlsxDisplayObject.ID) -OR ($sourceFile -eq "c"))
    If ($sourceFile -eq "c") {Break}
    $sourceXlsx = ($xlsxDisplayObject | Where-Object {$_.id -eq $sourceFile}).FileName

    #Get Template File
    Write-Host ""; Show-PnPFilesInFolder
    Do
    {
        Write-Host ""; Write-Host " Choose the ID of the current VCF Planning & Preparation Workbook template to transfer data to (or C to cancel): " -ForegroundColor Yellow -nonewline
        $templateFile = Read-Host
    } Until (($templateFile -in $xlsxDisplayObject.ID) -OR ($templateFile -eq "c"))
    If ($templateFile -eq "c") {Break}
    $targetXlsx = ($xlsxDisplayObject | Where-Object {$_.id -eq $templateFile}).FileName

    #Create New Target File from Template
    $newBlankFile = "Updated-"+($sourceXlsx.split(".xlsx")[0])+".xlsx"
    If (Test-Path -path $newBlankFile)
    {
        Remove-Item $newBlankFile
    }
    Copy-Item $targetXlsx $newBlankFile

    #Open and Check Excel Files
    $sourceWorkbook = Open-ExcelPackage -Path $sourceXlsx
    $sourceWorkbookUserVersion = [INT](($sourceWorkbook.Workbook.Names["pnp_version_number"].Value).split("v",2)[1]).replace(".","")
    If ($sourceWorkbookUserVersion -lt $baseSupportedUserVersion)
    {
        LogMessage -type ERROR -message "Source file $sourceXlsx is not supported for content transfer"
        LogMessage -type ERROR -message "Source file is $($sourceWorkbook.Workbook.Names["pnp_version_number"].Value) but must be version v1.9.0.005 or higher"
        anyKey
        Break
    }
    else
    {
        LogMessage -type INFO -message "Source file $sourceXlsx is supported for content transfer"
    }

    $targetWorkbook = Open-ExcelPackage -Path $newBlankFile
    $targetWorkbookAutomationVersion = [INT]($targetWorkbook.Workbook.Names["pnp_version_history"].Value)
    If ($targetWorkbookAutomationVersion -eq $supportedAutomationVersion)
    {
        LogMessage -type INFO -message "Template file $targetXlsx is the correct version for VCF.JSONGenerator"
        $changedNamesOld = @($targetWorkbook.Workbook.Names["change_control_old"].Value | Where-Object {$_ -ne $null})
        $changedNamesNew = @($targetWorkbook.Workbook.Names["change_control_new"].Value | Where-Object {$_ -ne $null})
    }
    else
    {
        LogMessage -type ERROR -message "Template file $targetXlsx is the not correct version for VCF.JSONGenerator" 
        LogMessage -type ERROR -message "Please source the latest version from the Broadcom website"
        anyKey
        Break
    }
    
    #Get Named Cell Count in source workbook
    $noOfNamedCells = $sourceWorkbook.Workbook.Names.Count

    #Get Inputs
    LogMessage -type INFO -message "Getting inputs from source file $sourceXlsx"
    $inputsHash = @{}
    $counter = 1
    Do
    {
        $namedCellName = $sourceWorkbook.Workbook.Names[$counter].Name | Where-Object {$sourceWorkbook.Workbook.Names[$counter].Name -like "input*"}
        $namedCellValue = $sourceWorkbook.Workbook.Names[$counter].Value | Where-Object {$sourceWorkbook.Workbook.Names[$counter].Name -like "input*"}
        If ($namedCellName)
        {
            $inputsHash.Add($namedCellName, $namedCellValue)
        }
        $counter++
    } Until ($counter -gt $noOfNamedCells)

    #Get Choices
    LogMessage -type INFO -message "Getting choices from source file $sourceXlsx"
    $choicesHash = @{}
    $counter = 1
    Do
    {
        $namedCellName = $sourceWorkbook.Workbook.Names[$counter].Name | Where-Object {$sourceWorkbook.Workbook.Names[$counter].Name -like "*chosen"}
        $namedCellValue = $sourceWorkbook.Workbook.Names[$counter].Value | Where-Object {$sourceWorkbook.Workbook.Names[$counter].Name -like "*chosen"}
        If ($namedCellName)
        {
            $choicesHash.Add($namedCellName, $namedCellValue)
        }
        $counter++
    }Until ($counter -gt $noOfNamedCells)

    Function insertValuesToExcelObject
    {
        Param(
        [Parameter(mandatory=$true)][hashtable]$hash,
        [Parameter(mandatory=$true)][array]$changedNamesOld,
        [Parameter(mandatory=$true)][array]$changedNamesNew
        )
        foreach ($h in $hash.GetEnumerator()) {
            If (($h.name -ne $null) -AND ($h.value -ne $null))
            {
                If ($targetWorkbook.Workbook.Names[$h.name])
                {
                    $targetWorkbook.Workbook.Names[$h.name].Value = $h.value
                }
                else
                {
                    If ($h.name -in $changedNamesOld)
                    {
                        $oldName = $h.name
                        Do{            
                            $index = [array]::IndexOf($changedNamesOld, $oldName)
                            $newName = $changedNamesNew[$index]
                            $oldName = $newName
                        }Until ($newname -notin $changedNamesOld)
                        LogMessage -type INFO -message "$($h.name) was remapped to $($newName)"
                        If ($targetWorkbook.Workbook.Names[$newName])
                        {
                            $targetWorkbook.Workbook.Names[$newName].Value = $h.value
                        }
                        else
                        {
                            LogMessage -type ERROR -message "Failed to remap $($h.name) to $($newName) as could not find target cell"
                            LogMessage -type ERROR -message "Please report bug on Planning & Preparation Workbook"
                        }                    
                    }
                    else
                    {
                        LogMessage -type INFO -message "$($h.name) was deprecated"
                    }
                }
            }
        }
    }
    LogMessage -type INFO -message "Injecting inputs into target file $newBlankFile"
    insertValuesToExcelObject -hash $inputsHash -changedNamesOld $changedNamesOld -changedNamesNew $changedNamesNew
    LogMessage -type INFO -message "Injecting choices into target file $newBlankFile"
    insertValuesToExcelObject -hash $choicesHash -changedNamesOld $changedNamesOld -changedNamesNew $changedNamesNew
    Close-ExcelPackage $targetWorkbook -calculate
    LogMessage -type NOTE -message "Transfer to $newBlankFile complete"
    LogMessage -type WARNING -message "Review updated file and populate fields that are new/unique to the latest workbook version"
}



# Generate Global Objects
Function New-SharedInstanceObject
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$pnpWorkbook
    )

    Try {
        LogMessage -type NOTE -message "Planning & Preparation Workbook to $($pnpWorkbook.Workbook.Names["mgmt_domain_chosen"].Value) discovered"
        LogMessage -type INFO -message "Extracting data common to Management and Workload Domains"

        $dnsObject = New-Object -TypeName psobject
        $dnsObject | Add-Member -notepropertyname 'dnsServer1' -notepropertyvalue $pnpWorkbook.Workbook.names["region_dns1_ip"].Value
        $dnsObject | Add-Member -notepropertyname 'dnsServer2' -notepropertyvalue $pnpWorkbook.Workbook.names["region_dns2_ip"].Value
        $dnsObject | Add-Member -notepropertyname 'parentDnsDomain' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $dnsObject | Add-Member -notepropertyname 'childDnsDomain' -notepropertyvalue $pnpWorkbook.Workbook.names["child_dns_zone"].Value
        
        $ntpObject = New-Object -TypeName psobject
        $ntpObject | Add-Member -notepropertyname 'ntpServer1' -notepropertyvalue $pnpWorkbook.Workbook.Names["region_ntp1_server"].Value
        $ntpObject | Add-Member -notepropertyname 'ntpServer2' -notepropertyvalue $pnpWorkbook.Workbook.Names["region_ntp2_server"].Value
        
        $ssoObject = New-Object -TypeName psobject
        $ssoObject | Add-Member -notepropertyname 'domain' -notepropertyvalue $pnpWorkbook.Workbook.names["mgmt_sso_domain"].Value 
        $ssoObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["administrator_vsphere_local_password"].Value 
        
        If ($workbookProfile.opsAutomationDayNDeployment -eq "Unselected")
        {
            $vcfOperationsObject = New-Object -TypeName psobject
            $vcfOperationsObject | Add-Member -notepropertyname 'nodeAFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_nodea_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'nodeBFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_nodeb_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'nodeCFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_nodec_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'vipFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_virtual_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'applianceSize' -notepropertyvalue ($pnpWorkbook.Workbook.Names["mgmt_vcfops_appliance_size_chosen"].Value).tolower()
            $vcfOperationsObject | Add-Member -notepropertyname 'adminUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_admin_password"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'rootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_root_password"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'opsCollectorFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_collector_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'opsCollectorRootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrops_collector_root_password"].Value

            $vcfAutomationObject = New-Object -TypeName psobject
            $vcfAutomationObject | Add-Member -notepropertyname 'nodeAIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_nodea_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'nodeBIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_nodeb_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'nodeCIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_nodec_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'extraNodeIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_noded_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'vipFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_virtual_fqdn"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'internalClusterCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_k8s_cluster_cidr_chosen"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'adminUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_admin_password"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'vcfaNodePrefix' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vra_prefix"].Value

            $vcfFleetManagerObject = New-Object -TypeName psobject
            $vcfFleetManagerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["xreg_vrslcm_fqdn"].Value
            $vcfFleetManagerObject | Add-Member -notepropertyname 'adminUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["vrslcm_admin_password"].Value
            $vcfFleetManagerObject | Add-Member -notepropertyname 'rootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["vrslcm_root_password"].Value
    
        }
        else
        {
            $vcfOperationsObject = New-Object -TypeName psobject
            $vcfOperationsObject | Add-Member -notepropertyname 'nodeAFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_nodea_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'nodeBFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_nodeb_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'nodeCFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_nodec_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'vipFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_vip_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'applianceSize' -notepropertyvalue ($pnpWorkbook.Workbook.Names["flt_custom_network_ops_size_chosen"].Value).tolower()
            $vcfOperationsObject | Add-Member -notepropertyname 'adminUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_admin_password"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'rootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_root_password"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'opsCollectorFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_collector_fqdn"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'opsCollectorRootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_collector_root_password"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'fltMgmtPortgroup' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_x_reg_pg"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'fltMgmtSubnetMask' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_x_reg_mask"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'fltMgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_x_reg_gateway_ip"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'collectorMgmtPortgroup' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_local_reg_pg"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'collectorMgmtSubnetMask' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_local_reg_mask"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'collectorMgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_local_reg_gateway_ip"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'fleetManagementDeploymentModel' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ha_mode_chosen"].Value
            $vcfOperationsObject | Add-Member -notepropertyname 'collectorApplianceSize' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ops_collector_size_chosen"].Value
            If ($pnpWorkbook.Workbook.Names["mgmt_domain_existing_vcf_operations_chosen"].Value -eq 'Unselected')
            {
                $vcfOperationsObject | Add-Member -notepropertyname 'useExisting' -notepropertyvalue $false
            }
            else
            {
                $vcfOperationsObject | Add-Member -notepropertyname 'useExisting' -notepropertyvalue $true
            } 
            
            
            $vcfAutomationObject = New-Object -TypeName psobject
            $vcfAutomationObject | Add-Member -notepropertyname 'nodeAIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_nodea_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'nodeBIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_nodeb_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'nodeCIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_nodec_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'extraNodeIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_noded_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'vipFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_vip_fqdn"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'internalClusterCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_cluster_cidr_chosen"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'adminUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_admin_password"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'vcfaNodePrefix' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_auto_prefix"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'fltMgmtPortgroup' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_x_reg_pg"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'fltMgmtSubnetMask' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_x_reg_mask"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'fltMgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_x_reg_gateway_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'collectorMgmtPortgroup' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_local_reg_pg"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'collectorMgmtSubnetMask' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_local_reg_mask"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'collectorMgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_local_reg_gateway_ip"].Value
            $vcfAutomationObject | Add-Member -notepropertyname 'fleetManagementDeploymentModel' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_ha_mode_chosen"].Value

            $vcfFleetManagerObject = New-Object -TypeName psobject
            $vcfFleetManagerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_flt_fqdn"].Value
            $vcfFleetManagerObject | Add-Member -notepropertyname 'adminUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_flt_admin_password"].Value
            $vcfFleetManagerObject | Add-Member -notepropertyname 'rootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["flt_custom_network_flt_root_password"].Value
        }        
        
        $vcfIdbObject = New-Object -TypeName psobject
        $vcfIdbObject | Add-Member -notepropertyname 'certAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_cert_alias"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'vipAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_vip_ip"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'nodeAIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_nodea_ip"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'nodeBIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_nodeb_ip"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'nodeCIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_nodec_ip"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'extraNodeIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_noded_ip"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'vCenter' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_vcenter_fqdn"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'cluster' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_cluster"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'folder' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_folder"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'resourcePool' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_resource_pool"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'portgroup' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_port_group"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'datastore' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_datastore"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'domainName' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'searchPath' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'dnsServers' -notepropertyvalue "$($dnsObject.dnsserver1),$($dnsObject.dnsServer2)"
        $vcfIdbObject | Add-Member -notepropertyname 'timeSyncMode' -notepropertyvalue "ntp"
        $vcfIdbObject | Add-Member -notepropertyname 'ntpServers' -notepropertyvalue "$($ntpObject.ntpServer1),$($ntpObject.ntpServer2)"
        $vcfIdbObject | Add-Member -notepropertyname 'gateway' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_gateway_ip"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'mask' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_mask"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'systemUserPasswordAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_system_user_alias"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'systemUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_system_user_password"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'rootUserPasswordAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_password_alias"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'rootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_password"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'nodePrefix' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_node_prefix"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'internalClusterCidr' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_internal_cidr_chosen"].Value
        $vcfIdbObject | Add-Member -notepropertyname 'vipFqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_vidb_vip_fqdn"].Value

        $vcfLogsObject = New-Object -TypeName psobject
        $vcfLogsObject | Add-Member -notepropertyname 'deploymentType' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_ha_mode_chosen"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'certAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_cert_alias"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'vipAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_vip_ip"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeAIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_nodea_ip"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeBIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_nodeb_ip"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeCIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_nodec_ip"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'vCenter' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_vcenter_fqdn"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'cluster' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_cluster"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'folder' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_folder"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'resourcePool' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_resource_pool"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'portgroup' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_portgroup"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'datastore' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_datastore"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'domainName' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'searchPath' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'dnsServers' -notepropertyvalue "$($dnsObject.dnsserver1),$($dnsObject.dnsServer2)"
        $vcfLogsObject | Add-Member -notepropertyname 'timeSyncMode' -notepropertyvalue "ntp"
        $vcfLogsObject | Add-Member -notepropertyname 'ntpServers' -notepropertyvalue "$($ntpObject.ntpServer1),$($ntpObject.ntpServer2)"
        $vcfLogsObject | Add-Member -notepropertyname 'diskMode' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_cert_disk_mode"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'gateway' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_gateway_ip"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'mask' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_mask"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'systemUserPasswordAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_admin_password_alias"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'systemUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_admin_password"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'rootUserPasswordAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_root_password_alias"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'rootUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_root_password"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'vipFqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_vip_fqdn"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeAfqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_nodea_fqdn"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeBfqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_nodeb_fqdn"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeCfqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_nodec_fqdn"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'nodeSize' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_node_size_chosen"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'adminEmail' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_admin_email"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'fipsMode' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_fips_mode_chosen"].Value
        $vcfLogsObject | Add-Member -notepropertyname 'configureAffinity' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_logs_affinty_rule_chosen"].Value
        
        $vcfNetworksObject = New-Object -TypeName psobject
        $vcfNetworksObject | Add-Member -notepropertyname 'deploymentType' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_ha_mode_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'certAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_cert_alias"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeAIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodea_ip"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeBIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodeb_ip"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeCIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodec_ip"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'proxyIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_prxy_ip"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'vCenter' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_vcenter_fqdn"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'cluster' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_cluster"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'folder' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_folder"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'resourcePool' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_resource_pool"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'datastore' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_datastore"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'domainName' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'searchPath' -notepropertyvalue $pnpWorkbook.Workbook.names["parent_dns_zone"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'dnsServers' -notepropertyvalue "$($dnsObject.dnsserver1),$($dnsObject.dnsServer2)"
        $vcfNetworksObject | Add-Member -notepropertyname 'timeSyncMode' -notepropertyvalue "ntp"
        $vcfNetworksObject | Add-Member -notepropertyname 'ntpServers' -notepropertyvalue "$($ntpObject.ntpServer1),$($ntpObject.ntpServer2)"
        $vcfNetworksObject | Add-Member -notepropertyname 'diskMode' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_disk_mode_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodePortgroup' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_node_portgroup"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeGateway' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_node_gateway_ip"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeNetmask' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_node_mask"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'systemUserPasswordAlias' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_admin_password_alias"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'systemUserPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_admin_password"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeAfqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodea_fqdn"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeBfqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodeb_fqdn"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeCfqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodec_fqdn"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeASize' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodea_size_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeBSize' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodeb_size_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'nodeCSize' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_nodec_size_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'proxyFqdn' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_prxy_fqdn"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'proxySize' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_prxy_size_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'proxyPortgroup' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_prxy_portgroup"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'proxyGateway' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_prxy_gateway_ip"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'proxyNetmask' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_prxy_mask"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'fipsMode' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_fips_mode_chosen"].Value
        $vcfNetworksObject | Add-Member -notepropertyname 'configureAffinity' -notepropertyvalue $pnpWorkbook.Workbook.names["flt_net_affinty_rule_chosen"].Value

        $sharedInstanceObject = New-Object -TypeName psobject
        $sharedInstanceObject | Add-Member -notepropertyname 'version' -notepropertyvalue $pnpWorkbook.Workbook.Names["vcf_version_chosen"].Value
        $sharedInstanceObject | Add-Member -notepropertyname 'dns' -notepropertyvalue $dnsObject
        $sharedInstanceObject | Add-Member -notepropertyname 'ntp' -notepropertyvalue $ntpObject
        $sharedInstanceObject | Add-Member -notepropertyname 'sso' -notepropertyvalue $ssoObject
        $sharedInstanceObject | Add-Member -notepropertyname 'operations' -notepropertyvalue $vcfOperationsObject
        $sharedInstanceObject | Add-Member -notepropertyname 'automation' -notepropertyvalue $vcfAutomationObject
        $sharedInstanceObject | Add-Member -notepropertyname 'idb' -notepropertyvalue $vcfIdbObject
        $sharedInstanceObject | Add-Member -notepropertyname 'logs' -notepropertyvalue $vcfLogsObject
        $sharedInstanceObject | Add-Member -notepropertyname 'networks' -notepropertyvalue $vcfNetworksObject
        $sharedInstanceObject | Add-Member -notepropertyname 'fleetManager' -notepropertyvalue $vcfFleetManagerObject
        $sharedInstanceObject | Add-Member -notepropertyname 'subscriptionLicensing' -notepropertyvalue "NotApplicable"
        Return $sharedInstanceObject
    }
    Catch {
        LogMessage -type ERROR -message "Shared Object failed to generate for $instance Instance. Please consult the error message and remediate"
        Break
    }
}

Function New-ManagementInstanceObject
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$pnpWorkbook
    )

    Try {
        LogMessage -type INFO -message "Extracting data specific to Management Domain Creation"
        $totalRackCount = 1
        $vcfInstanceName = $pnpWorkbook.Workbook.Names["vcf_instance_name"].Value

        $domainName = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value
        $sddcManagerObject = New-Object -TypeName psobject
        $sddcManagerObject | Add-Member -notepropertyname 'hostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_hostname"].Value
        $sddcManagerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_fqdn"].Value
        $sddcManagerObject | Add-Member -notepropertyname 'ipAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_ip"].Value
        $sddcManagerObject | Add-Member -notepropertyname 'rootUser' -notepropertyvalue "root"
        $sddcManagerObject | Add-Member -notepropertyname 'adminUser' -notepropertyvalue ("administrator@"+$pnpWorkbook.Workbook.names["mgmt_sso_domain"].Value)
        $sddcManagerObject | Add-Member -notepropertyname 'vcfUser' -notepropertyvalue "vcf"
        $sddcManagerObject | Add-Member -notepropertyname 'rootPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_root_password"].Value
        $sddcManagerObject | Add-Member -notepropertyname 'vcfPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_vcf_password"].Value
        $sddcManagerObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_admin_local_password"].Value
        $sddcManagerObject | Add-Member -notepropertyname 'localAdminPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["sddc_mgr_admin_local_password"].Value
        
        $vcenterServerObject = New-Object -TypeName psobject
        $vcenterServerObject | Add-Member -notepropertyname 'hostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_vc_hostname"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_vc_fqdn"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'ipAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_vc_ip"].Value 
        $vcenterServerObject | Add-Member -notepropertyname 'adminUser' -notepropertyvalue ("administrator@"+$pnpWorkbook.Workbook.names["mgmt_sso_domain"].Value)
        $vcenterServerObject | Add-Member -notepropertyname 'rootUser' -notepropertyvalue 'root'
        $vcenterServerObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["administrator_vsphere_local_password"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'rootPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["vcenter_root_password"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'datacenter' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'ceipStatus' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_ceip_status_chosen"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'mgmtVmFolder' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_mgmt_vm_folder"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'nsxVmFolder' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsx_vm_folder"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'edgeVmFolder' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_edge_vm_folder"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'mgmtRp' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_mgmt_rp"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'nsxRp' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsx_rp"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'userEdgeRp' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_user_edge_rp"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'userVmRp' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_user_vm_rp"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'vcSize' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_vcenter_appliance_size_chosen"].Value
        If ($pnpWorkbook.Workbook.Names["mgmt_domain_existing_vcenter_chosen"].Value -eq 'Unselected')
        {
            $vcenterServerObject | Add-Member -notepropertyname 'useExisting' -notepropertyvalue $false
        }
        else
        {
            $vcenterServerObject | Add-Member -notepropertyname 'useExisting' -notepropertyvalue $true
        }      

        $vdsArray = @()
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_mtu"].Value -as [STRING]
            'type' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_link_type_chosen"].Value
        }
        If ($vdsArray[0].type -eq "VDS LAG")
        {
            $vdsArray[0] | Add-Member -notePropertyName 'lagName' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_lag_name"].Value
            $vdsArray[0] | Add-Member -notePropertyName 'lagMode' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_lacp_mode_chosen"].Value
            $vdsArray[0] | Add-Member -notePropertyName 'lagLoadBalancing' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_lag_lbt_chosen"].Value
            $vdsArray[0] | Add-Member -notePropertyName 'lagTimeout' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_lacp_timeout_chosen"].Value
            $vdsArray[0] | Add-Member -notePropertyName 'uplinkCount' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds01_uplink_count"].Value            
        }
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_mtu"].Value -as [STRING]
            'type' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_link_type_chosen"].Value
        }
        If ($vdsArray[1].type -eq "VDS LAG")
        {
            $vdsArray[1] | Add-Member -notePropertyName 'lagName' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_lag_name"].Value
            $vdsArray[1] | Add-Member -notePropertyName 'lagMode' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_lacp_mode_chosen"].Value
            $vdsArray[1] | Add-Member -notePropertyName 'lagLoadBalancing' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_lag_lbt_chosen"].Value
            $vdsArray[1] | Add-Member -notePropertyName 'lagTimeout' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_lacp_timeout_chosen"].Value
            $vdsArray[1] | Add-Member -notePropertyName 'uplinkCount' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds02_uplink_count"].Value
        }
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_mtu"].Value -as [STRING]
            'type' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_link_type_chosen"].Value
        }
        If ($vdsArray[2].type -eq "VDS LAG")
        {
            $vdsArray[2] | Add-Member -notePropertyName 'lagName' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_lag_name"].Value
            $vdsArray[2] | Add-Member -notePropertyName 'lagMode' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_lacp_mode_chosen"].Value
            $vdsArray[2] | Add-Member -notePropertyName 'lagLoadBalancing' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_lag_lbt_chosen"].Value
            $vdsArray[2] | Add-Member -notePropertyName 'lagTimeout' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_lacp_timeout_chosen"].Value
            $vdsArray[2] | Add-Member -notePropertyName 'uplinkCount' -notePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_vds03_uplink_count"].Value
        }
        
        $az1PortGroups = New-Object -TypeName psobject
        $az1PortGroups | Add-Member -notepropertyname 'mgmtVm' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_mgmt_vm_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'mgmt' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_mgmt_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vmotion' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_vmotion_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vsan' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_vsan_pg"].Value
        
        $az2PortGroups = New-Object -TypeName psobject
        $az2PortGroups | Add-Member -notepropertyname 'mgmtVm' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_mgmt_vm_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'mgmt' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az2_mgmt_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'vmotion' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az2_vmotion_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'vsan' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_cl01_az2_vsan_pg"].Value
        
        $portGroupNames = New-Object -TypeName psobject
        $portGroupNames | Add-Member -notepropertyname 'az1' -notepropertyvalue $az1PortGroups
        $portGroupNames | Add-Member -notepropertyname 'az2' -notepropertyvalue $az2PortGroups

        $vsphereClusterArray = @()
        $vsphereClusterArray += [PSCustomObject]@{
            'clusterName' = $pnpWorkbook.Workbook.Names["mgmt_cl01_cluster"].Value
            'vssSwitch' = 'vSwitch0'
            'vsanDatastore' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vsan_datastore"].Value
            'vsanftt' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vsan_ftt_chosen"].Value
            'vsanDedup' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vsan_dedupe_compression_chosen"].Value
            'primaryAzVmGroup' = ($pnpWorkbook.Workbook.Names["mgmt_cl01_cluster"].Value + "_primary-az-vmgroup")
            'evcMode' = $pnpWorkbook.Workbook.Names["mgmt_cl01_evc_mode_chosen"].Value
            'vdsProfile' = $pnpWorkbook.Workbook.Names["mgmt_cl01_vds_profile_chosen"].Value
            'nsxOperationDefaultMode' = $pnpWorkbook.Workbook.Names["mgmt_default_nsx_operation_mode_chosen"].Value
            'nsxOperationSelectedMode' = $pnpWorkbook.Workbook.Names["mgmt_nsx_operation_mode_chosen"].Value                        
            'vds' = $vdsArray
            'portGroupNames' = $portGroupNames
            'storageModel' = $pnpWorkbook.Workbook.Names["mgmt_principal_storage_chosen"].Value
            'secondaryStorage' = $pnpWorkbook.Workbook.Names["mgmt_secondary_storage_chosen"].Value
        }

        $nsxtManagerObject = New-Object -TypeName psobject
        $nsxtManagerObject | Add-Member -notepropertyname 'hostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_hostname"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'ipAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_vip_ip"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_vip_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'adminUser' -notepropertyvalue "admin"
        $nsxtManagerObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["nsxt_lm_admin_password"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'rootPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["nsxt_lm_root_password"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'auditPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["nsxt_lm_audit_password"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeAFQDN' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgra_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeBFQDN' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgrb_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeCFQDN' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgrc_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'mgrFormfactor' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_nsxt_appliance_size_chosen"].Value
        If ($pnpWorkbook.Workbook.Names["mgmt_domain_existing_nsx_manager_chosen"].Value -eq 'Unselected')
        {
            $nsxtManagerObject | Add-Member -notepropertyname 'useExisting' -notepropertyvalue $false
        }
        else
        {
            $nsxtManagerObject | Add-Member -notepropertyname 'useExisting' -notepropertyvalue $true
        }  

        $hostCredentialsObject = New-Object -TypeName psobject
        $hostCredentialsObject | Add-Member -notepropertyname 'esxiPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["esxi_root_password"].Value
        $hostCredentialsObject | Add-Member -notepropertyname 'esxiUsername' -notepropertyvalue "root"

        # End Domain Specific Stuff

        #Define AZs for the domain
        $az1Object = New-Object -TypeName psobject
        $az2Object = New-Object -TypeName psobject

        # Start Rack Specific Stuff
        $rackIDArray = @()
        Foreach ($_ in (1..$totalRackCount)) {$rackIDArray += "rack$($_)"}
        Foreach ($rack in $rackIDArray)
        {
            If ($rack -eq "rack1")
            {
                $rackVariableModifier = ""
            }
            else
            {
                $rackVariableModifier = "$($rack)_"
            }
            $az1RackHostNames = @(($pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_hostnames"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az1RackHostMgmtIps = @(($pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_mgmt_ips"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az1RackHostFqdns = @(($pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_fqdns"].Value) | Where-Object {$_ -notin "Value Missing","Not Required" -and $_ -ne ""})
            
            $az1RackHostsObject = @()
            Foreach ($az1RackHost in $az1RackHostFqdns)
            {
                $az1RackHostObject = [pscustomobject]@{
                    'mgmtIp'   = $az1RackHostMgmtIps[$az1RackHostFqdns.indexof($az1RackHost)]
                    'hostname' = $az1RackHostNames[$az1RackHostFqdns.indexof($az1RackHost)]
                    'fqdn'     = $az1RackHostFqdns[$az1RackHostFqdns.indexof($az1RackHost)]
                }
                $az1RackHostsObject += $az1RackHostObject           
            }

            $az2RackHostNames = @(($pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_hostnames"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az2RackHostMgmtIps = @(($pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_mgmt_ips"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az2RackHostFqdns = @(($pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_fqdns"].Value) | Where-Object {$_ -notin "Value Missing","Not Required" -and $_ -ne ""})
            
            $az2RackHostsObject = @()
            Foreach ($az2RackHost in $az2RackHostFqdns)
            {
                $az2RackHostObject = [pscustomobject]@{
                    'mgmtIp'   = $az2RackHostMgmtIps[$az2RackHostFqdns.indexof($az2RackHost)]
                    'hostname' = $az2RackHostNames[$az2RackHostFqdns.indexof($az2RackHost)]
                    'fqdn'     = $az2RackHostFqdns[$az2RackHostFqdns.indexof($az2RackHost)]
                }
                $az2RackHostsObject += $az2RackHostObject
            }
                
            $az1RackNetworkObject = New-Object -TypeName psobject
            
            #VMs
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVmVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVmGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVmMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVmCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVmNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVmNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_mask"].Value

            #Hosts
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_mask"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_pool_start_ip"].Value        
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vmotion_pool_end_ip"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)vsan_pool_end_ip"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetmask' -notepropertyvalue  $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)secondary_storage_pool_end_ip"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_pool_end_ip"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_network_profile_name"].Value
            #$az1RackNetworkObject | Add-Member -notepropertyname 'vcfNetworkPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)pool_name"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_network_pool_name"].Value 
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolDesc' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)host_overlay_network_pool_description"].Value 
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayAddressing' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_host_overlay_addressing_chosen"].Value

            $az2RackNetworkObject = New-Object -TypeName psobject
            #VMs
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVmVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVmGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVmMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVmCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVmNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVmNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az1_$($rackVariableModifier)mgmt_vm_mask"].Value
            
            #Hosts
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)mgmt_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)mgmt_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)mgmt_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)mgmt_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)mgmt_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)mgmt_mask"].Value

            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_mask"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_pool_start_ip"].Value        
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vmotion_pool_end_ip"].Value

            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_mask"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_pool_start_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)vsan_pool_end_ip"].Value

            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_mask"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_pool_start_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)secondary_storage_pool_end_ip"].Value

            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_mask"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_pool_start_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_pool_end_ip"].Value

            $az2RackNetworkObject | Add-Member -notepropertyname 'uplinkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_uplink_profile_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_network_profile_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vcfNetworkPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)pool_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_network_pool_name"].Value 
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolDesc' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_network_pool_description"].Value 
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayAddressing' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_host_overlay_addressing_chosen"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'reuseExistingVcfNetworkPool' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)reuse_vcf_networkpool_chosen"].Value
            $az2RackNetworkObject | Add-Member -NotePropertyName 'reuseExistingStaticIpPool' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az2_$($rackVariableModifier)host_overlay_new_pool_chosen"].Value

            $az1RackObject = New-Object -TypeName psobject
            $az1RackObject | Add-Member -notepropertyname 'hosts' -notepropertyvalue $az1RackHostsObject
            $az1RackObject | Add-Member -notepropertyname 'network' -notepropertyvalue $az1RackNetworkObject
            $az1Object | Add-Member -notepropertyname $rack -notepropertyvalue $az1RackObject

            $az2RackObject = New-Object -TypeName psobject
            $az2RackObject | Add-Member -notepropertyname 'hosts' -notepropertyvalue $az2RackHostsObject
            $az2RackObject | Add-Member -notepropertyname 'network' -notepropertyvalue $az2RackNetworkObject
            $az2Object | Add-Member -notepropertyname $rack -notepropertyvalue $az2RackObject

            If ($pnpWorkbook.Workbook.Names["mgmt_domain_chosen"].Value -eq "First Instance")
            {
                $joinFleet = "N"
            }
            else
            {
                $joinFleet = "Y"
            }

            If ($pnpWorkbook.Workbook.Names["mgmt_domain_vcf_operations_ha_mode_chosen"].Value -eq "High Availability (Three-node)")
            {
                $singleNSXTManager = "N"
                $fleetManagementDeploymentModel = "highlyAvailable"
            }
            else
            {
                $singleNSXTManager = "Y"
                $fleetManagementDeploymentModel = "single"
            }
            
            If ($pnpWorkbook.Workbook.Names["mgmt_domain_ops_automation_later_chosen"].Value -eq "Selected")
            {
                $fleetManagementTiming = "later"
            }
            else
            {
                $fleetManagementTiming = "bringup"
            }

            If ($pnpWorkbook.Workbook.Names["mgmt_domain_vcf_automation_later_chosen"].Value -eq "Selected")
            {
                $skipAutomation = "Y"   
            }
            else
            {
                $skipAutomation = "N"
            }
            
            $deploymentProfileObject = New-Object -TypeName psobject
            $deploymentProfileObject | Add-Member -notepropertyname 'singleNSXTManager' -notepropertyvalue $singleNSXTManager
            $deploymentProfileObject | Add-Member -notepropertyname 'skipAutomation' -notepropertyvalue $skipAutomation
            $deploymentProfileObject | Add-Member -notepropertyname 'joinFleet' -notepropertyvalue $joinFleet
            $deploymentProfileObject | Add-Member -notepropertyname 'fleetManagementDeploymentModel' -notepropertyvalue $fleetManagementDeploymentModel
            $deploymentProfileObject | Add-Member -notepropertyname 'fleetManagementTiming' -notepropertyvalue $fleetManagementTiming
        }
        #  End Rack Specific Stuff

        If ($pnpWorkbook.Workbook.Names["mgmt_vns_chosen"].value -eq "Centralized Connectivity")
        {
            $edgeNode1Object = New-Object -TypeName psobject
            $edgeNode1Object | Add-Member -NotePropertyName 'hostGroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_ec01_en01_host_group_affinity_rule_name"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'clusterName' -NotePropertyValue $vsphereClusterArray[0].clusterName
            $edgeNode1Object | Add-Member -NotePropertyName 'datastoreName' -NotePropertyValue $vsphereClusterArray[0].vsanDatastore
            $edgeNode1Object | Add-Member -NotePropertyName 'vmManagementPorgroupName' -NotePropertyValue $vsphereClusterArray[0].portGroupNames.az1.mgmtVm
            $edgeNode1Object | Add-Member -NotePropertyName 'name' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_fqdn"].value).split(".",2)[0]
            $edgeNode1Object | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_en1_fqdn"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'mgmtAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_mgmt_cidr"].value).split("/",2)[0]
            $edgeNode1Object | Add-Member -NotePropertyName 'mgmtGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_mgmt_vm_gateway_ip"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'mgmtPrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_mgmt_cidr"].value).split("/",2)[1]
            If ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "Static IP List")
            {
                $edgeNode1Object | Add-Member -NotePropertyName 'overlayIpAddress1' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_interface_ip_1_ip"].value
                $edgeNode1Object | Add-Member -NotePropertyName 'overlayIpAddress2' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_interface_ip_2_ip"].value    
            }
            $edgeNode1Object | Add-Member -NotePropertyName 'overlayGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_edge_overlay_gateway_ip"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'overlayMask' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_edge_overlay_mask"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'formfactor' -NotePropertyValue $pnpWorkbook.Workbook.Names["sizing_mgmt_ec_formfactor_chosen"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'uplink01IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_uplink01_interface_cidr"].value).split("/",2)[0]
            $edgeNode1Object | Add-Member -NotePropertyName 'uplink02IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_uplink02_interface_cidr"].value).split("/",2)[0]

            $edgeNode2Object = New-Object -TypeName psobject
            $edgeNode2Object | Add-Member -NotePropertyName 'hostGroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_ec01_en02_host_group_affinity_rule_name"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'clusterName' -NotePropertyValue $vsphereClusterArray[0].clusterName
            $edgeNode2Object | Add-Member -NotePropertyName 'datastoreName' -NotePropertyValue $vsphereClusterArray[0].vsanDatastore
            $edgeNode2Object | Add-Member -NotePropertyName 'vmManagementPorgroupName' -NotePropertyValue $vsphereClusterArray[0].portGroupNames.az1.mgmtVm
            $edgeNode2Object | Add-Member -NotePropertyName 'name' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en2_fqdn"].value).split(".",2)[0]
            $edgeNode2Object | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_en2_fqdn"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'mgmtAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en2_mgmt_cidr"].value).split("/",2)[0]
            $edgeNode2Object | Add-Member -NotePropertyName 'mgmtGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_mgmt_vm_gateway_ip"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'mgmtPrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en2_mgmt_cidr"].value).split("/",2)[1]
            If ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "Static IP List")
            {
                $edgeNode2Object | Add-Member -NotePropertyName 'overlayIpAddress1' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_en2_edge_overlay_interface_ip_1_ip"].value
                $edgeNode2Object | Add-Member -NotePropertyName 'overlayIpAddress2' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_en2_edge_overlay_interface_ip_2_ip"].value    
            }

            $edgeNode2Object | Add-Member -NotePropertyName 'overlayGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_edge_overlay_gateway_ip"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'overlayMask' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_edge_overlay_mask"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'formfactor' -NotePropertyValue $pnpWorkbook.Workbook.Names["sizing_mgmt_ec_formfactor_chosen"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'uplink01IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en2_uplink01_interface_cidr"].value).split("/",2)[0]
            $edgeNode2Object | Add-Member -NotePropertyName 'uplink02IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en2_uplink02_interface_cidr"].value).split("/",2)[0]


            $nodesObject= New-Object -TypeName psobject
            $nodesObject | Add-Member -NotePropertyName 'node1' -NotePropertyValue $edgeNode1Object
            $nodesObject | Add-Member -NotePropertyName 'node2' -NotePropertyValue $edgeNode2Object

            $bgpPeer1Object = New-Object -TypeName psobject
            $bgpPeer1Object | Add-Member -NotePropertyName 'asn' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_tor1_peer_asn"].value
            $bgpPeer1Object | Add-Member -NotePropertyName 'id' -NotePropertyValue "-1"
            $bgpPeer1Object | Add-Member -NotePropertyName 'address' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_tor1_peer_ip"].value
            $bgpPeer1Object | Add-Member -NotePropertyName 'password' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_tor1_peer_bgp_password"].value

            $bgpPeer2Object = New-Object -TypeName psobject
            $bgpPeer2Object | Add-Member -NotePropertyName 'asn' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_tor2_peer_asn"].value
            $bgpPeer2Object | Add-Member -NotePropertyName 'id' -NotePropertyValue "-2"
            $bgpPeer2Object | Add-Member -NotePropertyName 'address' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_tor2_peer_ip"].value
            $bgpPeer2Object | Add-Member -NotePropertyName 'password' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_tor2_peer_bgp_password"].value

            $bgpObject = New-Object -TypeName psobject
            $bgpObject | Add-Member -NotePropertyName 'peer1' -NotePropertyValue $bgpPeer1Object
            $bgpObject | Add-Member -NotePropertyName 'peer2' -NotePropertyValue $bgpPeer2Object

            $edgeClusterObject = New-Object -TypeName psobject
            $edgeClusterObject | Add-Member -NotePropertyName 'name' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_ec_name"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'hostGroupAffinity' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_ec01_host_group_affinity_rule_chosen"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'hostSwitchProfileId' -NotePropertyValue "ce821684-e8b4-11e8-a5a1-5b81d6551107"
            $edgeClusterObject | Add-Member -NotePropertyName 'vlanTransportZoneId' -NotePropertyValue "1027ca04-24a8-11ef-9e70-06252099f24a"
            $edgeClusterObject | Add-Member -NotePropertyName 'edgeTrunk01PortgroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_uplink01_pg"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'edgeTrunk02PortgroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_cl01_az1_uplink02_pg"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'placementType' -NotePropertyValue "PolicyVsphereDeploymentConfig"
            $edgeClusterObject | Add-Member -NotePropertyName 'edgeNodeTunnelEndpointVlan' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_edge_overlay_vlan"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink01VlanId' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_uplink01_vlan"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink01Mtu' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_uplink01_mtu"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink01PrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_uplink01_interface_cidr"].value).split("/",2)[1]
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink02VlanId' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_uplink02_vlan"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink02Mtu' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_uplink01_mtu"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink02PrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_uplink02_interface_cidr"].value).split("/",2)[1]
            $edgeClusterObject | Add-Member -NotePropertyName 'localServicesID' -NotePropertyValue "ac4b6e79-e7ce-4458-9bdb-40d8c964b1d8"
            $edgeClusterObject | Add-Member -NotePropertyName 't0DisplayName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_tier0_name"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'localAsnNumber' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_en_asn"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'transitSubnet' -NotePropertyValue "100.64.0.0/21"
            $edgeClusterObject | Add-Member -NotePropertyName 'bgp' -NotePropertyValue $bgpObject
            $edgeClusterObject | Add-Member -NotePropertyName 'nodes' -NotePropertyValue $nodesObject
            $edgeClusterObject | Add-Member -NotePropertyName 'haMode' -NotePropertyValue (($pnpWorkbook.Workbook.Names["mgmt_tier0_ha_chosen"].value).ToUpper()).replace(" ","_")
            $edgeClusterObject | Add-Member -NotePropertyName 'externalIpBlocks' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_vpc_ext_ip_blocks"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'privateTgwIpBlocks' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_vpc_transit_gateway_ip_blocks"].value
            If ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "Static IP List")
            {
                $edgeClusterObject | Add-Member -NotePropertyName 'tepMode' -NotePropertyValue 'StaticIpv4List'
            }
            elseif ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "IP Pool")
            {
                $edgeClusterObject | Add-Member -NotePropertyName 'tepMode' -NotePropertyValue 'StaticIpv4Pool'
                $edgeClusterObject | Add-Member -NotePropertyName 'ipPoolName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_az1_edge_overlay_network_pool_name"].value                
            }
            elseif ($pnpWorkbook.Workbook.Names["mgmt_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "DHCP")
            {
                $edgeClusterObject | Add-Member -NotePropertyName 'tepMode' -NotePropertyValue 'Dhcpv4'
            }
        }

        $managementInstanceObject = New-Object -TypeName psobject
        $managementInstanceObject | Add-Member -notepropertyname 'version' -notepropertyvalue $pnpWorkbook.Workbook.Names["vcf_version_chosen"].Value
        $managementInstanceObject | Add-Member -notepropertyname 'instance' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_domain_chosen"].Value
        $managementInstanceObject | Add-Member -notepropertyname 'vcfInstanceName' -notepropertyvalue $vcfInstanceName
        $managementInstanceObject | Add-Member -notepropertyname 'deploymentProfile' -notepropertyvalue $deploymentProfileObject
        $managementInstanceObject | Add-Member -notepropertyname 'domainType' -notepropertyvalue "Management"
        $managementInstanceObject | Add-Member -notepropertyname 'domainName' -notepropertyvalue $domainName
        $managementInstanceObject | Add-Member -notepropertyname 'az1' -notepropertyvalue $az1Object
        $managementInstanceObject | Add-Member -notepropertyname 'az2' -notepropertyvalue $az2Object
        $managementInstanceObject | Add-Member -notepropertyname 'autoGeneratedPasswords' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_domain_password_creation_chosen"].Value
        $managementInstanceObject | Add-Member -notepropertyname 'hostCredentials' -notepropertyvalue $hostCredentialsObject
        $managementInstanceObject | Add-Member -notepropertyname 'sddcManager' -notepropertyvalue $sddcManagerObject
        $managementInstanceObject | Add-Member -notepropertyname 'vcenterServer' -notepropertyvalue $vcenterServerObject
        $managementInstanceObject | Add-Member -notepropertyname 'vsphereClusters' -notepropertyvalue $vsphereClusterArray
        $managementInstanceObject | Add-Member -notepropertyname 'nsxtManager' -notepropertyvalue $nsxtManagerObject

        If ($pnpWorkbook.Workbook.Names["mgmt_vns_chosen"].value -eq "Centralized Connectivity")
        {
            $managementInstanceObject | Add-Member -notepropertyname 'edgeCluster' -notepropertyvalue $edgeClusterObject
        }
        
        If ($pnpWorkbook.Workbook.Names["mgmt_stretched_cluster_chosen"].value -eq "Include")
        {
            $stretchClusterObject = New-Object -type pscustomobject
            $stretchClusterObject | Add-Member -notepropertyname 'required' -notepropertyvalue $true
            $stretchClusterObject | Add-Member -notepropertyname 'witnessFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_witness_fqdn"].Value
            $stretchClusterObject | Add-Member -notepropertyname 'witnessVsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_witnessaz_mgmt_cidr"].Value
            $stretchClusterObject | Add-Member -notepropertyname 'witnessVsanIp' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_witness_ip"].Value
            $managementInstanceObject | Add-Member -notepropertyname 'stretchCluster' -notepropertyvalue $stretchClusterObject
        }

        $networkPoolCreationRequired = $false
        
        Foreach ($rack in $rackIDArray)
        {
            Foreach ($az in "az1","az2")
            {
                If ($managementInstanceObject.$($az).$($rack).network.reuseExistingVcfNetworkPool -in "Exclude","Create a new VCF Network Pool")
                {
                    $networkPoolCreationRequired = $true
                }        
            }            
        }
        $managementInstanceObject | Add-Member -notepropertyname 'networkPoolCreationRequired' -notepropertyvalue $networkPoolCreationRequired


        Return $managementInstanceObject
    }
    Catch {
        LogMessage -type ERROR -message "Management Object failed to generate for $instance Instance. Please consult the error message and remediate"
        Break
    }
}

Function New-WorkloadInstanceObject
{   
    Param (
        [Parameter (Mandatory = $true)] [Object]$pnpWorkbook
    )

    Try {
        LogMessage -type INFO -message "Extracting data specific to Workload Domain Creation"

        
        If ($pnpWorkbook.Workbook.Names["wld_domain_chosen"].Value -eq "Deploy Workload Domain with a Multi-Rack Layer 3 Cluster")
        {
            $multiRackChosen = "Y"
        }
        else
        {
            $multiRackChosen = "N"
        }
        If ($multiRackChosen -eq "Y")
        {
            $totalRackCount = ([INT]($pnpWorkbook.Workbook.Names["wld_multi_rack_count_chosen"].Value) + 1)
            If ($pnpWorkbook.Workbook.Names["wld_dedicated_edge_cluster_result"].Value -eq "Included")
            {
                $dedicatedEdgeClusters = $true
                $computeRackCount = ($totalRackCount - 2)
            }
            else
            {
                $dedicatedEdgeClusters = $false
                $computeRackCount = $totalRackCount
            }
            $edgeRackFirst = "rack$($pnpWorkbook.Workbook.Names["wld_dedicated_edge_cluster_chosen_first"].Value)"
            $edgeRackSecond = "rack$($pnpWorkbook.Workbook.Names["wld_dedicated_edge_cluster_chosen_second"].Value)"
            $computeHostsPerRack = $pnpWorkbook.Workbook.Names["wld_compute_hosts_per_rack_chosen"].Value
        }
        else
        {
            $totalRackCount = 1
            $computeRackCount = 1
            If ($commonObject.environment.networkingModel -eq 'isolated')
            {
                $computeHostsPerRack = 3
            }
            else
            {
                $computeHostsPerRack = 4
            }            
            $dedicatedEdgeClusters = $false
            $edgeRackFirst = "Exclude"
            $edgeRackSecond = "Exclude"
        }
        
        $rackInformation = New-Object -TypeName psobject
        $rackInformation | Add-Member -notepropertyname 'multiRackChosen' -notepropertyvalue $multiRackChosen
        $rackInformation | Add-Member -notepropertyname 'totalRackCount' -notepropertyvalue $totalRackCount
        $rackInformation | Add-Member -notepropertyname 'computeRackCount' -notepropertyvalue $computeRackCount
        $rackInformation | Add-Member -notepropertyname 'computeHostsPerRack' -notepropertyvalue $computeHostsPerRack
        $rackInformation | Add-Member -notepropertyname 'dedicatedEdgeClusters' -notepropertyvalue $dedicatedEdgeClusters
        $rackInformation | Add-Member -notepropertyname 'edgeRackFirst' -notepropertyvalue $($edgeRackFirst)
        $rackInformation | Add-Member -notepropertyname 'edgeRackSecond' -notepropertyvalue $($edgeRackSecond)
        $rackInformation | Add-Member -notepropertyname 'edgeDeploymentModel' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_dedicated_edge_cluster_model_chosen"].Value

        $domainName = $pnpWorkbook.Workbook.Names["wld_sddc_domain"].Value

        $vcenterServerObject = New-Object -TypeName psobject
        $vcenterServerObject | Add-Member -notepropertyname 'vcenterSize' -notepropertyvalue "Medium"
        $vcenterServerObject | Add-Member -notepropertyname 'hostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_vc_hostname"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_vc_fqdn"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'ipAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_vc_ip"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'adminUser' -notepropertyvalue "administrator@$($pnpWorkbook.Workbook.Names["wld_sso_domain_name"].Value)"
        $vcenterServerObject | Add-Member -notepropertyname 'rootUser' -notepropertyvalue 'root'
        $vcenterServerObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_administrator_vsphere_local_password"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'rootPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_vcenter_root_password"].Value
        $vcenterServerObject | Add-Member -notepropertyname 'datacenter' -notepropertyvalue "$($domainName)-dc"

        $vdsArray = @()
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["wld_cl01_vds01_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["wld_cl01_vds01_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["wld_cl01_vds01_mtu"].Value -as [STRING]
        }
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["wld_cl01_vds02_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["wld_cl01_vds02_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["wld_cl01_vds02_mtu"].Value -as [STRING]
        }
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["wld_cl01_vds03_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["wld_cl01_vds03_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["wld_cl01_vds03_mtu"].Value -as [STRING]
        }

        $az1PortGroups = New-Object -TypeName psobject
        $az1PortGroups | Add-Member -notepropertyname 'mgmtVm' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az1_mgmt_vm_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'mgmt' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az1_mgmt_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vmotion' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az1_vmotion_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vsan' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az1_principal_storage_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vsanClient' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az1_vsan_storage_client_pg"].Value
        
        $az2PortGroups = New-Object -TypeName psobject
        $az2PortGroups | Add-Member -notepropertyname 'mgmtVm' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az1_mgmt_vm_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'mgmt' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az2_mgmt_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'vmotion' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az2_vmotion_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'vsan' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az2_principal_storage_pg"].Value
        $az2PortGroups | Add-Member -notepropertyname 'vsanClient' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_cl01_az2_vsan_storage_client_pg"].Value

        $portGroupNames = New-Object -TypeName psobject
        $portGroupNames | Add-Member -notepropertyname 'az1' -notepropertyvalue $az1PortGroups
        $portGroupNames | Add-Member -notepropertyname 'az2' -notepropertyvalue $az2PortGroups

        $vsphereClusterArray = @()
        $vsphereClusterArray += [PSCustomObject]@{
            'clusterName' = $pnpWorkbook.Workbook.Names["wld_cl01_cluster"].Value
            'clusterIndex' = 1
            'vlcmModel' = 'Images'
            'vsanDatastore' = $pnpWorkbook.Workbook.Names["wld_cl01_vsan_datastore"].Value
            'vsanftt' = $pnpWorkbook.Workbook.Names["wld_cl01_vsan_ftt_chosen"].Value
            'vsanDedup' = $pnpWorkbook.Workbook.Names["wld_cl01_vsan_dedupe_compression_chosen"].Value
            'nfsDatastoreName' = $pnpWorkbook.Workbook.Names["wld_cl01_nfs_datastore_name"].Value
            'nfsSharePath' = $pnpWorkbook.Workbook.Names["wld_cl01_nfs_share_path"].Value
            'nfsServerAddress' = $pnpWorkbook.Workbook.Names["wld_cl01_nfs_server_address"].Value
            'primaryAzVmGroup' = ($pnpWorkbook.Workbook.Names["wld_cl01_cluster"].Value + "_primary-az-vmgroup")
            'evcMode' = $pnpWorkbook.Workbook.Names["wld_cl01_evc_mode"].Value
            'vdsProfile' = $pnpWorkbook.Workbook.Names["wld_cl01_vds_profile_chosen"].Value
            'nsxOperationDefaultMode' = $pnpWorkbook.Workbook.Names["wld_nsx_default_operation_mode_chosen"].Value
            'nsxOperationSelectedMode' = $pnpWorkbook.Workbook.Names["wld_nsx_operation_mode_chosen"].Value
            'vds' = $vdsArray
            'portGroupNames' = $portGroupNames
            'storageModel' = $pnpWorkbook.Workbook.Names["wld_principal_storage_chosen"].Value
            'secondaryStorage' = $pnpWorkbook.Workbook.Names["wld_secondary_storage_chosen"].Value
            'imageName' = $pnpWorkbook.Workbook.Names["wld_cl01_image_name"].Value
        }

        $nsxtManagerObject = New-Object -TypeName psobject
        $nsxtManagerObject | Add-Member -notepropertyname 'hostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_hostname"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'ipAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_ip"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_vip_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'adminUser' -notepropertyvalue "admin"
        $nsxtManagerObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_lm_admin_password"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'rootPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_lm_root_password"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'auditPassword' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_lm_audit_password"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeAHostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgra_hostname"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeAFQDN' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgra_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeAIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgra_ip"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeBHostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgrb_hostname"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeBFQDN' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgrb_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeBIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgrb_ip"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeCHostname' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgrc_hostname"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeCFQDN' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgrc_fqdn"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'nodeCIpAddress' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_nsxt_mgrc_ip"].Value
        $nsxtManagerObject | Add-Member -notepropertyname 'formFactor' -notepropertyvalue $pnpWorkbook.Workbook.Names["sizing_w01_nsxt_appliance_size"].Value

        $hostCredentialsObject = New-Object -TypeName psobject
        $hostCredentialsObject | Add-Member -notepropertyname 'esxiPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["wld_esx_root_password"].Value
        $hostCredentialsObject | Add-Member -notepropertyname 'esxiUsername' -notepropertyvalue $pnpWorkbook.Workbook.names["wld_esx_root_username"].Value
        
        # End Domain Specific Stuff

        #Define AZs for the domain
        $az1Object = New-Object -TypeName psobject

        # Start Rack Specific Stuff
        $rackIDArray = @()
        Foreach ($_ in (1..$totalRackCount)) {$rackIDArray += "rack$($_)"}
        Foreach ($rack in $rackIDArray)
        {   
            If ($rack -eq "rack1")
            {
                $rackVariableModifier = ""
            }
            else
            {
                $rackVariableModifier = "$($rack)_"
            }

            $az1RackHostNames = @(($pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_hostnames"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az1RackHostMgmtIps = @(($pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_mgmt_ips"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az1RackHostFqdns = @(($pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_fqdns"].Value) | Where-Object {$_ -notin "Value Missing","Not Required" -and $_ -ne ""})
            
            $az1RackHostsObject = @()
            Foreach ($az1RackHost in $az1RackHostFqdns)
            {
                $az1RackHostObject = [pscustomobject]@{
                    'mgmtIp'   = $az1RackHostMgmtIps[$az1RackHostFqdns.indexof($az1RackHost)]
                    'hostname' = $az1RackHostNames[$az1RackHostFqdns.indexof($az1RackHost)]
                    'fqdn'     = $az1RackHostFqdns[$az1RackHostFqdns.indexof($az1RackHost)]
                }
                $az1RackHostsObject += $az1RackHostObject
            }
            
            $az2RackHostNames = @(($pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_hostnames"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az2RackHostMgmtIps = @(($pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_mgmt_ips"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az2RackHostFqdns = @(($pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_fqdns"].Value) | Where-Object {$_ -notin "Value Missing","Not Required" -and $_ -ne ""})
            
            $az2RackHostsObject = @()
            Foreach ($az2RackHost in $az2RackHostFqdns)
            {
                $az2RackHostObject = [pscustomobject]@{
                    'mgmtIp'   = $az2RackHostMgmtIps[$az2RackHostFqdns.indexof($az2RackHost)]
                    'hostname' = $az2RackHostNames[$az2RackHostFqdns.indexof($az2RackHost)]
                    'fqdn'     = $az2RackHostFqdns[$az2RackHostFqdns.indexof($az2RackHost)]
                }
                $az2RackHostsObject += $az2RackHostObject
            }
            
            $az1RackNetworkObject = New-Object -TypeName psobject
            
            #VMs
            #Hosts
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)mgmt_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)mgmt_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)mgmt_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)mgmt_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)mgmt_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'mgmtNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)mgmt_mask"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)vmotion_pool_end_ip"].Value
            
            If ($pnpWorkbook.Workbook.Names["wld_secondary_storage_chosen"].Value -eq "vSAN Storage Client Network")
            {
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_vlan"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_gateway_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_cidr"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_network"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue  $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_mask"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_mtu"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_pool_start_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)storage_cluster_pool_end_ip"].Value
            }
            else
            {
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_vlan"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_gateway_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_cidr"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_network"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue  $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_mask"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_mtu"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_pool_start_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)principal_storage_pool_end_ip"].Value
            }
    
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)secondary_storage_pool_end_ip"].Value    
        
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_Network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_pool_end_ip"].Value
        
            $az1RackNetworkObject | Add-Member -notepropertyname 'vcfNetworkPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)pool_name"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_network_profile_name"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'uplinkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_uplink_profile_name"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_network_pool_name"].Value 
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayAddressing' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_host_overlay_addressing_chosen"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'reuseExistingVcfNetworkPool' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)reuse_vcf_networkpool_chosen"].Value
            $az1RackNetworkObject | Add-Member -NotePropertyName 'reuseExistingStaticIpPool' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_$($rackVariableModifier)host_overlay_new_pool_chosen"].Value

            $az1RackObject = New-Object -TypeName psobject
            $az1RackObject | Add-Member -notepropertyname 'hosts' -notepropertyvalue $az1RackHostsObject
            $az1RackObject | Add-Member -notepropertyname 'network' -notepropertyvalue $az1RackNetworkObject
            $az1Object | Add-Member -notepropertyname $rack -notepropertyvalue $az1RackObject
      
            If ($pnpWorkbook.Workbook.Names["wld_stretched_cluster_result"].Value -eq "Included")
            {
                $az2Object = New-Object -TypeName psobject
                $az2RackNetworkObject = New-Object -TypeName psobject
                If ($rack -eq "rack1")
                {
                    #Hosts
                    $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)mgmt_vlan"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)mgmt_gateway_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)mgmt_mtu"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)mgmt_cidr"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)mgmt_network"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'mgmtNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)mgmt_mask"].Value
    
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_vlan"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_gateway_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_cidr"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_network"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_mask"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_mtu"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_pool_start_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)vmotion_pool_end_ip"].Value
                    
                    If ($pnpWorkbook.Workbook.Names["wld_secondary_storage_chosen"].Value -eq "vSAN Storage Client Network")
                    {
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_vlan"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_gateway_ip"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_cidr"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_network"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_mask"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_mtu"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_pool_start_ip"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)storage_cluster_pool_end_ip"].Value
                    }
                    else 
                    {
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_vlan"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_gateway_ip"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_cidr"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_network"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_mask"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_mtu"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_pool_start_ip"].Value
                        $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)principal_storage_pool_end_ip"].Value        
                    }
                    
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_vlan"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_gateway_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_cidr"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_network"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_mask"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_mtu"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_pool_start_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)secondary_storage_pool_end_ip"].Value
    
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_vlan"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_mask"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_mtu"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_gateway_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_cidr"].Value   
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_network"].Value   
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_pool_start_ip"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_pool_end_ip"].Value
            
                    $az2RackNetworkObject | Add-Member -notepropertyname 'vcfNetworkPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)pool_name"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_network_profile_name"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'uplinkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_uplink_profile_name"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_network_pool_name"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayAddressing' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_host_overlay_addressing_chosen"].Value
                    $az2RackNetworkObject | Add-Member -notepropertyname 'reuseExistingVcfNetworkPool' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)reuse_vcf_networkpool_chosen"].Value
                    $az2RackNetworkObject | Add-Member -NotePropertyName 'reuseExistingStaticIpPool' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az2_$($rackVariableModifier)host_overlay_new_pool_chosen"].Value
    
                    $az2RackObject = New-Object -TypeName psobject           
                    $az2RackObject | Add-Member -notepropertyname 'hosts' -notepropertyvalue $az2RackHostsObject
                    $az2RackObject | Add-Member -notepropertyname 'network' -notepropertyvalue $az2RackNetworkObject
                    $az2Object | Add-Member -notepropertyname $rack -notepropertyvalue $az2RackObject    
                }
            }
        }
        If ($pnpWorkbook.Workbook.Names["wld_nsx_ha_mode_chosen"].Value -eq "High-Availbility")
        {
            $singleNSXTManager = "N"
        }
        else
        {
            $singleNSXTManager = "Y"
        }

        $ssoObject = New-Object -TypeName psobject
        $ssoObject | Add-Member -notepropertyname 'domain' -notepropertyvalue $pnpWorkbook.Workbook.names["wld_sso_domain_name"].Value 
        $ssoObject | Add-Member -notepropertyname 'adminPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["wld_administrator_vsphere_local_password"].Value 

        $deploymentProfileObject = New-Object -TypeName psobject
        $deploymentProfileObject | Add-Member -notepropertyname 'singleNSXTManager' -notepropertyvalue $singleNSXTManager

        If ($pnpWorkbook.Workbook.Names["wld_bgp_chosen"].value -eq "Centralized Connectivity")
        {
            $edgeNode1Object = New-Object -TypeName psobject
            $edgeNode1Object | Add-Member -NotePropertyName 'hostGroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_ec01_en01_host_group_affinity_rule_name"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'clusterName' -NotePropertyValue $vsphereClusterArray[0].clusterName
            $edgeNode1Object | Add-Member -NotePropertyName 'datastoreName' -NotePropertyValue $vsphereClusterArray[0].vsanDatastore
            $edgeNode1Object | Add-Member -NotePropertyName 'vmManagementPorgroupName' -NotePropertyValue $vsphereClusterArray[0].portGroupNames.az1.mgmtVm
            $edgeNode1Object | Add-Member -NotePropertyName 'name' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_fqdn"].value).split(".",2)[0]
            $edgeNode1Object | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_en1_fqdn"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'mgmtAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_mgmt_cidr"].value).split("/",2)[0]
            $edgeNode1Object | Add-Member -NotePropertyName 'mgmtGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_mgmt_vm_gateway_ip"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'mgmtPrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_mgmt_cidr"].value).split("/",2)[1]
            If ($pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "Static IP List")
            {
                $edgeNode1Object | Add-Member -NotePropertyName 'overlayIpAddress1' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_interface_ip_1_ip"].value
                $edgeNode1Object | Add-Member -NotePropertyName 'overlayIpAddress2' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_interface_ip_2_ip"].value    
            }
            $edgeNode1Object | Add-Member -NotePropertyName 'overlayGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_edge_overlay_gateway_ip"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'overlayMask' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_edge_overlay_mask"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'formfactor' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_ec_formfactor_chosen"].value
            $edgeNode1Object | Add-Member -NotePropertyName 'uplink01IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_uplink01_interface_cidr"].value).split("/",2)[0]
            $edgeNode1Object | Add-Member -NotePropertyName 'uplink02IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_uplink02_interface_cidr"].value).split("/",2)[0]

            $edgeNode2Object = New-Object -TypeName psobject
            $edgeNode2Object | Add-Member -NotePropertyName 'hostGroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_ec01_en02_host_group_affinity_rule_name"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'clusterName' -NotePropertyValue $vsphereClusterArray[0].clusterName
            $edgeNode2Object | Add-Member -NotePropertyName 'datastoreName' -NotePropertyValue $vsphereClusterArray[0].vsanDatastore
            $edgeNode2Object | Add-Member -NotePropertyName 'vmManagementPorgroupName' -NotePropertyValue $vsphereClusterArray[0].portGroupNames.az1.mgmtVm
            $edgeNode2Object | Add-Member -NotePropertyName 'name' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en2_fqdn"].value).split(".",2)[0]
            $edgeNode2Object | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_en2_fqdn"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'mgmtAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en2_mgmt_cidr"].value).split("/",2)[0]
            $edgeNode2Object | Add-Member -NotePropertyName 'mgmtGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_mgmt_vm_gateway_ip"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'mgmtPrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en2_mgmt_cidr"].value).split("/",2)[1]
            If ($pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "Static IP List")
            {
                $edgeNode2Object | Add-Member -NotePropertyName 'overlayIpAddress1' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_en2_edge_overlay_interface_ip_1_ip"].value
                $edgeNode2Object | Add-Member -NotePropertyName 'overlayIpAddress2' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_en2_edge_overlay_interface_ip_2_ip"].value    
            }
            $edgeNode2Object | Add-Member -NotePropertyName 'overlayGateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_edge_overlay_gateway_ip"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'overlayMask' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_edge_overlay_mask"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'formfactor' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_ec_formfactor_chosen"].value
            $edgeNode2Object | Add-Member -NotePropertyName 'uplink01IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en2_uplink01_interface_cidr"].value).split("/",2)[0]
            $edgeNode2Object | Add-Member -NotePropertyName 'uplink02IpAddress' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en2_uplink02_interface_cidr"].value).split("/",2)[0]


            $nodesObject= New-Object -TypeName psobject
            $nodesObject | Add-Member -NotePropertyName 'node1' -NotePropertyValue $edgeNode1Object
            $nodesObject | Add-Member -NotePropertyName 'node2' -NotePropertyValue $edgeNode2Object

            $bgpPeer1Object = New-Object -TypeName psobject
            $bgpPeer1Object | Add-Member -NotePropertyName 'asn' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_tor1_peer_asn"].value
            $bgpPeer1Object | Add-Member -NotePropertyName 'id' -NotePropertyValue "-1"
            $bgpPeer1Object | Add-Member -NotePropertyName 'address' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_tor1_peer_ip"].value
            $bgpPeer1Object | Add-Member -NotePropertyName 'password' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_tor1_peer_bgp_password"].value

            $bgpPeer2Object = New-Object -TypeName psobject
            $bgpPeer2Object | Add-Member -NotePropertyName 'asn' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_tor2_peer_asn"].value
            $bgpPeer2Object | Add-Member -NotePropertyName 'id' -NotePropertyValue "-2"
            $bgpPeer2Object | Add-Member -NotePropertyName 'address' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_tor2_peer_ip"].value
            $bgpPeer2Object | Add-Member -NotePropertyName 'password' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_tor2_peer_bgp_password"].value

            $bgpObject = New-Object -TypeName psobject
            $bgpObject | Add-Member -NotePropertyName 'peer1' -NotePropertyValue $bgpPeer1Object
            $bgpObject | Add-Member -NotePropertyName 'peer2' -NotePropertyValue $bgpPeer2Object

            $edgeClusterObject = New-Object -TypeName psobject
            $edgeClusterObject | Add-Member -NotePropertyName 'name' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_ec_name"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'hostGroupAffinity' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_ec01_host_group_affinity_rule_chosen"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'hostSwitchProfileId' -NotePropertyValue "ce821684-e8b4-11e8-a5a1-5b81d6551107"
            $edgeClusterObject | Add-Member -NotePropertyName 'vlanTransportZoneId' -NotePropertyValue "1027ca04-24a8-11ef-9e70-06252099f24a"
            $edgeClusterObject | Add-Member -NotePropertyName 'edgeTrunk01PortgroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_cl01_az1_uplink01_pg"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'edgeTrunk02PortgroupName' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_cl01_az1_uplink02_pg"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'placementType' -NotePropertyValue "PolicyVsphereDeploymentConfig"
            $edgeClusterObject | Add-Member -NotePropertyName 'edgeNodeTunnelEndpointVlan' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_edge_overlay_vlan"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink01VlanId' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_uplink01_vlan"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink01Mtu' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_uplink01_mtu"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink01PrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_uplink01_interface_cidr"].value).split("/",2)[1]            
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink02VlanId' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_uplink02_vlan"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink02Mtu' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_uplink01_mtu"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'uplink02PrefixLength' -NotePropertyValue ($pnpWorkbook.Workbook.Names["wld_az1_en1_uplink02_interface_cidr"].value).split("/",2)[1]
            $edgeClusterObject | Add-Member -NotePropertyName 'localServicesID' -NotePropertyValue "ac4b6e79-e7ce-4458-9bdb-40d8c964b1d8"
            $edgeClusterObject | Add-Member -NotePropertyName 't0DisplayName' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_tier0_name"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'localAsnNumber' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_en_asn"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'transitSubnet' -NotePropertyValue "100.64.0.0/21"
            $edgeClusterObject | Add-Member -NotePropertyName 'bgp' -NotePropertyValue $bgpObject
            $edgeClusterObject | Add-Member -NotePropertyName 'nodes' -NotePropertyValue $nodesObject
            $edgeClusterObject | Add-Member -NotePropertyName 'haMode' -NotePropertyValue (($pnpWorkbook.Workbook.Names["wld_tier0_ha_chosen"].value).ToUpper()).replace(" ","_")
            $edgeClusterObject | Add-Member -NotePropertyName 'externalIpBlocks' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_vpc_ext_ip_blocks"].value
            $edgeClusterObject | Add-Member -NotePropertyName 'privateTgwIpBlocks' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_vpc_transit_gateway_ip_blocks"].value
            If ($pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "Static IP List")
            {
                $edgeClusterObject | Add-Member -NotePropertyName 'tepMode' -NotePropertyValue 'StaticIpv4List'
            }
            elseif ($pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "IP Pool")
            {
                $edgeClusterObject | Add-Member -NotePropertyName 'tepMode' -NotePropertyValue 'StaticIpv4Pool'
                $edgeClusterObject | Add-Member -NotePropertyName 'ipPoolName' -NotePropertyValue $pnpWorkbook.Workbook.Names["wld_az1_edge_overlay_network_pool_name"].value                
            }
            elseif ($pnpWorkbook.Workbook.Names["wld_az1_en1_edge_overlay_network_ip_allocation_chosen"].value -eq "DHCP")
            {
                $edgeClusterObject | Add-Member -NotePropertyName 'tepMode' -NotePropertyValue 'Dhcpv4'
            }
        }

        $workloadInstanceObject = New-Object -TypeName psobject
        $workloadInstanceObject | Add-Member -notepropertyname 'version' -notepropertyvalue $pnpWorkbook.Workbook.Names["vcf_version_chosen"].Value
        $workloadInstanceObject | Add-Member -notepropertyname 'deploymentProfile' -notepropertyvalue $deploymentProfileObject
        $workloadInstanceObject | Add-Member -notepropertyname 'instance' -notepropertyvalue $pnpWorkbook.Workbook.Names["mgmt_domain_chosen"].Value
        $workloadInstanceObject | Add-Member -notepropertyname 'granularOperation' -notepropertyvalue $pnpWorkbook.Workbook.Names["vcf_granular_option_chosen"].Value
        $workloadInstanceObject | Add-Member -notepropertyname 'domainType' -notepropertyvalue "Workload"
        $workloadInstanceObject | Add-Member -notepropertyname 'domainName' -notepropertyvalue $domainName
        $workloadInstanceObject | Add-Member -notepropertyname 'rackInformation' -notepropertyvalue $rackInformation
        $workloadInstanceObject | Add-Member -notepropertyname 'az1' -notepropertyvalue $az1Object
        If ($az2Object)
        {
            $workloadInstanceObject | Add-Member -notepropertyname 'az2' -notepropertyvalue $az2Object
        }
        $workloadInstanceObject | Add-Member -notepropertyname 'hostCredentials' -notepropertyvalue $hostCredentialsObject
        $workloadInstanceObject | Add-Member -notepropertyname 'vcenterServer' -notepropertyvalue $vcenterServerObject
        $workloadInstanceObject | Add-Member -notepropertyname 'sso' -notepropertyvalue $ssoObject
        $workloadInstanceObject | Add-Member -notepropertyname 'vsphereClusters' -notepropertyvalue $vsphereClusterArray
        $workloadInstanceObject | Add-Member -notepropertyname 'nsxtManager' -notepropertyvalue $nsxtManagerObject

        If ($pnpWorkbook.Workbook.Names["wld_bgp_chosen"].value -eq "Centralized Connectivity")
        {
            $workloadInstanceObject | Add-Member -notepropertyname 'edgeCluster' -notepropertyvalue $edgeClusterObject
        }

        If ($pnpWorkbook.Workbook.Names["wld_stretched_cluster_chosen"].value -eq "Include")
        {
            $stretchClusterObject = New-Object -type pscustomobject
            $stretchClusterObject | Add-Member -notepropertyname 'required' -notepropertyvalue $true
            $stretchClusterObject | Add-Member -notepropertyname 'witnessFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_witness_fqdn"].Value
            $stretchClusterObject | Add-Member -notepropertyname 'witnessVsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_witnessaz_mgmt_cidr"].Value
            $stretchClusterObject | Add-Member -notepropertyname 'witnessVsanIp' -notepropertyvalue $pnpWorkbook.Workbook.Names["wld_witness_ip"].Value
            $workloadInstanceObject | Add-Member -notepropertyname 'stretchCluster' -notepropertyvalue $stretchClusterObject
        }

        $networkPoolCreationRequired = $false
        
        Foreach ($rack in $rackIDArray)
        {
            Foreach ($az in "az1","az2")
            {
                If ($workloadInstanceObject.$($az).$($rack).network.reuseExistingVcfNetworkPool -in "Exclude","Create a new VCF Network Pool")
                {
                    $networkPoolCreationRequired = $true
                }        
            }            
        }
        $workloadInstanceObject | Add-Member -notepropertyname 'networkPoolCreationRequired' -notepropertyvalue $networkPoolCreationRequired

        Return $workloadInstanceObject
    }
    Catch {
        LogMessage -type ERROR -message "Workload object failed to generate for $($workloadInstanceObject.instance). Please consult the error message and remediate"
        $($_.Exception.Message)
    }
}

Function New-ClusterObject
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$pnpWorkbook
    )
    Try 
    {
        LogMessage -type INFO -message "Extracting data specific to Cluster Creation"
        If ($pnpWorkbook.Workbook.Names["cluster_chosen"].Value -eq "Deploy a Multi-Rack Layer 3 Cluster")
        {
            #$clusterType = "M"
            $totalRackCount = ([INT]($pnpWorkbook.Workbook.Names["cluster_multi_rack_count_chosen"].Value) + 1)
            $computeHostsPerRack = $pnpWorkbook.Workbook.Names["cluster_compute_hosts_per_rack_chosen"].Value
            $multiRackChosen = "Y"
        }
        else
        {
            $multiRackChosen = "N"
            $totalRackCount = 1
        }

        $rackInformation = New-Object -TypeName psobject
        $rackInformation | Add-Member -notepropertyname 'multiRackChosen' -notepropertyvalue $multiRackChosen
        $rackInformation | Add-Member -notepropertyname 'totalRackCount' -notepropertyvalue $totalRackCount
        $rackInformation | Add-Member -notepropertyname 'computeHostsPerRack' -notepropertyvalue $computeHostsPerRack   
        
        $vdsArray = @()
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["cluster_vds01_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["cluster_vds01_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["cluster_vds01_mtu"].Value -as [STRING]
        }
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["cluster_vds02_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["cluster_vds02_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["cluster_vds02_mtu"].Value -as [STRING]
        }
        $vdsArray += [PSCustomObject]@{
            'vdsName' = $pnpWorkbook.Workbook.Names["cluster_vds03_name"].Value
            'pNics' = $pnpWorkbook.Workbook.Names["cluster_vds03_pnics"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["cluster_vds03_mtu"].Value -as [STRING]
        }

        $az1PortGroups = New-Object -TypeName psobject
        $az1PortGroups | Add-Member -notepropertyname 'mgmtVm' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az1_mgmt_vm_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'mgmt' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az1_mgmt_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vmotion' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az1_vmotion_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vsan' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az1_principal_storage_pg"].Value
        $az1PortGroups | Add-Member -notepropertyname 'vsanClient' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_cl01_az1_vsan_storage_client_pg"].Value

        $portGroupNames = New-Object -TypeName psobject
        $portGroupNames | Add-Member -notepropertyname 'az1' -notepropertyvalue $az1PortGroups

        #Define AZs for the domain
        $az1Object = New-Object -TypeName psobject

        $rackIDArray = @()
        Foreach ($_ in (1..$totalRackCount)) {$rackIDArray += "rack$($_)"}
        Foreach ($rack in $rackIDArray)
        { 
            If ($rack -eq "rack1")
            {
                $rackVariableModifier = ""
                $pnpVariableNameModifier = "cluster"
            }
            else
            {
                $rackVariableModifier = "$($rack)_"
                $pnpVariableNameModifier = "wld"
            }
            $az1RackHostMgmtIps = @(($pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_mgmt_ips"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az1RackHostFqdns = @(($pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_fqdns"].Value) | Where-Object {$_ -notin "Value Missing","Not Required" -and $_ -ne ""})
            
            $az1RackHostsObject = @()
            Foreach ($az1RackFqdn in $az1RackHostFqdns)
            {
                $az1RackHostObject = [pscustomobject]@{
                    'mgmtIp'   = $az1RackHostMgmtIps[$az1RackHostFqdns.indexof($az1RackFqdn)]
                    'fqdn'     = $az1RackHostFqdns[$az1RackHostFqdns.indexof($az1RackFqdn)]
                }
                $az1RackHostsObject += $az1RackHostObject
            }
            
            $az1RackNetworkObject = New-Object -TypeName psobject

            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_pool_start_ip"].Value        
            $az1RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)vmotion_pool_end_ip"].Value

            If ($pnpWorkbook.Workbook.Names["cluster_secondary_storage_chosen"].Value -eq "vSAN Storage Client Network")
            {
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_vlan"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_gateway_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_cidr"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_network"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_mask"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_mtu"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_pool_start_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)storage_cluster_pool_end_ip"].Value
            }
            else 
            {
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_vlan"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_gateway_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_cidr"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_network"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_mask"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_mtu"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_pool_start_ip"].Value
                $az1RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)principal_storage_pool_end_ip"].Value
            }
            
            
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_network"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_mask"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_mtu"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)secondary_storage_pool_end_ip"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_vlan"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_gateway_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_cidr"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_pool_start_ip"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_pool_end_ip"].Value
            
            $az1RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_network_pool_name"].Value 
            $az1RackNetworkObject | Add-Member -notepropertyname 'uplinkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_uplink_profile_name"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'vcfNetworkPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)pool_name"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_network_profile_name"].Value

            $az1RackNetworkObject | Add-Member -notepropertyname 'hostOverlayAddressing' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_host_overlay_addressing_chosen"].Value
            $az1RackNetworkObject | Add-Member -notepropertyname 'reuseExistingVcfNetworkPool' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)reuse_vcf_networkpool_chosen"].Value
            $az1RackNetworkObject | Add-Member -NotePropertyName 'reuseExistingStaticIpPool' -NotePropertyValue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az1_$($rackVariableModifier)host_overlay_new_pool_chosen"].Value
            $az1RackObject = New-Object -TypeName psobject
            $az1RackObject | Add-Member -notepropertyname 'hosts' -notepropertyvalue $az1RackHostsObject
            $az1RackObject | Add-Member -notepropertyname 'network' -notepropertyvalue $az1RackNetworkObject
            $az1Object | Add-Member -notepropertyname $rack -notepropertyvalue $az1RackObject
        }

        If ($pnpWorkbook.Workbook.Names["cluster_stretched_cluster_chosen"].value -eq "Include")
        {
            $az2Object = New-Object -TypeName psobject

            $az2RackHostMgmtIps = @(($pnpWorkbook.Workbook.Names["cluster_az2_host_mgmt_ips"].Value) | Where-Object {$_ -notin "Value Missing","Not Required"})
            $az2RackHostFqdns = @(($pnpWorkbook.Workbook.Names["cluster_az2_host_fqdns"].Value) | Where-Object {$_ -notin "Value Missing","Not Required" -and $_ -ne ""})
            
            $az2RackHostsObject = @()
            Foreach ($az2RackHost in $az2RackHostFqdns)
            {
                $az2RackHostObject = [pscustomobject]@{
                    'mgmtIp'   = $az2RackHostMgmtIps[$az2RackHostFqdns.indexof($az2RackHost)]
                    'fqdn'     = $az2RackHostFqdns[$az2RackHostFqdns.indexof($az2RackHost)]
                }
                $az2RackHostsObject += $az2RackHostObject
            }
            
            $az2RackNetworkObject = New-Object -TypeName psobject
            
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_mask"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_pool_start_ip"].Value        
            $az2RackNetworkObject | Add-Member -notepropertyname 'vmotionPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_vmotion_pool_end_ip"].Value
            
            If ($pnpWorkbook.Workbook.Names["cluster_secondary_storage_chosen"].Value -eq "vSAN Storage Client Network")
            {
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_vlan"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_gateway_ip"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_cidr"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_network"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_mask"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_mtu"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_pool_start_ip"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_storage_cluster_pool_end_ip"].Value                    
            }
            else
            {
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_vlan"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_gateway_ip"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_cidr"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_network"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_mask"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_mtu"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_pool_start_ip"].Value
                $az2RackNetworkObject | Add-Member -notepropertyname 'vsanPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_principal_storage_pool_end_ip"].Value
            }

            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetwork' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_network"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageNetmask' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_mask"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStorageMtu' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_mtu"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_pool_start_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'secondaryStoragePoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["$($pnpVariableNameModifier)_az2_$($rackVariableModifier)secondary_storage_pool_end_ip"].Value
            
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayVlanID' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_vlan"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayGw' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_gateway_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_cidr"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolStartIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_pool_start_ip"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayPoolEndIP' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_pool_end_ip"].Value
            
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostIpAddressPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_network_pool_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'uplinkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_$($rackVariableModifier)host_overlay_uplink_profile_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'vcfNetworkPoolName' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_pool_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'hostOverlayAddressing' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_host_overlay_addressing_chosen"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_network_profile_name"].Value
            $az2RackNetworkObject | Add-Member -notepropertyname 'reuseExistingVcfNetworkPool' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_az2_reuse_vcf_networkpool_chosen"].Value
            $az2RackNetworkObject | Add-Member -NotePropertyName 'reuseExistingStaticIpPool' -NotePropertyValue $pnpWorkbook.Workbook.Names["cluster_az2_host_overlay_new_pool_chosen"].Value
            #$az2RackNetworkObject | Add-Member -notepropertyname 'reuseExistingVcfNetworkPool' -notepropertyvalue "Exclude"
            #$az2RackNetworkObject | Add-Member -NotePropertyName 'reuseExistingStaticIpPool' -NotePropertyValue "Create New Static IP Pool"
            
            $az2RackObject = New-Object -TypeName psobject
            $az2RackObject | Add-Member -notepropertyname 'hosts' -notepropertyvalue $az2RackHostsObject
            $az2RackObject | Add-Member -notepropertyname 'network' -notepropertyvalue $az2RackNetworkObject
            $az2Object | Add-Member -notepropertyname 'rack1' -notepropertyvalue $az2RackObject
        }

        $hostCredentialsObject = New-Object -TypeName psobject
        $hostCredentialsObject | Add-Member -notepropertyname 'esxiPassword' -notepropertyvalue $pnpWorkbook.Workbook.names["cluster_esx_root_password"].Value
        $hostCredentialsObject | Add-Member -notepropertyname 'esxiUsername' -notepropertyvalue $pnpWorkbook.Workbook.names["cluster_esx_root_username"].Value


        $vsphereClusterArray = @()
        $vsphereClusterArray += [PSCustomObject]@{
            'clusterName' = $pnpWorkbook.Workbook.Names["cluster_name"].Value
            'vlcmModel' = 'Images'
            'vsanDatastore' = $pnpWorkbook.Workbook.Names["cluster_vsan_datastore"].Value
            'vsanStorageClusterName' = $pnpWorkbook.Workbook.Names["cluster_storage_cluster_name"].Value            
            'vsanftt' =$pnpWorkbook.Workbook.Names["cluster_vsan_ftt_chosen"].Value
            'vsanDedup' =$pnpWorkbook.Workbook.Names["cluster_vsan_dedupe_compression_chosen"].Value
            'nfsDatastoreName' = $pnpWorkbook.Workbook.Names["cluster_nfs_datastore_name"].Value
            'nfsSharePath' = $pnpWorkbook.Workbook.Names["cluster_nfs_share_path"].Value
            'nfsServerAddress' = $pnpWorkbook.Workbook.Names["cluster_nfs_server_address"].Value
            'primaryAzVmGroup' = ($pnpWorkbook.Workbook.Names["cluster_name"].Value + "_primary-az-vmgroup")
            'vdsProfile' = $pnpWorkbook.Workbook.Names["cluster_vds_profile_chosen"].Value
            'nsxOperationDefaultMode' = $pnpWorkbook.Workbook.Names["cluster_default_nsx_operation_mode_chosen"].Value
            'nsxOperationSelectedMode' = $pnpWorkbook.Workbook.Names["cluster_nsx_operation_mode_chosen"].Value            
            'vds' = $vdsArray
            'portGroupNames' = $portGroupNames
            'storageModel' = $pnpWorkbook.Workbook.Names["cluster_principal_storage_chosen"].Value
            'imageName' = $pnpWorkbook.Workbook.Names["cluster_image_name"].Value
            'secondaryStorage' = $pnpWorkbook.Workbook.Names["cluster_secondary_storage_chosen"].Value
            'vsanType' = $pnpWorkbook.Workbook.Names["cluster_vsan_type"].Value
        }

        $clusterObject = New-Object -type pscustomobject
        $clusterObject | Add-Member -NotePropertyName "domainName" -NotePropertyValue $pnpWorkbook.Workbook.Names["cluster_domain_name"].Value #fix
        $clusterObject | Add-Member -notepropertyname 'rackInformation' -notepropertyvalue $rackInformation
        $clusterObject | Add-Member -notepropertyname 'az1' -notepropertyvalue $az1Object
        If ($az2Object)
        {
            $clusterObject | Add-Member -notepropertyname 'az2' -notepropertyvalue $az2Object
        }
        $clusterObject | Add-Member -notepropertyname 'hostCredentials' -notepropertyvalue $hostCredentialsObject
        $clusterObject | Add-Member -notepropertyname 'tzName' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_host_overlay_transport_zone"].Value
        $clusterObject | Add-Member -notepropertyname 'vsphereClusters' -notepropertyvalue $vsphereClusterArray
        If ($pnpWorkbook.Workbook.Names["cluster_stretched_cluster_chosen"].value -eq "Include")
        {
            $stretchClusterObject = New-Object -type pscustomobject
            $stretchClusterObject | Add-Member -notepropertyname 'required' -notepropertyvalue $true
            $stretchClusterObject | Add-Member -notepropertyname 'witnessFqdn' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_witness_fqdn"].Value
            $stretchClusterObject | Add-Member -notepropertyname 'witnessVsanCidr' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_witnessaz_mgmt_cidr"].Value
            $stretchClusterObject | Add-Member -notepropertyname 'witnessVsanIp' -notepropertyvalue $pnpWorkbook.Workbook.Names["cluster_witness_ip"].Value
            $stretchClusterObject | Add-Member -NotePropertyName 'networkTopology' -NotePropertyValue $pnpWorkbook.Workbook.Names["cluster_vsan_compute_network_topology_chosen"].Value
            $stretchClusterObject | Add-Member -NotePropertyName 'faultDomainMapping' -NotePropertyValue $pnpWorkbook.Workbook.Names["cluster_vsan_compute_fault_domain_mapping_chosen"].Value
            $clusterObject | Add-Member -notepropertyname 'stretchCluster' -notepropertyvalue $stretchClusterObject
        }
        
        $networkPoolCreationRequired = $false
        Foreach ($rack in $rackIDArray)
        {
            Foreach ($az in "az1","az2")
            {
                If ($clusterObject.$($az).$($rack).network.reuseExistingVcfNetworkPool -in "Exclude","Create a new VCF Network Pool")
                {
                    $networkPoolCreationRequired = $true
                }        
            }            
        }
        $clusterObject | Add-Member -notepropertyname 'networkPoolCreationRequired' -notepropertyvalue $networkPoolCreationRequired
        
        If ($clusterObject.rackInformation.multiRackChosen -eq "N")
        {
            If ($clusterObject.vsphereClusters[0].vsanType -eq "vSAN HCI")
            {
                $determinedClusterConfig = "Single-Rack HCI"
            }
            elseif ($clusterObject.vsphereClusters[0].vsanType -eq "vSAN Storage")
            {
                $determinedClusterConfig = "Single-Rack vSAN Storage"
            }
            elseIf ($clusterObject.vsphereClusters[0].vsanType -eq "Compute Cluster")
            {
                If ($clusterObject.stretchCluster.required -eq $true)
                {
                    $determinedClusterConfig = "Stretched Compute Only"
                }
                else
                {
                    $determinedClusterConfig = "Single-Rack Compute Only"
                }                
            }
        }
        elseIf ($clusterObject.rackInformation.multiRackChosen -eq "Y")
        {
            If ($clusterObject.vsphereClusters[0].vsanType -eq "vSAN HCI")
            {
                $determinedClusterConfig = "Multi-Rack HCI"
            }
            elseif ($clusterObject.vsphereClusters[0].vsanType -eq "vSAN Storage")
            {
                $determinedClusterConfig = "Multi-Rack vSAN Storage"
            }
            elseIf ($clusterObject.vsphereClusters[0].vsanType -eq "Compute Cluster")
            {
                $determinedClusterConfig = "Multi-Rack Compute Only"
            }
        }
        $clusterObject | Add-Member -notepropertyname 'determinedClusterConfig' -notepropertyvalue $determinedClusterConfig
        
        Return $clusterObject
    }
    Catch 
    {
        LogMessage -type ERROR -message "Cluster object failed to generate. Please consult the error message and remediate"
        $($_.Exception.Message)
    } 
    
}

# Domain JSON Files
Function New-ManagementDomainJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$instanceObject,
        [Parameter (Mandatory = $true)] [Array]$sharedInstanceObject
    )

    Try {
        LogMessage -type INFO -message "Generating Management Domain JSON"
        $singleNSXTManager = $instanceObject.deploymentProfile.singleNSXTManager
        $joinFleet = $instanceObject.deploymentProfile.joinFleet
        $skipAutomation = $instanceObject.deploymentProfile.skipAutomation
        If (($joinFleet -eq "Y") -and ($instanceObject.instance -eq "Additional Instance"))
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve fingerprints for ESX hosts plus existing Operations and Automation components? (Y/N): " -skipnewline
        }
        else
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve fingerprints for ESX hosts? (Y/N): " -skipnewline
        }
        Do
        {  
            $interactiveEnabled = Read-Host    
        } Until ($interactiveEnabled -in "Y","N")
        $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
            
        If (($joinFleet -eq "Y") -and ($instanceObject.instance -eq "Additional Instance"))
        {            
            If ($interactiveEnabled -eq "Y")
            {
                If ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
                {
                    $fm01fingerprint = (echo "Q" | openssl.exe s_client -connect "$($sharedInstanceObject.fleetManager.fqdn):443" -showcerts 2>$null |  Filter-X509 | openssl.exe x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]
                    $ops01fingerprint = (echo "Q" | openssl.exe s_client -connect "$($sharedInstanceObject.operations.nodeAFqdn):443" -showcerts 2>$null |  Filter-X509 | openssl.exe x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]                
                }
                else
                {
                    $fm01fingerprint = (echo "Q" | openssl s_client -connect "$($sharedInstanceObject.fleetManager.fqdn):443" -showcerts 2>$null |  Filter-X509 | openssl x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]
                    $ops01fingerprint = (echo "Q" | openssl s_client -connect "$($sharedInstanceObject.operations.nodeAFqdn):443" -showcerts 2>$null |  Filter-X509 | openssl x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]                
                }
                
                If ($skipAutomation -ne "Y")
                {
                    If ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
                    {
                        $auto01fingerprint = (echo "Q" | openssl.exe s_client -connect "$($sharedInstanceObject.automation.vipFqdn):443" -showcerts 2>$null |  Filter-X509 | openssl.exe x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]
                    }
                    else
                    {
                        $auto01fingerprint = (echo "Q" | openssl s_client -connect "$($sharedInstanceObject.automation.vipFqdn):443" -showcerts 2>$null |  Filter-X509 | openssl x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]
                    }
                    If ((!($fm01fingerprint)) -or (!($ops01fingerprint)) -or (!($auto01fingerprint)))
                    {
                        LogMessage -type ERROR -message "One or more of $($sharedInstanceObject.fleetManager.fqdn), $($sharedInstanceObject.operations.nodeAFqdn) or $($sharedInstanceObject.automation.vipFqdn) are not reachable. Unable to Join Fleet"
                        anykey
                        Break
                    }
                }
                else
                {
                    If ((!($fm01fingerprint)) -or (!($ops01fingerprint)))
                    {
                        LogMessage -type ERROR -message "One or more of $($sharedInstanceObject.fleetManager.fqdn) or $($sharedInstanceObject.operations.nodeAFqdn) are not reachable. Unable to Join Fleet"
                        anykey
                        Break
                    }
                }    
            }
            else
            {
                $fm01fingerprint = '<--ENTER-FLEET-MANAGER-FINGERPRINT-HERE-->'
                $ops01fingerprint = '<--ENTER-VCF-OPS-FINGERPRINT-HERE-->'
                $auto01fingerprint = '<--ENTER-VCF-AUTO-FINGERPRINT-HERE-->'
            }            
        }

        #dnsSpec
        If ($sharedInstanceObject.dns.dnsServer2 -in "n/a","Value Missing") {
            [Array]$nameServers =  $sharedInstanceObject.dns.dnsServer1
        }
        else {
            [Array]$nameServers =  $sharedInstanceObject.dns.dnsServer1,  $sharedInstanceObject.dns.dnsServer2
        } 
        $dnsObject = @()
        $dnsObject += [pscustomobject]@{
            'nameservers'         = $nameServers
            'subdomain'           = $sharedInstanceObject.dns.parentDnsDomain
        }

        #ntpServers
        If ($sharedInstanceObject.ntp.ntpServer2 -in "n/a","Value Missing") {
            [Array]$ntpServers =  $sharedInstanceObject.ntp.ntpserver1
        }
        else {
            [Array]$ntpServers =  $sharedInstanceObject.ntp.ntpserver1,  $sharedInstanceObject.ntp.ntpServer2
        }

        #vcenterSpec
        #$vcenterObject = @()
        $vcenterObject = [pscustomobject]@{
            'vcenterHostname'       = $instanceObject.vcenterServer.fqdn
            'vmSize'                = $instanceObject.vcenterServer.vcSize.tolower()
            'storageSize'           = 'lstorage' #review
            'ssoDomain'             = $sharedInstanceObject.sso.domain
            'useExistingDeployment' = $instanceObject.vcenterServer.useExisting
        }
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $vcenterObject | Add-Member -NotePropertyName 'rootVcenterPassword' -NotePropertyValue $instanceObject.vcenterServer.rootPassword
            $vcenterObject | Add-Member -NotePropertyName 'adminUserSsoPassword' -NotePropertyValue $instanceObject.vcenterServer.adminPassword
        }
        
        #clusterSpec    
        $clusterObject = @()
        $clusterObject += [pscustomobject]@{
            'clusterName'    = $instanceObject.vsphereClusters[0].clusterName
            'datacenterName'    = $instanceObject.vcenterServer.datacenter
        }

        #vsanSpec
        If ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-ESA")
        {
            $ESAenabledtrueobject = @()
            $ESAenabledtrueobject  += [pscustomobject]@{
                    'enabled' = $true
                }
        }
        elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-OSA")
        {
            $ESAenabledtrueobject = @()
            $ESAenabledtrueobject  += [pscustomobject]@{
                    'enabled' = $false
            }
            $excelvsanDedup = $instanceObject.vsphereClusters[0].vsanDedup
            If ($excelvsanDedup -eq "Unselected") {
                $vsanDedup = $false
            }
            elseIf ($excelvsanDedup -eq "Selected") {
                $vsanDedup = $true
            }
        }
        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'datastoreName' = $instanceObject.vsphereClusters[0].vsanDatastore
            'esaConfig' =  ($ESAenabledtrueobject | Select-Object -Skip 0)
        }
        If ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-OSA") {
            $vsanObject | Add-Member -NotePropertyName 'vsanDedup' -NotePropertyValue $vsanDedup
            $vsanObject | Add-Member -NotePropertyName 'failuresToTolerate' -NotePropertyValue $($instanceObject.vsphereClusters[0].vsanftt -as [INT])
        }
        $datastoreSpecObject = @()
        $datastoreSpecObject += [pscustomobject]@{
            'vsanSpec' = ($vsanObject | Select-Object -Skip 0)
        }

        #nsxtSpec
        $nsxtManagerObject = @()
        $nsxtManagerObject += [pscustomobject]@{
            'hostname' = $instanceObject.nsxtManager.nodeAFqdn
        }
        If ($singleNSXTManager -eq "N")
        {
            $nsxtManagerObject += [pscustomobject]@{
                'hostname' = $instanceObject.nsxtManager.nodeBFqdn
            }
            $nsxtManagerObject += [pscustomobject]@{
                'hostname' = $instanceObject.nsxtManager.nodeCFqdn
            }
        }
        #$nsxtObject = @()
        $nsxtObject = [pscustomobject]@{
            'nsxtManagerSize'                       = $instanceObject.nsxtManager.mgrFormfactor.tolower()            
            'nsxtManagers'                          = $nsxtManagerObject
            'vipFqdn'                               = $instanceObject.nsxtManager.fqdn
            'useExistingDeployment'                 = $instanceObject.nsxtManager.useExisting                        
            'skipNsxOverlayOverManagementNetwork'   = $true
            'transportVlanId'                       = $instanceObject.az1.rack1.network.hostOverlayVlanID -as [int]            
            'rootLoginEnabledForNsxtManager'        = "true" #review
            'sshEnabledForNsxtManager'              = "true" #review
        }
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $nsxtObject | Add-Member -NotePropertyName 'nsxtAdminPassword' -NotePropertyValue $instanceObject.nsxtManager.adminPassword
            $nsxtObject | Add-Member -NotePropertyName 'nsxtAuditPassword'-NotePropertyValue $instanceObject.nsxtManager.auditPassword
            $nsxtObject | Add-Member -NotePropertyName 'rootNsxtManagerPassword' -NotePropertyValue $instanceObject.nsxtManager.rootPassword
        }
        
        $ipAddressPoolSpec = New-Object -type PSObject
        If ($instanceObject.az1.rack1.network.hostOverlayAddressing -eq "IP Pool")
        {
            $ipAddressPoolRangesArray += [pscustomobject]@{
                'start' = $instanceObject.az1.rack1.network.hostOverlayPoolStartIP
                'end' = $instanceObject.az1.rack1.network.hostOverlayPoolEndIP
            }
            
            $subnetsArray = @()
            $subnetsArray += [pscustomobject]@{
                'cidr' = $instanceObject.az1.rack1.network.hostOverlayCidr
                'gateway' = $instanceObject.az1.rack1.network.hostOverlayGw
                'ipAddressPoolRanges' = @($ipAddressPoolRangesArray)
            }

            
            $ipAddressPoolSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $instanceObject.az1.rack1.network.hostIpAddressPoolName
            $ipAddressPoolSpec | Add-Member -NotePropertyName 'description' -NotePropertyValue $instanceObject.az1.rack1.network.hostIpAddressPoolDesc
            $ipAddressPoolSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
            
        }
        else
        {
            $ipAddressPoolSpec = $null
        } 
        $nsxtObject | Add-Member -NotePropertyName 'ipAddressPoolSpec' -NotePropertyValue $ipAddressPoolSpec   
        
        #vcfOperationsSpec
        $vcfOpsNodesObject = @()

        If ($instanceObject.instance -eq "First Instance")
        {
            If ($instanceObject.deploymentProfile.fleetManagementDeploymentModel -eq "single")
            {
                $vcfOpsNodesObjectNodeA = [pscustomobject]@{
                    'hostname' = $sharedInstanceObject.operations.nodeAFqdn
                    'type' = 'master'                    
                }
                If ($instanceObject.autoGeneratedPasswords -ne "Selected")
                {
                    $vcfOpsNodesObjectNodeA | Add-Member -NotePropertyName 'rootUserPassword' -NotePropertyValue $sharedInstanceObject.operations.rootUserPassword
                }
                $vcfOpsNodesObject += $vcfOpsNodesObjectNodeA
            }
            elseif ($instanceObject.deploymentProfile.fleetManagementDeploymentModel -eq "highlyAvailable")
            {
                $vcfOpsNodesObjectNodeA = [pscustomobject]@{
                    'hostname' = $sharedInstanceObject.operations.nodeAFqdn
                    'type' = 'master'                    
                }

                $vcfOpsNodesObjectNodeB = [pscustomobject]@{
                    'hostname' = $sharedInstanceObject.operations.nodeBFqdn
                    'type' = 'replica'                    
                }
                
                $vcfOpsNodesObjectNodeC = [pscustomobject]@{
                    'hostname' = $sharedInstanceObject.operations.nodeCFqdn
                    'type' = 'data'                    
                }

                If ($instanceObject.autoGeneratedPasswords -ne "Selected")
                {
                    $vcfOpsNodesObjectNodeA | Add-Member -NotePropertyName 'rootUserPassword' -NotePropertyValue $sharedInstanceObject.operations.rootUserPassword
                    $vcfOpsNodesObjectNodeB | Add-Member -NotePropertyName 'rootUserPassword' -NotePropertyValue $sharedInstanceObject.operations.rootUserPassword
                    $vcfOpsNodesObjectNodeC | Add-Member -NotePropertyName 'rootUserPassword' -NotePropertyValue $sharedInstanceObject.operations.rootUserPassword
                }
                $vcfOpsNodesObject += $vcfOpsNodesObjectNodeA
                $vcfOpsNodesObject += $vcfOpsNodesObjectNodeB
                $vcfOpsNodesObject += $vcfOpsNodesObjectNodeC
            }
        }
        else
        {
            $vcfOpsNodesObject += [pscustomobject]@{
                'hostname' = $sharedInstanceObject.operations.nodeAFqdn
                'type' = 'master'
                'sslThumbprint' = $ops01fingerprint
            }
        }

        #$vcfOperationsSpecObject = @()
        $vcfOperationsSpecObject = [pscustomobject]@{
            'nodes' = $vcfOpsNodesObject
            
        }
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $vcfOperationsSpecObject | Add-Member -notepropertyName 'adminUserPassword' -NotePropertyValue $sharedInstanceObject.operations.adminUserPassword
        }
        
        If ($joinFleet -eq "N")
        {
            $vcfOperationsSpecObject | Add-Member -NotePropertyName 'applianceSize' -NotePropertyValue $sharedInstanceObject.operations.applianceSize
            $vcfOperationsSpecObject | Add-Member -NotePropertyName 'useExistingDeployment' -NotePropertyValue $sharedInstanceObject.operations.useExisting
        } 
        else 
        {
            $vcfOperationsSpecObject | Add-Member -NotePropertyName 'useExistingDeployment' -NotePropertyValue $true
        }
        If ($instanceObject.deploymentProfile.fleetManagementDeploymentModel -eq "highlyAvailable")
        {
            $vcfOperationsSpecObject | Add-Member -NotePropertyName 'loadBalancerFqdn' -NotePropertyValue $sharedInstanceObject.operations.useExisting
        }

        #vcfOperationsManagementSpec
        #$vcfOperationsManagementSpecObject = @()
        $vcfOperationsManagementSpecObject = [pscustomobject]@{
            'hostname' = $sharedInstanceObject.fleetManager.fqdn
        } 
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $vcfOperationsManagementSpecObject | Add-Member -NotePropertyName 'rootUserPassword' -NotePropertyValue $sharedInstanceObject.fleetManager.rootUserPassword
            $vcfOperationsManagementSpecObject | Add-Member -NotePropertyName 'adminUserPassword' -NotePropertyValue $sharedInstanceObject.fleetManager.adminUserPassword
        }
        
        If ($joinFleet -eq "N")
        {
            $vcfOperationsManagementSpecObject | Add-Member -NotePropertyName 'useExistingDeployment' -NotePropertyValue $false
        }
        else 
        {
            $vcfOperationsManagementSpecObject | Add-Member -NotePropertyName 'useExistingDeployment' -NotePropertyValue $true
            $vcfOperationsManagementSpecObject | Add-Member -NotePropertyName 'sslThumbprint'  -NotePropertyValue $fm01fingerprint
        }

        #vcfOperationsCloudProxySpec
        #$vcfOperationsCloudProxySpecObject = @()
        $vcfOperationsCloudProxySpecObject = [pscustomobject]@{
            'hostname' = $sharedInstanceObject.operations.opsCollectorFqdn
            'useExistingDeployment' = $false
        }
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $vcfOperationsCloudProxySpecObject | Add-Member -NotePropertyName 'rootUserPassword' -NotePropertyValue $sharedInstanceObject.operations.opsCollectorRootUserPassword
        }

        #vcfAutomationSpecObject
        $ipPoolObject = @()
        $ipPoolObject += $sharedInstanceObject.automation.nodeAIpAddress
        $ipPoolObject += $sharedInstanceObject.automation.nodeBIpAddress
        If ($instanceObject.deploymentProfile.fleetManagementDeploymentModel -eq "highlyAvailable")
        {
            $ipPoolObject += $sharedInstanceObject.automation.nodeCIpAddress
            $ipPoolObject += $sharedInstanceObject.automation.extraNodeIpAddress    
        }
        #$vcfAutomationSpecObjectObject = @()
        $vcfAutomationSpecObjectObject = [pscustomobject]@{
            'hostname' = $sharedInstanceObject.automation.vipFqdn   
            'nodePrefix' = $sharedInstanceObject.automation.vcfaNodePrefix
            
        }
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $vcfAutomationSpecObjectObject | Add-Member -NotePropertyName 'adminUserPassword' -NotePropertyValue $sharedInstanceObject.automation.adminUserPassword
        }
        If ($joinFleet -eq "N")
        {
            $vcfAutomationSpecObjectObject | Add-Member -NotePropertyName 'useExistingDeployment' -NotePropertyValue $false
            $vcfAutomationSpecObjectObject | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue $ipPoolObject
            $vcfAutomationSpecObjectObject | Add-Member -NotePropertyName 'internalClusterCidr' -NotePropertyValue $sharedInstanceObject.automation.internalClusterCidr
        }
        else 
        {
            $vcfAutomationSpecObjectObject | Add-Member -NotePropertyName 'useExistingDeployment' -NotePropertyValue $true
            $vcfAutomationSpecObjectObject | Add-Member -NotePropertyName 'sslThumbprint'  -NotePropertyValue $auto01fingerprint
        }

        #hostSpecsObject
        $hostCredentialsObject = @()
        $hostCredentialsObject += [pscustomobject]@{
            'username' = $instanceObject.hostcredentials.esxiUsername
            'password' = $instanceObject.hostcredentials.esxiPassword
        }
        $HostObject = @()
        Foreach ($hostInstance in $instanceObject.az1.rack1.hosts)
        {
            If ($interactiveEnabled -eq "Y")
            {
                If ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
                {
                    $fingerprint = (echo "Q" | openssl.exe s_client -connect "$($hostInstance.fqdn):443" -showcerts 2>$null |  Filter-X509 | openssl.exe x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]
                }
                else
                {
                    $fingerprint = (echo "Q" | openssl s_client -connect "$($hostInstance.fqdn):443" -showcerts 2>$null |  Filter-X509 | openssl x509 -noout -fingerprint -sha256).split("sha256 Fingerprint=")[1]
                }
                If ($fingerprint)
                {
                    LogMessage -Type INFO -Message "Obtaining fingerprint for host $($hostInstance.fqdn): Found"
                }
                else
                {
                    LogMessage -Type ERROR -Message "Obtaining fingerprint for host $($hostInstance.fqdn): Not found. Adding placeholder to JSON File"
                    $fingerprint = "<--ENTER-ESX-THUMBPRINT-HERE-->"
                }                
            }
            else
            {
                $fingerprint = "<--ENTER-ESX-THUMBPRINT-HERE-->"
            }
            $HostObject += [pscustomobject]@{
                'hostname'       = $hostInstance.fqdn
                'credentials'      = ($hostCredentialsObject | Select-Object -Skip 0)
                'sslThumbprint' = $fingerprint
            }
        }

        #dvsSpecsObject
        $vmotionMtu = $instanceObject.az1.rack1.network.vmotionMtu -as [int]
        $vsanMtu = $instanceObject.az1.rack1.network.vsanMtu -as [int]
        $vdsMtu = $instanceObject.vsphereClusters[0].vds[0].mtu -as [int]

        $networks = New-Object System.Collections.ArrayList
        [Array]$networks = "MANAGEMENT", "VMOTION", "VSAN","VM_MANAGEMENT"

        If ($instanceObject.vsphereClusters[0].nsxOperationDefaultMode -eq "Selected")
        {
            $operationMode = "ENS_INTERRUPT"
        }
        else
        {
            If ($instanceObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Standard")
            {
                $operationMode = "STANDARD"
            }
            elseif ($instanceObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Enhanced Datapath Standard")
            {
                $operationMode = "ENS_INTERRUPT"
            }
            else 
            {
                $operationMode = "ENS"
            }
        }

        $overlayTransportZone = [pscustomobject]@{
            'name'          = "overlay-tz-$($instanceObject.nsxtManager.hostname)"
            'transportType' = "OVERLAY"
        }
        
        
        $dvsObject = @()
        If ($instanceObject.vsphereClusters[0].vdsProfile -eq "Default")
        {
            ##### VDS 1 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-0"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $transportZoneArray += $overlayTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[0].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[0].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[0].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }
        
            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }
            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'networks' = $networks
                'mtu' = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
                'nsxTeamings' = $teamingsArray
            }
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[0].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[0].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[0].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[0].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[0].uplinkCount -as [INT]
                }
                $dvsObject[0] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }
        }
        elseif ($instanceObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic Separation")
        {
            ##### VDS 1 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-0"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $transportZoneArray += $overlayTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[0].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[0].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[0].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }
        
            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }
            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'networks' = $networks | Where-Object {$_ -in "MANAGEMENT","VM_MANAGEMENT","VMOTION"}
                'mtu' = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
                'nsxTeamings' = $teamingsArray
            }
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[0].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[0].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[0].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[0].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[0].uplinkCount -as [INT]
                }
                $dvsObject[0] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }

            ##### VDS 2 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-1"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[1].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[1].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[1].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[1].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }

            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }
            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'networks' =  @($networks | Where-Object {$_ -in "VSAN"})
                'mtu'      = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
            }
            If  ($instanceObject.vsphereClusters[0].vds[1].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[1].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[1].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[1].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[1].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[1].uplinkCount -as [INT]
                }
                If ($instanceObject.version -in "9.0.0.0","9.0.1.0")
                {
                    $dvsObject[1] | Add-Member -notePropertyName 'nsxtSwitchConfig' -notePropertyValue $nsxtSwitchConfigObject
                    $dvsObject[1] | Add-Member -notePropertyName 'nsxTeamings' -notePropertyValue $teamingsArray     
                }
                $dvsObject[1] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }
        }
        elseif ($instanceObject.vsphereClusters[0].vdsProfile -eq "NSX Traffic Separation")
        {
            ##### VDS 1 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-0"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $transportZoneArray += $overlayTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[0].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[0].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[0].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }
        
            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }
            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'networks' = $networks | Where-Object {$_ -in "MANAGEMENT","VM_MANAGEMENT","VMOTION","VSAN"}
                'mtu' = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
            }
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[0].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[0].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[0].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[0].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[0].uplinkCount -as [INT]
                }
                $dvsObject[0] | Add-Member -notePropertyName 'nsxtSwitchConfig' -notePropertyValue $nsxtSwitchConfigObject
                $dvsObject[0] | Add-Member -notePropertyName 'nsxTeamings' -notePropertyValue $teamingsArray
                $dvsObject[0] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }

            ##### VDS 2 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-1"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $transportZoneArray += $overlayTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[1].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[1].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[1].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[1].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }

            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }

            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'mtu'      = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
                'nsxTeamings' = $teamingsArray
            }
            If  ($instanceObject.vsphereClusters[0].vds[1].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[1].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[1].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[1].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[1].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[1].uplinkCount -as [INT]
                }
                $dvsObject[1] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }
        }
        else
        {
            ##### VDS 1 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-0"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[0].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[0].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[0].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }

            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      =  $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }

            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'networks' = $networks | Where-Object {$_ -in "MANAGEMENT","VM_MANAGEMENT","VMOTION"}
                'mtu'      = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
            }
            If  ($instanceObject.vsphereClusters[0].vds[0].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[0].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[0].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[0].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[0].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[0].uplinkCount -as [INT]
                }
                $dvsObject[0] | Add-Member -notePropertyName 'nsxtSwitchConfig' -notePropertyValue $nsxtSwitchConfigObject
                $dvsObject[0] | Add-Member -notePropertyName 'nsxTeamings' -notePropertyValue $teamingsArray
                $dvsObject[0] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }

            ##### VDS 2 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            $vlanTransportZone = [pscustomobject]@{
                'name'          = "nsx-vlan-transportzone-1"
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[1].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[1].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[1].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[1].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }
 
           $vmnicObject = @()
           $vmnicObject += [pscustomobject]@{
               'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
               'uplink' = $uplink1Name
           }
           $vmnicObject += [pscustomobject]@{
               'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
               'uplink' = $uplink2Name
           }
           $dvsObject += [pscustomobject]@{
               'dvsName'  = $instanceObject.vsphereClusters[0].vds[1].vdsName
               'networks' =  @($networks | Where-Object {$_ -in "VSAN"})
               'mtu'      = $vdsMtu
               'vmnicsToUplinks' = $vmnicObject
           }
           If  ($instanceObject.vsphereClusters[0].vds[1].type -eq "VDS LAG")
           {
               $lagSpecsObject = @()
               $lagSpecsObject += [pscustomobject]@{
                   'name' = $instanceObject.vsphereClusters[0].vds[1].lagName
                   'lacpMode' = ($instanceObject.vsphereClusters[0].vds[1].lagMode).toUpper()
                   'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[1].lagLoadBalancing).replace(" ","_")).toUpper()
                   'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[1].lagTimeout).toUpper()
                   'uplinksCount' = $instanceObject.vsphereClusters[0].vds[1].uplinkCount -as [INT]
               }
               If ($instanceObject.version -in "9.0.0.0","9.0.1.0")
               {
                   $dvsObject[1] | Add-Member -notePropertyName 'nsxtSwitchConfig' -notePropertyValue $nsxtSwitchConfigObject
                   $dvsObject[1] | Add-Member -notePropertyName 'nsxTeamings' -notePropertyValue $teamingsArray     
               }
               $dvsObject[1] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
           }

            ##### VDS 3 #####
            #Figure out nsxtSwitchConfig
            $nsxtSwitchConfigObject = New-Object -type psobject
            If ($instanceObject.version -in "9.0.0.0","9.0.1.0")
            {
                $vlanTransportZoneName = "nsx-vlan-transportzone-2"
            }
            else 
            {
                $vlanTransportZoneName = "nsx-vlan-transportzone-1"
            }
            $vlanTransportZone = [pscustomobject]@{
                'name'          = $vlanTransportZoneName
                'transportType' = "VLAN"
            }
            $transportZoneArray = @()
            $transportZoneArray += $vlanTransportZone
            $transportZoneArray += $overlayTransportZone
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
            $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode

            #figure out teamingArray
            If  ($instanceObject.vsphereClusters[0].vds[2].type -eq "VDS LAG")
            {
                $activeUplinksArray = @($instanceObject.vsphereClusters[0].vds[2].lagName)
                $policy = "FAILOVER_ORDER"
                $uplink1Name = "$($instanceObject.vsphereClusters[0].vds[2].lagName)-0"
                $uplink2Name= "$($instanceObject.vsphereClusters[0].vds[2].lagName)-1"
            }
            else
            {
                $activeUplinksArray = @("uplink1","uplink2")
                $policy = "LOADBALANCE_SRCID"
                $uplink1Name = "uplink1"
                $uplink2Name= "uplink2"
            }
            $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'policy' = $policy
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }

            $vmnicObject = @()
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[2].pnics.split(",")[0]
                'uplink' = $uplink1Name
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[2].pnics.split(",")[1]
                'uplink' = $uplink2Name
            }

            $dvsObject += [pscustomobject]@{
                'dvsName'  = $instanceObject.vsphereClusters[0].vds[2].vdsName
                'mtu'      = $vdsMtu
                'vmnicsToUplinks' = $vmnicObject
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
                'nsxTeamings' = $teamingsArray
            }
            If  ($instanceObject.vsphereClusters[0].vds[2].type -eq "VDS LAG")
            {
                $lagSpecsObject = @()
                $lagSpecsObject += [pscustomobject]@{
                    'name' = $instanceObject.vsphereClusters[0].vds[2].lagName
                    'lacpMode' = ($instanceObject.vsphereClusters[0].vds[2].lagMode).toUpper()
                    'loadBalancingMode' = (($instanceObject.vsphereClusters[0].vds[2].lagLoadBalancing).replace(" ","_")).toUpper()
                    'lacpTimeoutMode' = ($instanceObject.vsphereClusters[0].vds[2].lagTimeout).toUpper()
                    'uplinksCount' = $instanceObject.vsphereClusters[0].vds[2].uplinkCount -as [INT]
                }
                $dvsObject[2] | Add-Member -notePropertyName 'lagSpecs' -notePropertyValue $lagSpecsObject
            }
        }

        #networkSpecsObject
        $vmotionIpObject = @()
        $vmotionIpObject += [pscustomobject]@{
            'startIpAddress' = $instanceObject.az1.rack1.network.vmotionPoolStartIP
            'endIpAddress'   = $instanceObject.az1.rack1.network.vmotionPoolEndIP
        }

        $vsanIpObject = @()
        $vsanIpObject += [pscustomobject]@{
            'startIpAddress' = $instanceObject.az1.rack1.network.vsanPoolStartIP
            'endIpAddress'   = $instanceObject.az1.rack1.network.vsanPoolEndIP
        }

        $networkObject = @()
        $networkObject += [pscustomobject]@{
            'networkType'  = "VM_MANAGEMENT"
            'subnet' = $instanceObject.az1.rack1.network.mgmtVmCidr
            'gateway' = $instanceObject.az1.rack1.network.mgmtVmGw
            'subnetMask' = $null
            'includeIpAddress' = $null
            'includeIpAddressRanges' =$null
            'vlanId' = $instanceObject.az1.rack1.network.mgmtVmVlanID -as [int]
            'mtu' = $instanceObject.az1.rack1.network.mgmtVmMtu -as [int]
            'teamingPolicy' =  'loadbalance_loadbased'
            'activeUplinks' = $activeUplinksArray
            'standbyUplinks' = $null
            'portGroupKey' = $instanceObject.vsphereClusters[0].portgroupNames.az1.mgmtVm
        } 
        $networkObject += [pscustomobject]@{
            'networkType'  = "MANAGEMENT"
            'subnet' = $instanceObject.az1.rack1.network.mgmtCidr
            'gateway' = $instanceObject.az1.rack1.network.mgmtGw
            'subnetMask' = $null
            'includeIpAddress' = $null
            'includeIpAddressRanges' =$null
            'vlanId' = $instanceObject.az1.rack1.network.mgmtVlanID -as [int]
            'mtu' = $instanceObject.az1.rack1.network.mgmtMtu -as [int]
            'teamingPolicy' =  'loadbalance_loadbased'
            'activeUplinks' = $activeUplinksArray
            'standbyUplinks' = $null
            'portGroupKey' = $instanceObject.vsphereClusters[0].portgroupNames.az1.mgmt
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "VMOTION"
            'subnet'  = $instanceObject.az1.rack1.network.vmotionCidr
            'gateway' = $instanceObject.az1.rack1.network.vmotionGw
            'subnetMask' = $null
            'includeIpAddress' = $null
            'includeIpAddressRanges' = $vmotionIpObject
            'vlanId' = $instanceObject.az1.rack1.network.vmotionVlanID -as [int]
            'mtu' = $vmotionMtu
            'teamingPolicy' =  'loadbalance_loadbased'
            'activeUplinks' = $activeUplinksArray
            'standbyUplinks' = $null
            'portGroupKey' = $instanceObject.vsphereClusters[0].portgroupNames.az1.vmotion
        }
        $networkObject += [pscustomobject]@{
            'networkType'          = "VSAN"
            'subnet'               = $instanceObject.az1.rack1.network.vsanCidr
            'gateway'              = $instanceObject.az1.rack1.network.vsanGw
            'subnetMask' = $null
            'includeIpAddress' = $null
            'includeIpAddressRanges' = $vsanIpObject
            'vlanId'               = $instanceObject.az1.rack1.network.vsanVlanID  -as [int]
            'mtu'                  = $vsanMtu
            'teamingPolicy' =  'loadbalance_loadbased'
            'activeUplinks' = $activeUplinksArray
            'standbyUplinks' = $null
            'portGroupKey' = $instanceObject.vsphereClusters[0].portgroupNames.az1.vsan
        }

        # Update activeUplinks if Lag is required
        Foreach ($network in $networkObject)
        {
            $networkType = $network.networkType
            $matchingDvsSpec = $dvsObject | Where-Object { $networkType -in $_.networks } | Select-Object -First 1
            $dvsName = $matchingDvsSpec.dvsName
            $matchingVds = $instanceObject.vsphereClusters[0].vds | Where-Object { $_.vdsName -eq $dvsName } | Select-Object -First 1
            If ($matchingVds.type -eq "VDS LAG")
            {
                $network.activeUplinks = @($matchingVds.lagName)
                $network.teamingPolicy = "failover_explicit"
            }
            else
            {
                $network.activeUplinks = @("uplink1", "uplink2")
            }
        }

        #sddcManagerSpecObject
        $rootUserObject = @()
        $rootUserObject += [pscustomobject]@{
            'username' = "root"
            'password' = $instanceObject.sddcManager.rootPassword
        }

        $secondUserObject = @()
        $secondUserObject += [pscustomobject]@{
            'username' = "vcf"
            'password' = $instanceObject.sddcManager.vcfPassword
        }

        $localAdminObject = @()
        $localAdminObject += [pscustomobject]@{
            'username' = "admin"
            'password' = $instanceObject.sddcManager.localAdminPassword
        }

        #$sddcManagerObject = @()
        $sddcManagerObject = [pscustomobject]@{
            'hostname'            = $instanceObject.sddcManager.fqdn
            'useExistingDeployment' = $false
        }
        If ($instanceObject.autoGeneratedPasswords -ne "Selected")
        {
            $sddcManagerObject | Add-Member -notepropertyName 'rootPassword' -NotePropertyValue $instanceObject.sddcManager.rootPassword
            $sddcManagerObject | Add-Member -notepropertyName 'sshPassword' -NotePropertyValue $instanceObject.sddcManager.vcfPassword
            $sddcManagerObject | Add-Member -notepropertyName 'localUserPassword' -NotePropertyValue $instanceObject.sddcManager.localAdminPassword
        }

        #final spec
        $ceipState = $instanceObject.vcenterServer.ceipStatus
        If ($ceipState -eq "Selected") {
            $ceipEnabled = "$true"
        }
        else {
            $ceipEnabled = "$false"
        }

        $managementDomainObject = New-Object -TypeName psobject
        $managementDomainObject | Add-Member -notepropertyname 'sddcId' -notepropertyvalue $instanceObject.domainName
        $managementDomainObject | Add-Member -notepropertyname 'vcfInstanceName' -notepropertyvalue $instanceObject.vcfInstanceName
        If ($instanceObject.instance -eq "First Instance")
        {
            $managementDomainObject | Add-Member -notepropertyname 'workflowType' -notepropertyvalue "VCF"
        }
        else
        {
            $managementDomainObject | Add-Member -notepropertyname 'workflowType' -notepropertyvalue "VCF_EXTEND"
        }

        $managementDomainObject | Add-Member -notepropertyname 'version' -notepropertyvalue $instanceObject.version
        $managementDomainObject | Add-Member -notepropertyname 'ceipEnabled' -notepropertyvalue $ceipEnabled
        #$managementDomainObject | Add-Member -notepropertyname 'managementPoolName' -notepropertyvalue $instanceObject.az1.rack1.network.vcfNetworkPoolName
        $managementDomainObject | Add-Member -notepropertyname 'managementPoolName' -notepropertyvalue "$($instanceObject.domainName)-network-pool-01"
        $managementDomainObject | Add-Member -notepropertyname 'dnsSpec' -notepropertyvalue ($dnsObject | Select-Object -Skip 0)
        $managementDomainObject | Add-Member -notepropertyname 'ntpServers' -notepropertyvalue $ntpServers
        $managementDomainObject | Add-Member -notepropertyname 'vcenterSpec' -notepropertyvalue $vcenterObject
        $managementDomainObject | Add-Member -notepropertyname 'clusterSpec' -notepropertyvalue ($clusterObject | Select-Object -Skip 0)
        $managementDomainObject | Add-Member -notepropertyname 'datastoreSpec' -notepropertyvalue ($datastoreSpecObject | Select-Object -Skip 0)
        $managementDomainObject | Add-Member -notepropertyname 'nsxtSpec' -notepropertyvalue $nsxtObject
        If (($instanceObject.deploymentProfile.fleetManagementTiming -ne "later") -and (($instanceObject.instance -eq "First Instance") -OR (($instanceObject.instance -eq "Additional Instance") -AND ($joinFleet -eq "Y")))){$managementDomainObject | Add-Member -notepropertyname 'vcfOperationsSpec' -notepropertyvalue $vcfOperationsSpecObject}
        If (($instanceObject.deploymentProfile.fleetManagementTiming -ne "later") -and (($instanceObject.instance -eq "First Instance") -OR (($instanceObject.instance -eq "Additional Instance") -AND ($joinFleet -eq "Y")))) {$managementDomainObject | Add-Member -notepropertyname 'vcfOperationsFleetManagementSpec' -notepropertyvalue $vcfOperationsManagementSpecObject}
        If (($instanceObject.deploymentProfile.fleetManagementTiming -ne "later") -and (($instanceObject.instance -eq "First Instance") -OR (($instanceObject.instance -eq "Additional Instance") -AND ($joinFleet -eq "Y")))) {$managementDomainObject | Add-Member -notepropertyname 'vcfOperationsCollectorSpec' -notepropertyvalue $vcfOperationsCloudProxySpecObject}
        If ((($instanceObject.deploymentProfile.fleetManagementTiming -ne "later") -and ($instanceObject.instance -eq "First Instance") -AND ($skipAutomation -ne 'Y')) -or (($instanceObject.instance -eq "Additional Instance") -and ($joinFleet -eq "Y") -AND ($skipAutomation -ne 'Y'))) {$managementDomainObject | Add-Member -notepropertyname 'vcfAutomationSpec' -notepropertyvalue $vcfAutomationSpecObjectObject}
        $managementDomainObject | Add-Member -notepropertyname 'hostSpecs' -notepropertyvalue $hostObject
        $managementDomainObject | Add-Member -notepropertyname 'networkSpecs' -notepropertyvalue $networkObject
        $managementDomainObject | Add-Member -notepropertyname 'dvsSpecs' -notepropertyvalue $dvsObject
        $managementDomainObject | Add-Member -notepropertyname 'sddcManagerSpec' -notepropertyvalue $sddcManagerObject

        LogMessage -Type INFO -Message "Exporting the Management Domain JSON to managementDomainSpec-$($instanceObject.domainName).json"
        $managementDomainObject | ConvertTo-Json -Depth 12 | Out-File -Encoding UTF8 -FilePath "managementDomainSpec-$($instanceObject.domainName).json"
        LogMessage -Type NOTE -Message "Completed the Process of Generating the Management Domain JSON"
    }
    Catch {
        catchWriter -object $_
    }
}

Function New-WorkloadDomainJsonFile 
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$instanceObject
    )

    Try 
    {
        LogMessage -type INFO -message "Generating Workload Domain JSON"
        Do
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve host and personality IDs from SDDC Manager? (Y/N): " -skipnewline
            $interactiveEnabled = Read-Host    
        } Until ($interactiveEnabled -in "Y","N")
        $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
        If ($interactiveEnabled -eq "Y")
        {
            Do
            {
                LogMessage -type INFO -message "SDDC Manager FQDN: " -skipnewline
                $sddcMgrFqdn = Read-Host
                LogMessage -type INFO -message "SDDC Manager Administrator: " -skipnewline
                $sddcMgrUser = Read-Host
                LogMessage -type INFO -message "SDDC Manager Administrator password: " -skipnewline
                $adminPassword = Read-Host -AsSecureString
                $decodedPassword = New-DecodedPassword -securePassword $adminPassword
                New-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $decodedPassword *>$null
                If (!($accessToken))
                {
                    LogMessage -type ERROR -message "Failed to connect to $sddcMgrFqdn. Please check details and try again"
                }
            } Until ($accessToken)
        }

        $nsxtNode1Object = @()
        $nsxtNode1Object += [pscustomobject]@{
            'ipAddress'  = $instanceObject.nsxtManager.nodeAIpAddress
            'dnsName'    = $instanceObject.nsxtManager.nodeAFQDN
        }

        $nsxtNode2Object = @()
        $nsxtNode2Object += [pscustomobject]@{
            'ipAddress'  = $instanceObject.nsxtManager.nodeBIpAddress
            'dnsName'    = $instanceObject.nsxtManager.nodeBFQDN
        }

        $nsxtNode3Object = @()
        $nsxtNode3Object += [pscustomobject]@{
            'ipAddress'  = $instanceObject.nsxtManager.nodeCIpAddress
            'dnsName'    = $instanceObject.nsxtManager.nodeCFQDN
        }

        $nsxtManagerObject = @()
        $nsxtManagerObject += [pscustomobject]@{
            'name'             = $instanceObject.nsxtManager.nodeAHostname
            'networkDetailsSpec' = ($nsxtNode1Object | Select-Object -Skip 0)
        }
        If ($instanceObject.deploymentProfile.singleNSXTManager -eq "N")
        {
            $nsxtManagerObject += [pscustomobject]@{
                'name'             = $instanceObject.nsxtManager.nodeBHostname
                'networkDetailsSpec' = ($nsxtNode2Object | Select-Object -Skip 0)
            }
            $nsxtManagerObject += [pscustomobject]@{
                'name'             = $instanceObject.nsxtManager.nodeCHostname
                'networkDetailsSpec' = ($nsxtNode3Object | Select-Object -Skip 0)
            }
        }
        
        $nsxtObject = @()
        $nsxtObject += [pscustomobject]@{
            'formFactor'              = $instanceObject.nsxtManager.formFactor
            'nsxManagerSpecs'         = $nsxtManagerObject
            'vip'                     = $instanceObject.nsxtManager.ipAddress
            'vipFqdn'                 = $instanceObject.nsxtManager.fqdn
            'nsxManagerAdminPassword' = $instanceObject.nsxtManager.adminPassword
        }

        $vmnicObject = @()
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[0].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[0].vdsName
            'uplink' = "uplink2"
        }
        If ($instanceObject.vsphereClusters[0].vdsProfile -in "Storage Traffic Separation","NSX Traffic Separation")
        {
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
                'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'uplink' = "uplink1"
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
                'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'uplink' = "uplink2"
            }
        }
        If ($instanceObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic and NSX Traffic Separation")
        {
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
                'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'uplink' = "uplink1"
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
                'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'uplink' = "uplink2"
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[2].pnics.split(",")[0]
                'vdsName' = $instanceObject.vsphereClusters[0].vds[2].vdsName
                'uplink' = "uplink1"
            }
            $vmnicObject += [pscustomobject]@{
                'id'      = $instanceObject.vsphereClusters[0].vds[2].pnics.split(",")[1]
                'vdsName' = $instanceObject.vsphereClusters[0].vds[2].vdsName
                'uplink' = "uplink2"
            }
        }

        $hostArray = @()
        $hostCounter = 0
        $maxClusterNodeCount = 64
        $rackArray = @(($instanceObject.az1 | Get-Member -type NoteProperty).name)
        Foreach ($rack in $rackArray)
        {
            $selectedHosts = @(0..$([INT]$instanceObject.az1.$($rack).hosts.count -1))
            If ((($instanceObject.rackInformation.dedicatedEdgeClusters -eq $true ) -AND ($rack -ne $instanceObject.rackInformation.edgeRackFirst) -AND ($rack -ne $instanceObject.rackInformation.edgeRackSecond)) -OR ($instanceObject.rackInformation.dedicatedEdgeClusters -eq $false ))
            {
                Foreach ($selectedHost in $selectedHosts)
                {
                    $hostnetworkObject = @()
                    $hostnetworkObject += [pscustomobject]@{
                        'vmNics' = $vmnicObject
                    }
                    If ($instanceObject.rackinformation.multiRackChosen -eq "Y")
                    {
                        $hostnetworkObject | Add-Member -notepropertyName 'networkProfileName' -NotePropertyValue $instanceObject.az1.$($rack).network.networkProfileName
                    }

                    If ($interactiveEnabled -eq "Y")
                    {
                        $hostID = Get-VCFHostDetails -Status UNASSIGNED_USEABLE | Select-Object fqdn, id | Where-Object { $_.fqdn -eq $instanceObject.az1.$($rack).hosts[$selectedHost].fqdn }
                        If ($hostID)
                        {
                            LogMessage -Type INFO -Message "Obtaining Host ID from SDDC Manager for host $($instanceObject.az1.$($rack).hosts[$selectedHost].fqdn): Found"
                            $hostIdValue = $hostId.id
                        }
                        else
                        {
                            LogMessage -Type WARNING -Message "Obtaining Host ID from SDDC Manager for host $($instanceObject.az1.$($rack).hosts[$selectedHost].fqdn): Not found. Not adding to JSON File"
                            $hostIdValue = "None Found"
                        }
                    }
                    else
                    {
                        $hostIdValue = "<--ENTER-SDDC-HOSTID-HERE-->"
                    }
                    If ($hostIdValue -ne "None Found")
                    {
                        $newHost = [pscustomobject]@{
                            'id'                = "$hostIdValue"
                            'hostname'          = $instanceObject.az1.$($rack).hosts[$selectedHost].fqdn
                            'hostNetworkSpec'   = ($hostnetworkObject | Select-Object -Skip 0)
                        }
                        $hostArray += $newHost
                    }
                    $hostCounter++
                }
            }
        }
        If ($hostCounter -gt $maxClusterNodeCount)
        {
            LogMessage -type ERROR -message "Your cluster configuration exceeds the maximum limit of $maxClusterNodeCount. Please adjust the total node count across racks and retry"
        }

        $activeUplinksArray = @()
        $activeUplinksArray += "uplink1"
        $activeUplinksArray += "uplink2"

        $portgroupObject = @()
        $portgroupObject += [pscustomobject]@{
            'name'          = $instanceObject.vsphereClusters[0].portgroupNames.az1.mgmt
            'transportType' = "MANAGEMENT"
            'standByUplinks' = @()
            'teamingPolicy' = "loadbalance_loadbased"
            'activeUplinks' = $activeUplinksArray
        }
        $portgroupObject += [pscustomobject]@{
            'name'          = $instanceObject.vsphereClusters[0].portgroupNames.az1.vmotion
            'transportType' = "VMOTION"
            'standByUplinks' = @()
            'teamingPolicy' = "loadbalance_loadbased"
            'activeUplinks' = $activeUplinksArray
        }
        $portgroupObject += [pscustomobject]@{
            'name'          = $instanceObject.vsphereClusters[0].portgroupNames.az1.vsan
            'transportType' = "VSAN"
            'standByUplinks' = @()
            'teamingPolicy' = "loadbalance_loadbased"
            'activeUplinks' = $activeUplinksArray
        }
        
        If (($instanceObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster") -and ($instanceObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network") -and ($instanceObject.vsphereClusters[0].vdsProfile -ne "Default"))
        {
            $portgroupObject += [pscustomobject]@{
                'name'          = $instanceObject.vsphereClusters[0].portgroupNames.az1.vsanClient
                'transportType' = "VSAN_EXTERNAL"
                'standByUplinks' = @()
                'teamingPolicy' = "loadbalance_loadbased"
                'activeUplinks' = $activeUplinksArray
            }
        }
        
        $vdsMtu = $([INT]$instanceObject.vsphereClusters[0].vds[0].mtu)
        $transportZoneArray = @()
        $transportZoneArray += [pscustomobject]@{
            'name'          = "nsx-vlan-transportzone"
            'transportType' = "VLAN"
        }
        $transportZoneArray += [pscustomobject]@{
            'name'          = "overlay-tz-$($instanceObject.nsxtManager.hostname)"
            'transportType' = "OVERLAY"
        }
        
        $nsxtSwitchConfigObject = New-Object -type psobject
        If ($instanceObject.vsphereClusters[0].nsxOperationDefaultMode -eq "Selected")
        {
            $operationMode = "ENS_INTERRUPT"
        }
        else
        {
            If ($instanceObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Standard")
            {
                $operationMode = "STANDARD"
            }
            elseif ($instanceObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Enhanced Datapath Standard")
            {
                $operationMode = "ENS_INTERRUPT"
            }
            else 
            {
                < $operationMode = "ENS"
            }
        }
        $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode
        $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray

        $vdsObject = @()
        If ($instanceObject.vsphereClusters[0].vdsProfile -eq "Default")
        {
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'mtu' = $vdsMtu
                'portGroupSpecs' = $portgroupObject
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
            }
        }
        elseif ($instanceObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic Separation")
        {
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'mtu' = $vdsMtu
                'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
            }
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'mtu' = $vdsMtu
                'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
            }
        }
        elseif ($instanceObject.vsphereClusters[0].vdsProfile -eq "NSX Traffic Separation")
        {
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'mtu' = $vdsMtu
                'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN","VSAN_EXTERNAL"}
            }
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'mtu' = $vdsMtu
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
            }
        }
        else
        {
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[0].vdsName
                'mtu' = $vdsMtu
                'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
            }
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[1].vdsName
                'mtu' = $vdsMtu
                'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
            }
            $vdsObject += [pscustomobject]@{
                'name'         = $instanceObject.vsphereClusters[0].vds[2].vdsName
                'mtu' = $vdsMtu
                'nsxtSwitchConfig' = $nsxtSwitchConfigObject
            }
        }

        $vdsUplinkToNsxUplinkArray = @()
        $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
            'nsxUplinkName' = "uplink1"
            'vdsUplinkName' = "uplink1"
        }
        $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
            'nsxUplinkName' = "uplink2"
            'vdsUplinkName' = "uplink2"
        }

        If ($instanceObject.vsphereClusters[0].vdsProfile -in "NSX Traffic Separation")
        {
            $vdsName = $instanceObject.vsphereClusters[0].vds[1].vdsName
        }
        elseIf ($instanceObject.vsphereClusters[0].vdsProfile -in "Storage Traffic and NSX Traffic Separation")
        {
            $vdsName = $instanceObject.vsphereClusters[0].vds[2].vdsName
        }
        else
        {
            $vdsName = $instanceObject.vsphereClusters[0].vds[0].vdsName
        }

        $rackArray = @(($instanceObject.az1 | Get-Member -type NoteProperty).name)
        
        $networkProfilesArray = @()
        Foreach ($rack in $rackArray)
        {
            If ($instanceObject.az1.rack1.network.hostOverlayAddressing -eq "Static IP Pool")
            {
                $ipaddressPoolName = $instanceObject.az1.$($rack).network.hostIpAddressPoolName
            }
            else
            {
                $ipaddressPoolName = $null
            }
            $nsxtHostSwitchConfigs = @()
            $nsxtHostSwitchConfigs += [pscustomobject]@{
                'ipAddressPoolName' = $ipaddressPoolName
                'uplinkProfileName' = $instanceObject.az1.$($rack).network.uplinkProfileName
                'vdsName' = $vdsName
                'vdsUplinkToNsxUplink' = $vdsUplinkToNsxUplinkArray
            }
                            
            $rackNetworkProfile = New-Object -type psobject
            $rackNetworkProfile | Add-Member -NotePropertyName 'isDefault' -NotePropertyValue $(If ($networkProfilesArray.count -eq 0) {$true} else {$false})
            $rackNetworkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $instanceObject.az1.$($rack).network.networkProfileName
            $rackNetworkProfile | Add-Member -NotePropertyName 'nsxtHostSwitchConfigs' -NotePropertyValue $nsxtHostSwitchConfigs
            $networkProfilesArray += $rackNetworkProfile
        }

        If ($instanceObject.az1.rack1.network.hostOverlayAddressing -eq "Static IP Pool")
        {
            $ipAddressPoolsSpecArray = @()
            Foreach ($rack in $rackArray)
            {
                If ($instanceObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
                {
                    $ipAddressPoolRangesArray = @()
                    $ipAddressPoolRangesArray += [pscustomobject]@{
                        'start' = $instanceObject.az1.$($rack).network.hostOverlayPoolStartIP
                        'end' = $instanceObject.az1.$($rack).network.hostOverlayPoolEndIP
                    }
                    
                    $subnetsArray = @()
                    $subnetsArray += [pscustomobject]@{
                        'cidr' = $instanceObject.az1.$($rack).network.hostOverlayCidr
                        'gateway' = $instanceObject.az1.$($rack).network.hostOverlayGw
                        'ipAddressPoolRanges' = $ipAddressPoolRangesArray
                    }
                }
                $ipAddressSpec = New-Object -type PSObject
                $ipAddressSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $instanceObject.az1.$($rack).network.hostIpAddressPoolName
                If ($instanceObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
                {
                    $ipAddressSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
                }
                $ipAddressPoolsSpecArray += $ipAddressSpec
            }
        }
        else
        {
            $ipAddressPoolsSpecArray = $null
        }

        $teamingsArray = @()
        $teamingsArray += [pscustomobject]@{
            'name' = "DEFAULT"
            'policy' = "LOADBALANCE_SRCID"
            'standByUplinks' = @()
            'activeUplinks' = $activeUplinksArray
        }

        $uplinkProfilesArray = @()
        Foreach ($rack in $rackArray)
        {
            If ((($instanceObject.rackInformation.dedicatedEdgeClusters -eq $true ) -AND ($rack -ne $instanceObject.rackInformation.edgeRackFirst) -AND ($rack -ne $instanceObject.rackInformation.edgeRackSecond)) -OR ($instanceObject.rackInformation.dedicatedEdgeClusters -eq $false))
            {
                $uplinkProfile = New-Object -type PSObject
                $uplinkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $instanceObject.az1.$($rack).network.uplinkProfileName
                $uplinkProfile | Add-Member -NotePropertyName 'transportVlan' -NotePropertyValue $([INT]($instanceObject.az1.$($rack).network.hostOverlayVlanID))
                $uplinkProfile | Add-Member -NotePropertyName 'teamings' -NotePropertyValue $teamingsArray
                $uplinkProfilesArray += $uplinkProfile
            }
        }

        $nsxTClusterObject = @()
        $nsxTClusterObject += [pscustomobject]@{
            'ipAddressPoolsSpec' = $ipAddressPoolsSpecArray
            'uplinkProfiles' = $uplinkProfilesArray
        }

        $nsxClusterObject = @()
        $nsxClusterObject += [pscustomobject]@{
            'nsxTClusterSpec' = ($nsxTClusterObject | Select-Object -Skip 0)
        }

        $networkObject = @()
        $networkObject += [pscustomobject]@{
            'vdsSpecs'       = $vdsObject
            'networkProfiles' = @($networkProfilesArray | Select-Object)
            'nsxClusterSpec' = ($nsxClusterObject | Select-Object -Skip 0)
        }

        If ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-ESA")
        {
            $ESAenabledtrueobject = @()
            $ESAenabledtrueobject  += [pscustomobject]@{
                'enabled' = "true"
            }                    
        }
        elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster")
        {
            $vsanMaxConfigObject = New-Object -type psobject
            If ($instanceObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network")
            {
                $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanExternalNetwork' -NotePropertyValue $true
            }
            else
            {
                $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanExternalNetwork' -NotePropertyValue $false
            }
            $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanMax' -NotePropertyValue $true
            $ESAenabledtrueobject = @()
            $ESAenabledtrueobject  += [pscustomobject]@{
                'enabled' = "true"
                'vsanMaxConfig' = $vsanMaxConfigObject
            }  
        }
        elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-OSA")
        {
            $ESAenabledtrueobject = @()
            $ESAenabledtrueobject  += [pscustomobject]@{
                'enabled' = "false"
            } 
        }

        $vsanDatastoreObject = @()
        If ($instanceObject.vsphereClusters[0].storageModel -in "VSAN-ESA","vSAN Storage Cluster")
        {
            $vsanDatastoreObject += [pscustomobject]@{
            'datastoreName'      = $instanceObject.vsphereClusters[0].vsanDatastore
            'esaConfig' =  ($ESAenabledtrueobject | Select-Object -Skip 0)
            }
        }
        elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-OSA") 
        {
            $vsanDatastoreObject += [pscustomobject]@{
            'failuresToTolerate' = "1"
            'datastoreName'      = $instanceObject.vsphereClusters[0].vsanDatastore
            }
        }
        
        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanDatastoreSpec' = ($vsanDatastoreObject | Select-Object -Skip 0)
        }

        $clusterObject = @()
        $clusterObject += [pscustomobject]@{
            'name'        = $instanceObject.vsphereClusters[0].clusterName
            'hostSpecs'     = $hostArray
            'datastoreSpec' = ($vsanObject | Select-Object -Skip 0)
            'networkSpec'   = ($networkObject | Select-Object -Skip 0)
        }

        If ($instanceObject.vsphereClusters[0].vlcmModel -eq "Images") 
        {
            If ($interactiveEnabled -eq "Y")
            {
                LogMessage -Type INFO -Message "Obtaining Cluster Image Personality ID from SDDC Manager"
                $clusterImageId = (Get-VCFPersonalityDetails | Where-Object { $_.personalityName -eq $instanceObject.vsphereClusters[0].imageName }).personalityId
            }
            else
            {
                $clusterImageId = "<--ENTER-SDDC-PERSONALITY-NAME-HERE-->"
            }
            $clusterObject[0] | Add-Member -NotePropertyName 'clusterImageId' -NotePropertyValue $clusterImageId
        }

        $computeObject = @()
        $computeObject += [pscustomobject]@{
            'clusterSpecs' = $clusterObject
        }

        $vcenterNetworkObject = @()
        $vcenterNetworkObject += [pscustomobject]@{
            'ipAddress'  = $instanceObject.vcenterServer.ipAddress
            'dnsName'    = $instanceObject.vcenterServer.fqdn
        }

        $vcenterObject = @()
        $vcenterObject += [pscustomobject]@{
            'name'             = $instanceObject.vcenterServer.hostname
            'networkDetailsSpec' = ($vcenterNetworkObject | Select-Object -Skip 0)
            'rootPassword'     = $($instanceObject.vcenterServer.rootPassword)
            'datacenterName'   = $instanceObject.vcenterServer.datacenter
            'vmSize'   = $instanceObject.vcenterServer.vcenterSize
            }

        If ($instanceObject.vcenterServer.vcenterSize -eq "large")
        {
            $vcenterObject[0] | Add-Member -notepropertyName 'storageSize' -NotePropertyValue "lstorage"
        }
        elseif ($instanceObject.vcenterServer.vcenterSize -eq "xlarge")
        {
            $vcenterObject[0] | Add-Member -notepropertyName 'storageSize' -NotePropertyValue "xlstorage"
        }

        #review
        $ssoDomainSpecObject = @()
        $ssoDomainSpecObject += [pscustomobject]@{
            'ssoDomainName' = $instanceObject.sso.domain
            'ssoDomainPassword' = $instanceObject.sso.adminPassword
        }

        $workloadDomainObject = @()
        $workloadDomainObject += [pscustomobject]@{
            'domainName' = $instanceObject.domainName
            'vcenterSpec'  = ($vcenterObject | Select-Object -Skip 0)
            'computeSpec'  = ($computeObject | Select-Object -Skip 0)
            'nsxTSpec'     = ($nsxtObject | Select-Object -Skip 0)
        }

        $workloadDomainObject[0] | Add-Member -NotePropertyName 'ssoDomainSpec' -NotePropertyValue ($ssoDomainSpecObject | Select-Object -Skip 0)
        $workloadDomainObject[0] | Add-Member -NotePropertyName 'deployWithoutLicenseKeys' -NotePropertyValue "true"

        LogMessage -Type INFO -Message "Exporting the Workload Domain JSON to workloadDomainSpec-$($instanceObject.domainName).json"
        $workloadDomainObject | ConvertTo-Json -Depth 12 | Out-File -Encoding UTF8 -FilePath "workloadDomainSpec-$($instanceObject.domainName).json"
        LogMessage -Type NOTE -Message "Completed the Process of Generating the Workload Domain JSON"
    }
    Catch 
    {
        catchWriter -object $_
    }
}

# SDDC Manager Supporting Functions
Function New-NetworkPoolJsonFile 
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$instanceObject
        )

    Try {
        LogMessage -type INFO -message "Generating Required Network Pool JSON files"      
        $selectedRackArray = @(($instanceObject.az1 | Get-Member -type NoteProperty).name)
        Foreach ($rack in $selectedRackArray)
        {
            Foreach ($az in "az1","az2")
            {
                If ($instanceObject.$($az).$($rack).network.reuseExistingVcfNetworkPool -in "Exclude","Create a new VCF Network Pool")
                {
                    $vmotionIpPoolObject = @()
                    $vmotionIpPoolObject += [pscustomobject]@{
                        'start' = $instanceObject.$($az).$($rack).network.vmotionPoolStartIP
                        'end'   = $instanceObject.$($az).$($rack).network.vmotionPoolEndIP
                    }
            
                    $vsanIpPoolObject = @()
                    $vsanIpPoolObject += [pscustomobject]@{
                        'start' = $instanceObject.$($az).$($rack).network.vsanPoolStartIP
                        'end'   = $instanceObject.$($az).$($rack).network.vsanPoolEndIP
                    }
                    
                    If (($instanceObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster") -and ($instanceObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network"))
                    {
                        $secondaryStorageIpPoolObject = @()
                        $secondaryStorageIpPoolObject += [pscustomobject]@{
                            'start' = $instanceObject.$($az).$($rack).network.secondaryStoragePoolStartIp
                            'end'   = $instanceObject.$($az).$($rack).network.secondaryStoragePoolEndIp
                        }
                    }
            
                    $vmotionMtu = $instanceObject.$($az).$($rack).network.vmotionMtu -as [string]
                    $vsanMtu = $instanceObject.$($az).$($rack).network.vsanMtu -as [string]
                    $secondaryStorageMtu = $instanceObject.$($az).$($rack).network.secondaryStorageMtu -as [string]
            
                    $networkObject = @()
                    $networkObject += [pscustomobject]@{
                        'type'    = "VMOTION"
                        'vlanId'  = $instanceObject.$($az).$($rack).network.vmotionVlanID
                        'mtu'     = $vmotionMtu
                        'subnet'  = $instanceObject.$($az).$($rack).network.vmotionNetwork
                        'mask'    = $instanceObject.$($az).$($rack).network.vmotionNetmask
                        'gateway' = $instanceObject.$($az).$($rack).network.vmotionGw
                        'ipPools'   = $vmotionIpPoolObject
                    }
                    $networkObject += [pscustomobject]@{
                        'type'    = "VSAN"
                        'vlanId'  = $instanceObject.$($az).$($rack).network.vsanVlanID
                        'mtu'     = $vsanMtu
                        'subnet'  = $instanceObject.$($az).$($rack).network.vsanNetwork
                        'mask'    = $instanceObject.$($az).$($rack).network.vsanNetmask
                        'gateway' = $instanceObject.$($az).$($rack).network.vsanGw
                        'ipPools'   = $vsanIpPoolObject
                    }

                    If (($instanceObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster") -and ($instanceObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network"))
                    {
                        $networkObject += [pscustomobject]@{
                            'type'    = "VSAN_EXTERNAL"
                            'vlanId'  = $instanceObject.$($az).$($rack).network.secondaryStorageVlanID
                            'mtu'     = $secondaryStorageMtu
                            'subnet'  = $instanceObject.$($az).$($rack).network.secondaryStorageNetwork
                            'mask'    = $instanceObject.$($az).$($rack).network.secondaryStorageNetmask
                            'gateway' = $instanceObject.$($az).$($rack).network.secondaryStorageGw
                            'ipPools'   = $secondaryStorageIpPoolObject
                        }
                    }
            
                    $networkPoolObject = @()
                    $networkPoolObject += [pscustomobject]@{
                        'name'   = $instanceObject.$($az).$($rack).network.vcfNetworkPoolName
                        'networks' = $networkObject
                    }
        
                    LogMessage -Type INFO -Message "Exporting Network Pool JSON to networkPoolSpec-$($instanceObject.$($az).$($rack).network.vcfNetworkPoolName).json"
                    $networkPoolObject | ConvertTo-Json -Depth 4 | Out-File -Encoding UTF8 -FilePath "networkPoolSpec-$($instanceObject.$($az).$($rack).network.vcfNetworkPoolName).json"                
                }
            }
        }
        LogMessage -Type NOTE -Message "Completed the Process of Generating the Workload Domain Network Pool JSON(s)"
    }
    Catch {
        catchWriter -object $_
    }
}

Function New-RackBasedHostCommissioning
{
    Param (
        [Parameter(Mandatory = $true)][Object]$instanceObject,
        [Parameter(Mandatory = $false)][string]$az
    )
    Remove-Variable commissionNestedHosts -errorAction silentlyContinue

    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to create a commissioning JSON for submission via API (A) or UI (U)? " -skipnewline
        $jsonMode = Read-Host    
    } Until ($jsonMode -in "A","U")
    
    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve network pool IDs from SDDC Manager? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "SDDC Manager FQDN: " -skipnewline
            $sddcMgrFqdn = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator: " -skipnewline
            $sddcMgrUser = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator password: " -skipnewline
            $adminPassword = Read-Host -AsSecureString
            $decodedPassword = New-DecodedPassword -securePassword $adminPassword
            New-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $decodedPassword *>$null
            If (!($accessToken))
            {
                LogMessage -type ERROR -message "Failed to connect to $sddcMgrFqdn. Please check details and try again"
            }
        } Until ($accessToken)
    }

    If (!($az))
    {
        If ($instanceObject.az2)
        { 
            $azs = @("az1","az2") 
        }
        else
        {
            $azs = @("az1")
        }
    }
    
    Foreach ($az in $azs)
    {
        $selectedRackArray = @(($instanceObject.$($az) | Get-Member -type NoteProperty).name)
        $commissionNestedHosts = @()
        If (!$exitFunction)
        {
            Foreach ($rack in $selectedRackArray)
            {
                $selectedHostArray = @($instanceObject.$($az).$($rack).hosts)
    
                If (!$exitFunction)
                {
                    If ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-ESA") 
                    {
                        $vSanTypeObject="VSAN_ESA" 
                    }
                    elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster")
                    {
                        $vSanTypeObject="VSAN_MAX"
                    }
                    else
                    {
                        $vSanTypeObject="VSAN"
                    }
        
                    If ($interactiveEnabled -eq "Y")
                    {
                        LogMessage -Type INFO -Message "Obtaining Network Pool ID from SDDC Manager for pool $($instanceObject.$($az).$($rack).network.vcfNetworkPoolName): Found"
                        $networkPool = (Get-VCFNetworkPoolDetails | Where-Object { $_.name -eq $instanceObject.$($az).$($rack).network.vcfNetworkPoolName }).id
                    }
                    else
                    {
                        $networkPool = '<--ENTER-NETWORK-POOL-ID-HERE-->'
                    }
    
                    Foreach ($selectedHost in $selectedHostArray)
                    {
                        $commissionNestedHosts += [pscustomobject]@{
                            "fqdn" = $selectedHost.fqdn
                            "username" = "root"
                            "storageType" = $vSanTypeObject
                            "password" = $instanceObject.hostCredentials.esxiPassword
                            'networkPoolName' = $instanceObject.$($az).$($rack).network.vcfNetworkPoolName
                            'networkPoolId'   = $networkPool
                        } 
                    }
                Remove-Variable selectedHostArray
                }
            }
    
            If (!$exitFunction)
            {
                
                If ($jsonMode -eq "A")
                {
                    #Create API JSON Spec
                    LogMessage -Type INFO -Message "Exporting API Commissioning JSON to commissionHostSpec-$($instanceObject.vsphereClusters[0].clustername)-$($az)-api.json"
                    ConvertTo-Json $commissionNestedHosts -Depth 10 | Out-File -FilePath "commissionHostSpec-$($instanceObject.vsphereClusters[0].clustername)-$($az)-api.json"
                }
                else
                {
                    #Create UI JSON Spec
                    $uiSpecObject = @()
                    $uiSpecObject += [pscustomobject]@{
                        'hosts' = $commissionNestedHosts
                    }                
                    $uiSpecObject[0].hosts = $uiSpecObject.hosts | ForEach-Object {            
                        $_ | Select-Object @{Name = 'fqdn'; Expression = {$_.fqdn}}, 'username', 'storageType', 'password', 'networkPoolName'
                    } | Select-Object -Skip 0
                    LogMessage -Type INFO -Message "Exporting UI Commissioning JSON to commissionHostSpec-$($instanceObject.vsphereClusters[0].clustername)-$($az)-ui.json"
                    $uiSpecObject | Convertto-json -depth 10 | Out-File -FilePath "commissionHostSpec-$($instanceObject.vsphereClusters[0].clustername)-$($az)-ui.json"    
                }
                LogMessage -Type NOTE -Message "Completed the Process of Generating the Commissioning JSON"
            }
        }
    }
}

#Cluster JSON Files
Function New-L2vSphereClusterJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$clusterObject
    )
    Do
    {
        If ($clusterObject.determinedClusterConfig -eq "Single-Rack Compute Only")
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Domain, Host, Image and Datastore IDs from SDDC Manager/vCenter? (Y/N): " -skipnewline
        }
        else
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Domain, Host and Image IDs from SDDC Manager? (Y/N): " -skipnewline
        }
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "SDDC Manager FQDN: " -skipnewline
            $sddcMgrFqdn = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator: " -skipnewline
            $sddcMgrUser = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator password: " -skipnewline
            $adminPassword = Read-Host -AsSecureString
            $decodedPassword = New-DecodedPassword -securePassword $adminPassword
            New-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $decodedPassword *>$null
            If (!($accessToken))
            {
                LogMessage -type ERROR -message "Failed to connect to $sddcMgrFqdn. Please check details and try again"
            }
        } Until ($accessToken)
        If ($clusterObject.determinedClusterConfig -eq "Single-Rack Compute Only")
        {
            Do
            {
                LogMessage -type INFO -message "vCenter FQDN: " -skipnewline
                $vCenterFqdn = Read-Host
                LogMessage -type INFO -message "vCenter Administrator: " -skipnewline
                $vCenterAdminUser = Read-Host
                LogMessage -type INFO -message "vCenter Administrator password: " -skipnewline
                $vCenterPassword = Read-Host -AsSecureString
                $decodedVcenterPassword = New-DecodedPassword -securePassword $vCenterPassword
                $vCenterConnection = Connect-VIServer -server $vCenterFQDN -user $vCenterAdminUser -password $decodedvCenterPassword -errorAction SilentlyContinue
                If (!($vCenterConnection))
                {
                    LogMessage -type ERROR -message "Failed to connect to successfully read information from $vCenterFqdn. Please check details and try again"
                }
            } Until ($vCenterConnection)
        }
    }
    
    $rack = "rack1"

    $vmnicObject = @()
    $vmnicObject += [pscustomobject]@{
        'id'      = $clusterObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
        'vdsName' = $clusterObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink1"
    }
    $vmnicObject += [pscustomobject]@{
        'id'      = $clusterObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
        'vdsName' = $clusterObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink2"
    }
    If ($clusterObject.vsphereClusters[0].vdsProfile -in "Storage Traffic Separation","NSX Traffic Separation")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
    }
    If ($clusterObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic and NSX Traffic Separation")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[2].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[2].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink2"
        }
    }     

    $hostArray = @()
    $hostCounter = 0
    #$selectedHosts = @(0..$([INT]$clusterObject.az1.$($rack).hosts.count -1))

    Foreach ($selectedHost in $clusterObject.az1.$($rack).hosts)
    {
        If ($interactiveEnabled -eq "Y")
        {
            $hostID = Get-VCFHostDetails -Status UNASSIGNED_USEABLE | Select-Object fqdn, id | Where-Object { $_.fqdn -eq $selectedHost.fqdn }
            If ($hostID)
            {
                LogMessage -Type INFO -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Found"
                $hostIdValue = $hostId.id
            }
            else
            {
                LogMessage -Type WARNING -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Not found. Not adding to JSON File"
                $hostIdValue = "None Found"
            }
        }
        else
        {
            $hostIdValue = "<--ENTER-SDDC-HOSTID-HERE-->"
        }
        
        $hostnetworkObject = @()
        $hostnetworkObject += [pscustomobject]@{
            'vmNics' = $vmnicObject
        }
        If ($hostIdValue -ne "None Found")
        {
            $newHost = [pscustomobject]@{
                'id'                = $hostIdValue
                'hostname'          = $selectedHost.fqdn
                'hostNetworkSpec'   = ($hostnetworkObject | Select-Object -Skip 0)
            }
            $hostArray += $newHost
        }
        $hostCounter++
    }


    If ($clusterObject.vsphereClusters[0].storageModel -eq "VSAN-ESA")
    {
        $ESAenabledtrueobject = @()
        $ESAenabledtrueobject  += [pscustomobject]@{
            'enabled' = "true"
        }                    
    }
    elseIf ($clusterObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster")
    {
        $vsanMaxConfigObject = New-Object -type psobject
        If ($clusterObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network")
        {
            $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanExternalNetwork' -NotePropertyValue $true
        }
        else
        {
            $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanExternalNetwork' -NotePropertyValue $false
        }
        $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanMax' -NotePropertyValue $true
        $ESAenabledtrueobject = @()
        $ESAenabledtrueobject  += [pscustomobject]@{
            'enabled' = "true"
            'vsanMaxConfig' = $vsanMaxConfigObject
        }  
    }
    elseIf ($clusterObject.vsphereClusters[0].storageModel -eq "VSAN-OSA")
    {
        $ESAenabledtrueobject = @()
        $ESAenabledtrueobject  += [pscustomobject]@{
            'enabled' = "false"
        } 
    }

    If ($clusterObject.determinedClusterConfig -eq "Single-Rack Compute Only")
    {
        If ($interactiveEnabled -eq "Y")
        {
            $datastoreUuid = (Get-Datastore -name $clusterObject.vsphereClusters[0].vsanDatastore).ExtensionData.info.ContainerId
        }
        else
        {
            $datastoreUuid = '<-- ENTER UUID OF REMOTE DATASTORE HERE -->'
        }
        $vsanRemoteDatastoreObject = @()
        $vsanRemoteDatastoreObject += [pscustomobject]@{
            'datastoreUuid'      = $datastoreUuid
        }

        $vsanRemoteDatastoreSpecArray = @()
        $vsanRemoteDatastoreSpecArray += $vsanRemoteDatastoreObject

        $vsanRemoteDatastoreClusterSpecObject = New-Object -type psobject
        $vsanRemoteDatastoreClusterSpecObject | Add-Member -NotePropertyName 'vsanRemoteDatastoreSpec' -NotePropertyValue $vsanRemoteDatastoreSpecArray

        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanRemoteDatastoreClusterSpec' = $vsanRemoteDatastoreClusterSpecObject
        }
    }
    else
    {
        $vsanDatastoreObject = @()
        If ($clusterObject.vsphereClusters[0].storageModel -in "VSAN-ESA","vSAN Storage Cluster")
        {
            $vsanDatastoreObject += [pscustomobject]@{
            'datastoreName'      = $clusterObject.vsphereClusters[0].vsanDatastore
            'esaConfig' =  ($ESAenabledtrueobject | Select-Object -Skip 0)
            }
        }
        elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-OSA") 
        {
            $vsanDatastoreObject += [pscustomobject]@{
            'failuresToTolerate' = "1"
            'datastoreName'      = $clusterObject.vsphereClusters[0].vsanDatastore
            }
        }
    
        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanDatastoreSpec' = ($vsanDatastoreObject | Select-Object -Skip 0)
        }
    }

    $activeUplinksArray = @()
    $activeUplinksArray += "uplink1"
    $activeUplinksArray += "uplink2"

    $portgroupObject = @()
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.mgmt
        'transportType' = "MANAGEMENT"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vmotion
        'transportType' = "VMOTION"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vsan
        'transportType' = "VSAN"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    If (($clusterObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster") -and ($clusterObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network") -and ($clusterObject.vsphereClusters[0].vdsProfile -ne "Default"))
    {
        $portgroupObject += [pscustomobject]@{
            'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vsanClient
            'transportType' = "VSAN_EXTERNAL"
            'standByUplinks' = @()
            'teamingPolicy' = "loadbalance_loadbased"
            'activeUplinks' = $activeUplinksArray
        }
    }

    $vdsMtu = $clusterObject.vsphereClusters[0].vds[0].mtu -as [string]
    
    $transportZoneArray = @()
    $transportZoneArray += [pscustomobject]@{
        'name'          = "nsx-vlan-transportzone"
        'transportType' = "VLAN"
    }
    $transportZoneArray += [pscustomobject]@{
        'name'          = "overlay-tz-$($clusterObject.tzName)"
        'transportType' = "OVERLAY"
    }
    
    $nsxtSwitchConfigObject = New-Object -type psobject
    If ($clusterObject.vsphereClusters[0].nsxOperationDefaultMode -eq "Selected")
    {
        $operationMode = "ENS_INTERRUPT"
    }
    else
    {
        If ($clusterObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Standard")
        {
            $operationMode = "STANDARD"
        }
        elseif ($clusterObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Enhanced Datapath Standard")
        {
            $operationMode = "ENS_INTERRUPT"
        }
        else 
        {
            < $operationMode = "ENS"
        }
    }
    $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode
    $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
        
    $vdsObject = @()
    If ($clusterObject.vsphereClusters[0].vdsProfile -eq "Default")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }
    elseif ($clusterObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic Separation")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
        }
    }
    elseif ($clusterObject.vsphereClusters[0].vdsProfile -eq "NSX Traffic Separation")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN","VSAN_EXTERNAL"}
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }
    else
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'mtu' = $vdsMtu
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }

    #uplink profiles
    $teamingsArray = @()
    $teamingsArray += [pscustomobject]@{
        'name' = "DEFAULT"
        'policy' = "LOADBALANCE_SRCID"
        'standByUplinks' = @()
        'activeUplinks' = $activeUplinksArray
    }

    $newNetworkProfileName = $clusterObject.az1.$($rack).network.networkProfileName
    
    If ($clusterObject.az1.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
    {
        $newHostPoolName = $clusterObject.az1.$($rack).network.hostIpAddressPoolName
    }
    else
    {
        $newHostPoolName = $null
    }
    $newUplinkProfileName = $clusterObject.az1.$($rack).network.uplinkProfileName
    $newHostPoolStartIp = $clusterObject.az1.$($rack).network.hostOverlayPoolStartIP
    $newHostPoolEndIp = $clusterObject.az1.$($rack).network.hostOverlayPoolEndIP

    $uplinkProfilesArray = @()
    
    $uplinkProfile = New-Object -type PSObject
    $uplinkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newUplinkProfileName
    $uplinkProfile | Add-Member -NotePropertyName 'transportVlan' -NotePropertyValue $([INT]($clusterObject.az1.$($rack).network.hostOverlayVlanID))
    $uplinkProfile | Add-Member -NotePropertyName 'teamings' -NotePropertyValue $teamingsArray
    $uplinkProfilesArray += $uplinkProfile

    #ipAddressPoolsSpec
    $ipAddressPoolsSpecArray = @()    
    $ipAddressPoolRangesArray = @()

    If ($clusterObject.az1.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
    {
        If ($clusterObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
        {
            $ipAddressPoolRangesArray += [pscustomobject]@{
                'start' = $newHostPoolStartIp
                'end' = $newHostPoolEndIp
            }
        
            $subnetsArray = @()
            $subnetsArray += [pscustomobject]@{
                'cidr' = $clusterObject.az1.$($rack).network.hostOverlayCidr
                'gateway' = $clusterObject.az1.$($rack).network.hostOverlayGw
                'ipAddressPoolRanges' = $ipAddressPoolRangesArray
            }
        }

        $ipAddressSpec = New-Object -type PSObject
        $ipAddressSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $newHostPoolName
        If ($clusterObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
        {
            $ipAddressSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
        }

        $ipAddressPoolsSpecArray += $ipAddressSpec
    }
    else
    {
        $ipAddressPoolsSpecArray = $null
    }
    
    $nsxTClusterObject = @()
    $nsxTClusterObject += [pscustomobject]@{
        'ipAddressPoolsSpec' = $ipAddressPoolsSpecArray
        'uplinkProfiles' = $uplinkProfilesArray
    }   

    $nsxClusterObject = @()
    $nsxClusterObject += [pscustomobject]@{
        'nsxTClusterSpec' = ($nsxTClusterObject | Select-Object -Skip 0)
    }

    $vdsUplinkToNsxUplinkArray = @()
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink1"
        'vdsUplinkName' = "uplink1"
    }
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink2"
        'vdsUplinkName' = "uplink2"
    }

    If ($clusterObject.vsphereClusters[0].vdsProfile -in "NSX Traffic Separation")
    {
        $vdsName = $clusterObject.vsphereClusters[0].vds[1].vdsName
    }
    elseIf ($clusterObject.vsphereClusters[0].vdsProfile -in "Storage Traffic and NSX Traffic Separation")
    {
        $vdsName = $clusterObject.vsphereClusters[0].vds[2].vdsName
    }
    else
    {
        $vdsName = $clusterObject.vsphereClusters[0].vds[0].vdsName
    }

    $nsxtHostSwitchConfigs = @()
    $nsxtHostSwitchConfigs += [pscustomobject]@{
        'ipAddressPoolName' = $newHostPoolName
        'uplinkProfileName' = $newUplinkProfileName
        'vdsName' = $vdsName
        'vdsUplinkToNsxUplink' = $vdsUplinkToNsxUplinkArray
    }

    $networkProfilesArray = @()
    $rackNetworkProfile = New-Object -type psobject
    $rackNetworkProfile | Add-Member -NotePropertyName 'isDefault' -NotePropertyValue $(If ($networkProfilesArray.count -eq 0) {$true} else {$false})
    $rackNetworkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newNetworkProfileName
    $rackNetworkProfile | Add-Member -NotePropertyName 'nsxtHostSwitchConfigs' -NotePropertyValue $nsxtHostSwitchConfigs
    $networkProfilesArray += $rackNetworkProfile  

    $networkObject = @()
    $networkObject += [pscustomobject]@{
        'vdsSpecs'       = $vdsObject
        'nsxClusterSpec' = ($nsxClusterObject | Select-Object -Skip 0)
        'networkProfiles' = $networkProfilesArray
    }

    $clusterSpecObject = @()
    $clusterSpecObject += [pscustomobject]@{
        'name'        = $clusterObject.vsphereClusters[0].clusterName
        'hostSpecs'     = $hostArray
        'datastoreSpec' = ($vsanObject | Select-Object -Skip 0)
        'networkSpec'   = ($networkObject | Select-Object -Skip 0)
    }
    
    If ($clusterObject.vsphereClusters[0].vlcmModel -eq "Images") 
    {
        If ($interactiveEnabled -eq "Y")
        {
            LogMessage -Type INFO -Message "Obtaining Cluster Image Personality ID from SDDC Manager"
            $clusterImageId = (Get-VCFPersonalityDetails | Where-Object { $_.personalityName -eq $clusterObject.vsphereClusters[0].imageName }).personalityId
        }
        else
        {
            $clusterImageId = "<--ENTER-SDDC-PERSONALITY-NAME-HERE-->"
        }
        $clusterSpecObject[0] | Add-Member -NotePropertyName 'clusterImageId' -NotePropertyValue $clusterImageId
    }

    $computeSpecObject = @()
    $computeSpecObject += [pscustomobject]@{
        'clusterSpecs' = $clusterSpecObject
    }

    If ($interactiveEnabled -eq "Y")
    {
        $domainID = (Get-VCFWorkloadDomainDetails -name $clusterObject.domainName).id
        If ($domainID)
        {
            LogMessage -Type INFO -Message "Obtaining Domain ID from SDDC Manager for domain $($clusterObject.domainName): Found"
            $domainIDValue = $domainID
        }
        else
        {
            LogMessage -Type ERROR -Message "Obtaining Domain ID from SDDC Manager for domain $($clusterObject.domainName): Not found. Adding placeholder to JSON File"
            $domainIDValue = "<--ENTER-SDDC-DOMAINID-HERE-->"
        }
    }
    else
    {
        $domainIDValue = "<--ENTER-SDDC-DOMAINID-HERE-->"
    }

    $clusterJsonObject = @()
    $clusterJsonObject += [pscustomobject]@{
        'domainId' = $domainIDValue
        'computeSpec'  = ($computeSpecObject | Select-Object -Skip 0)
    }
    $clusterJsonObject | Add-Member -notepropertyname 'deployWithoutLicenseKeys' -notepropertyvalue "true"
    LogMessage -Type INFO -Message "Exporting the Cluster Creation JSON to clusterSpec-$($clusterObject.vsphereClusters[0].clusterName).json"
    $clusterJsonObject | ConvertTo-Json -Depth 12 | Out-File -Encoding UTF8 -FilePath "clusterSpec-$($clusterObject.vsphereClusters[0].clusterName).json"
    LogMessage -Type NOTE -Message "Completed the Process of Generating the Cluster Creation JSON"
}

Function New-L3vSphereClusterJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$clusterObject
    )
    Do
    {
        If ($clusterObject.determinedClusterConfig -eq "Multi-Rack Compute Only")
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Domain, Host, Image and Datastore IDs from SDDC Manager/vCenter? (Y/N): " -skipnewline
        }
        else
        {
            LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Domain, Host and Image IDs from SDDC Manager? (Y/N): " -skipnewline
        }
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "SDDC Manager FQDN: " -skipnewline
            $sddcMgrFqdn = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator: " -skipnewline
            $sddcMgrUser = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator password: " -skipnewline
            $adminPassword = Read-Host -AsSecureString
            $decodedPassword = New-DecodedPassword -securePassword $adminPassword
            New-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $decodedPassword *>$null
            If (!($accessToken))
            {
                LogMessage -type ERROR -message "Failed to connect to $sddcMgrFqdn. Please check details and try again"
            }
        } Until ($accessToken)
        If ($clusterObject.determinedClusterConfig -eq "Multi-Rack Compute Only")
        {
            Do
            {
                LogMessage -type INFO -message "vCenter FQDN: " -skipnewline
                $vCenterFqdn = Read-Host
                LogMessage -type INFO -message "vCenter Administrator: " -skipnewline
                $vCenterAdminUser = Read-Host
                LogMessage -type INFO -message "vCenter Administrator password: " -skipnewline
                $vCenterPassword = Read-Host -AsSecureString
                $decodedVcenterPassword = New-DecodedPassword -securePassword $vCenterPassword
                $vCenterConnection = Connect-VIServer -server $vCenterFQDN -user $vCenterAdminUser -password $decodedvCenterPassword -errorAction SilentlyContinue
                If (!($vCenterConnection))
                {
                    LogMessage -type ERROR -message "Failed to connect to successfully read information from $vCenterFqdn. Please check details and try again"
                }
            } Until ($vCenterConnection)
        }
    }
    
    $vmnicObject = @()
    $vmnicObject += [pscustomobject]@{
        'id'      = $clusterObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
        'vdsName' = $clusterObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink1"
    }
    $vmnicObject += [pscustomobject]@{
        'id'      = $clusterObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
        'vdsName' = $clusterObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink2"
    }
    If ($clusterObject.vsphereClusters[0].vdsProfile -in "Storage Traffic Separation","NSX Traffic Separation")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
    }
    If ($clusterObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic and NSX Traffic Separation")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[2].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[2].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink2"
        }
    }   

    $hostArray = @()
    $hostCounter = 0
    
    $rackArray = @(($clusterObject.az1 | Get-Member -type NoteProperty).name)
    Foreach ($rack in $rackArray)
    {
        
        $rackAbbreviation = "r0"+(($rack).substring(4,1))
        $newNetworkProfileName = $clusterObject.az1.$($rack).network.networkProfileName
        Foreach ($selectedHost in $clusterObject.az1.$($rack).hosts)
        {
            If ($interactiveEnabled -eq "Y")
            {
                $hostID = Get-VCFHostDetails -Status UNASSIGNED_USEABLE | Select-Object fqdn, id | Where-Object { $_.fqdn -eq $selectedHost.fqdn }
                If ($hostID)
                {
                    LogMessage -Type INFO -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Found"
                    $hostIdValue = $hostId.id
                }
                else
                {
                    LogMessage -Type WARNING -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Not found. Not adding to JSON File"
                    $hostIdValue = "None Found"
                }
            }
            else
            {
                $hostIdValue = "<--ENTER-SDDC-HOSTID-HERE-->"
            }
            
            $hostnetworkObject = @()
            $hostnetworkObject += [pscustomobject]@{
                'networkProfileName' = $newNetworkProfileName
                'vmNics' = $vmnicObject
            }
            
            $newHost = [pscustomobject]@{
                'id'                = $hostIdValue
                'hostname'          = $selectedHost.fqdn
                'hostNetworkSpec'   = ($hostnetworkObject | Select-Object -Skip 0)
            }
            $hostArray += $newHost
            $hostCounter++
        }
    
    }

    If ($clusterObject.vsphereClusters[0].storageModel -eq "VSAN-ESA")
    {
        $ESAenabledtrueobject = @()
        $ESAenabledtrueobject  += [pscustomobject]@{
            'enabled' = "true"
        }                    
    }
    elseIf ($clusterObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster")
    {
        $vsanMaxConfigObject = New-Object -type psobject
        If ($clusterObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network")
        {
            $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanExternalNetwork' -NotePropertyValue $true
        }
        else
        {
            $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanExternalNetwork' -NotePropertyValue $false
        }
        $vsanMaxConfigObject | Add-Member -NotePropertyName 'enableVsanMax' -NotePropertyValue $true
        $ESAenabledtrueobject = @()
        $ESAenabledtrueobject  += [pscustomobject]@{
            'enabled' = "true"
            'vsanMaxConfig' = $vsanMaxConfigObject
        }  
    }
    elseIf ($clusterObject.vsphereClusters[0].storageModel -eq "VSAN-OSA")
    {
        $ESAenabledtrueobject = @()
        $ESAenabledtrueobject  += [pscustomobject]@{
            'enabled' = "false"
        } 
    }

    If ($clusterObject.determinedClusterConfig -eq "Multi-Rack Compute Only")
    {
        If ($interactiveEnabled -eq "Y")
        {
            $datastoreUuid = (Get-Datastore -name $clusterObject.vsphereClusters[0].vsanDatastore).ExtensionData.info.ContainerId
        }
        else
        {
            $datastoreUuid = '<-- ENTER UUID OF REMOTE DATASTORE HERE -->'
        }
        $vsanRemoteDatastoreObject = @()
        $vsanRemoteDatastoreObject += [pscustomobject]@{
            'datastoreUuid'      = $datastoreUuid
        }

        $vsanRemoteDatastoreSpecArray = @()
        $vsanRemoteDatastoreSpecArray += $vsanRemoteDatastoreObject

        $vsanRemoteDatastoreClusterSpecObject = New-Object -type psobject
        $vsanRemoteDatastoreClusterSpecObject | Add-Member -NotePropertyName 'vsanRemoteDatastoreSpec' -NotePropertyValue $vsanRemoteDatastoreSpecArray

        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanRemoteDatastoreClusterSpec' = $vsanRemoteDatastoreClusterSpecObject
        }
    }
    else
    {
        $vsanDatastoreObject = @()
        If ($clusterObject.vsphereClusters[0].storageModel -in "VSAN-ESA","vSAN Storage Cluster")
        {
            $vsanDatastoreObject += [pscustomobject]@{
            'datastoreName'      = $clusterObject.vsphereClusters[0].vsanDatastore
            'esaConfig' =  ($ESAenabledtrueobject | Select-Object -Skip 0)
            }
        }
        elseIf ($instanceObject.vsphereClusters[0].storageModel -eq "VSAN-OSA") 
        {
            $vsanDatastoreObject += [pscustomobject]@{
            'failuresToTolerate' = "1"
            'datastoreName'      = $clusterObject.vsphereClusters[0].vsanDatastore
            }
        }
    
        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanDatastoreSpec' = ($vsanDatastoreObject | Select-Object -Skip 0)
        }
    }

    $activeUplinksArray = @()
    $activeUplinksArray += "uplink1"
    $activeUplinksArray += "uplink2"

    $portgroupObject = @()
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.mgmt
        'transportType' = "MANAGEMENT"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vmotion
        'transportType' = "VMOTION"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vsan
        'transportType' = "VSAN"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    If (($clusterObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster") -and ($clusterObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network") -and ($clusterObject.vsphereClusters[0].vdsProfile -ne "Default"))
    {
        $portgroupObject += [pscustomobject]@{
            'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vsanClient
            'transportType' = "VSAN_EXTERNAL"
            'standByUplinks' = @()
            'teamingPolicy' = "loadbalance_loadbased"
            'activeUplinks' = $activeUplinksArray
        }
    }

    $vdsMtu = $clusterObject.vsphereClusters[0].vds[0].mtu -as [string]

    $transportZoneArray = @()
    $transportZoneArray += [pscustomobject]@{
        'name'          = "nsx-vlan-transportzone"
        'transportType' = "VLAN"
    }
    $transportZoneArray += [pscustomobject]@{
        'name'          = "overlay-tz-$($clusterObject.tzName)"
        'transportType' = "OVERLAY"
    }
    
    $nsxtSwitchConfigObject = New-Object -type psobject
    If ($clusterObject.vsphereClusters[0].nsxOperationDefaultMode -eq "Selected")
    {
        $operationMode = "ENS_INTERRUPT"
    }
    else
    {
        If ($clusterObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Standard")
        {
            $operationMode = "STANDARD"
        }
        elseif ($clusterObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Enhanced Datapath Standard")
        {
            $operationMode = "ENS_INTERRUPT"
        }
        else 
        {
            < $operationMode = "ENS"
        }
    }
    $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode
    $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
        
    $vdsObject = @()
    If ($clusterObject.vsphereClusters[0].vdsProfile -eq "Default")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }
    elseif ($clusterObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic Separation")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
        }
    }
    elseif ($clusterObject.vsphereClusters[0].vdsProfile -eq "NSX Traffic Separation")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN","VSAN_EXTERNAL"}
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }
    else
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'mtu' = $vdsMtu
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }

    #uplink profiles
    $teamingsArray = @()
    $teamingsArray += [pscustomobject]@{
        'name' = "DEFAULT"
        'policy' = "LOADBALANCE_SRCID"
        'standByUplinks' = @()
        'activeUplinks' = $activeUplinksArray
    }

    $vdsUplinkToNsxUplinkArray = @()
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink1"
        'vdsUplinkName' = "uplink1"
    }
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink2"
        'vdsUplinkName' = "uplink2"
    }

    $networkProfilesArray = @()
    $ipAddressPoolsSpecArray = @()  
    $uplinkProfilesArray = @()
    Foreach ($rack in $rackArray)
    {
        $rackAbbreviation = "r0"+(($rack).substring(4,1))
        $newNetworkProfileName = $clusterObject.az1.$($rack).network.networkProfileName
    

        If ($clusterObject.az1.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
        {
            $newHostPoolName = $clusterObject.az1.$($rack).network.hostIpAddressPoolName
        }
        else
        {
            $newHostPoolName = $null
        }
        $newUplinkProfileName = $clusterObject.az1.$($rack).network.uplinkProfileName
        $newHostPoolStartIp = $clusterObject.az1.$($rack).network.hostOverlayPoolStartIP
        $newHostPoolEndIp = $clusterObject.az1.$($rack).network.hostOverlayPoolEndIP

        If ($clusterObject.vsphereClusters[0].vdsProfile -in "NSX Traffic Separation")
        {
            $vdsName = $clusterObject.vsphereClusters[0].vds[1].vdsName
        }
        elseIf ($clusterObject.vsphereClusters[0].vdsProfile -in "Storage Traffic and NSX Traffic Separation")
        {
            $vdsName = $clusterObject.vsphereClusters[0].vds[2].vdsName
        }
        else
        {
            $vdsName = $clusterObject.vsphereClusters[0].vds[0].vdsName
        }

        $nsxtHostSwitchConfigs = @()
        $nsxtHostSwitchConfigs += [pscustomobject]@{
            'ipAddressPoolName' = $newHostPoolName
            'uplinkProfileName' = $newUplinkProfileName
            'vdsName' = $vdsName
            'vdsUplinkToNsxUplink' = $vdsUplinkToNsxUplinkArray
        }
                        
        $rackNetworkProfile = New-Object -type psobject
        $rackNetworkProfile | Add-Member -NotePropertyName 'isDefault' -NotePropertyValue $(If ($networkProfilesArray.count -eq 0) {$true} else {$false})
        $rackNetworkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newNetworkProfileName
        $rackNetworkProfile | Add-Member -NotePropertyName 'nsxtHostSwitchConfigs' -NotePropertyValue $nsxtHostSwitchConfigs
        $networkProfilesArray += $rackNetworkProfile

        If ($clusterObject.az1.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
        {
            If ($clusterObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
            {
                $ipAddressPoolRangesArray = @()
                $ipAddressPoolRangesArray += [pscustomobject]@{
                    'start' = $newHostPoolStartIp
                    'end' = $newHostPoolEndIp
                }
                
                $subnetsArray = @()
                $subnetsArray += [pscustomobject]@{
                    'cidr' = $clusterObject.az1.$($rack).network.hostOverlayCidr
                    'gateway' = $clusterObject.az1.$($rack).network.hostOverlayGw
                    'ipAddressPoolRanges' = $ipAddressPoolRangesArray
                }
            }
            
            $ipAddressSpec = New-Object -type PSObject
            $ipAddressSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $newHostPoolName
            If ($clusterObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
            {
                $ipAddressSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
            }
        
            $ipAddressPoolsSpecArray += $ipAddressSpec
        }
    
        $teamingsArray = @()
        $teamingsArray += [pscustomobject]@{
            'name' = "DEFAULT"
            'policy' = "LOADBALANCE_SRCID"
            'standByUplinks' = @()
            'activeUplinks' = $activeUplinksArray
        }
    
        $uplinkProfile = New-Object -type PSObject
        $uplinkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newUplinkProfileName
        $uplinkProfile | Add-Member -NotePropertyName 'transportVlan' -NotePropertyValue $([INT]($clusterObject.az1.$($rack).network.hostOverlayVlanID))
        $uplinkProfile | Add-Member -NotePropertyName 'teamings' -NotePropertyValue $teamingsArray
        $uplinkProfilesArray += $uplinkProfile
    }

    $nsxTClusterObject = @()
    $nsxTClusterObject += [pscustomobject]@{
        'ipAddressPoolsSpec' = $ipAddressPoolsSpecArray
        'uplinkProfiles' = $uplinkProfilesArray
    }

    $nsxClusterObject = @()
    $nsxClusterObject += [pscustomobject]@{
        'nsxTClusterSpec' = ($nsxTClusterObject | Select-Object -Skip 0)
    }

    $networkObject = @()
    $networkObject += [pscustomobject]@{
        'vdsSpecs'       = $vdsObject
        'networkProfiles' = $networkProfilesArray
        'nsxClusterSpec' = ($nsxClusterObject | Select-Object -Skip 0)
    }

    $clusterSpecObject = @()
    $clusterSpecObject += [pscustomobject]@{
        'name'        = $clusterObject.vsphereClusters[0].clusterName
        'hostSpecs'     = $hostArray
        'datastoreSpec' = ($vsanObject | Select-Object -Skip 0)
        'networkSpec'   = ($networkObject | Select-Object -Skip 0)
    }

    If ($clusterObject.vsphereClusters[0].vlcmModel -eq "Images") 
    {
        If ($interactiveEnabled -eq "Y")
        {
            LogMessage -Type INFO -Message "Obtaining Cluster Image Personality ID from SDDC Manager"
            $clusterImageId = (Get-VCFPersonalityDetails | Where-Object { $_.personalityName -eq $clusterObject.vsphereClusters[0].imageName }).personalityId
        }
        else
        {
            $clusterImageId = "<--ENTER-SDDC-PERSONALITY-NAME-HERE-->"
        }
        $clusterSpecObject[0] | Add-Member -NotePropertyName 'clusterImageId' -NotePropertyValue $clusterImageId
    }

    $computeSpecObject = @()
    $computeSpecObject += [pscustomobject]@{
        'clusterSpecs' = $clusterSpecObject
    }

    If ($interactiveEnabled -eq "Y")
    {
        $domainID = (Get-VCFWorkloadDomainDetails -name $clusterObject.domainName).id
        If ($domainID)
        {
            LogMessage -Type INFO -Message "Obtaining Domain ID from SDDC Manager for domain $($clusterObject.domainName): Found"
            $domainIDValue = $domainID
        }
        else
        {
            LogMessage -Type ERROR -Message "Obtaining Domain ID from SDDC Manager for domain $($clusterObject.domainName): Not found. Adding placeholder to JSON File"
            $domainIDValue = "<--ENTER-SDDC-DOMAINID-HERE-->"
        }
    }
    else
    {
        $domainIDValue = "<--ENTER-SDDC-DOMAINID-HERE-->"
    }

    $clusterJsonObject = @()
    $clusterJsonObject += [pscustomobject]@{
        'domainId' = $domainIDValue
        'computeSpec'  = ($computeSpecObject | Select-Object -Skip 0)
    }
    $clusterJsonObject | Add-Member -notepropertyname 'deployWithoutLicenseKeys' -notepropertyvalue "true"
    LogMessage -Type INFO -Message "Exporting the Cluster Creation JSON to clusterSpec-$($clusterObject.vsphereClusters[0].clusterName).json"
    $clusterJsonObject | ConvertTo-Json -Depth 12 | Out-File -Encoding UTF8 -FilePath "clusterSpec-$($clusterObject.vsphereClusters[0].clusterName).json"
    LogMessage -Type NOTE -Message "Completed the Process of Generating the Cluster Creation JSON"
}

Function New-StretchedClusterJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$instanceObject
    )

    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Host IDs from SDDC Manager? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "SDDC Manager FQDN: " -skipnewline
            $sddcMgrFqdn = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator: " -skipnewline
            $sddcMgrUser = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator password: " -skipnewline
            $adminPassword = Read-Host -AsSecureString
            $decodedPassword = New-DecodedPassword -securePassword $adminPassword
            New-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $decodedPassword *>$null
            If (!($accessToken))
            {
                LogMessage -type ERROR -message "Failed to connect to $sddcMgrFqdn. Please check details and try again"
            }
        } Until ($accessToken)
    }

    $vmnicObject = @()
    $vmnicObject += [pscustomobject]@{
        'id'      = $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
        'vdsName' = $instanceObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink1"
    }
    $vmnicObject += [pscustomobject]@{
        'id'      = $instanceObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
        'vdsName' = $instanceObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink2"
    }
    If ($instanceObject.vsphereClusters[0].vdsProfile -in "Storage Traffic Separation","NSX Traffic Separation","Profile-2","Profile-3")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
    }
    If ($instanceObject.vsphereClusters[0].vdsProfile -in "Storage Traffic and NSX Traffic Separation","Profile-4")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[2].pnics.split(",")[0]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $instanceObject.vsphereClusters[0].vds[2].pnics.split(",")[1]
            'vdsName' = $instanceObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink2"
        }
    } 

    $hostNetworkSpecObject = New-Object -TypeName psobject
    If ($instanceObject.az2.rack1.network.hostOverlayAddressing -in "IP Pool", "Static IP Pool")
    {
        $hostNetworkSpecObject | Add-Member -notepropertyname 'networkProfileName' -notepropertyvalue $instanceObject.az2.rack1.network.networkProfileName
    }
    $hostNetworkSpecObject | Add-Member -notepropertyname 'vmNics' -notepropertyvalue @($vmnicObject)

    $hostSpecsObject = @()
    Foreach ($az2Host in $instanceObject.az2.rack1.hosts)
    {
        If ($interactiveEnabled -eq "Y")
        {
            $hostID = Get-VCFHostDetails -Status UNASSIGNED_USEABLE | Select-Object fqdn, id | Where-Object { $_.fqdn -eq $az2Host.fqdn }
            If ($hostID)
            {
                LogMessage -Type INFO -Message "Obtaining Host ID from SDDC Manager for host $($az2Host.fqdn): Found"
                $hostIdValue = $hostId.id
            }
            else
            {
                LogMessage -Type WARNING -Message "Obtaining Host ID from SDDC Manager for host $($az2Host.fqdn): Not found. Not adding to JSON File"
                $hostIdValue = "None Found"
            }
        }
        else
        {
            $hostIdValue = "<--ENTER-SDDC-HOSTID-HERE-->"
        }
        
        $hostSpec = [pscustomobject]@{
            'id'    = $hostIdValue
            'hostname' = $az2Host.fqdn
            'hostNetworkSpec' = $hostNetworkSpecObject
        }
        If ($instanceObject.release -eq "vcf5")
        {
            $hostSpec | Add-Member -NotePropertyName 'licenseKey' -NotePropertyValue $commonObject.licenses.$($instanceObject.release).esxi
        }
        $hostSpecsObject += $hostSpec
    }

    If ($instanceObject.az2.rack1.network.hostOverlayAddressing -in "IP Pool","Static IP Pool")
    {
        $newHostPoolName = $instanceObject.az2.rack1.network.hostIpAddressPoolName
    }
    else
    {
        $newHostPoolName = $null
    }
    $newUplinkProfileName = $instanceObject.az2.rack1.network.uplinkProfileName
    $newNetworkProfileName = $instanceObject.az2.rack1.network.networkProfileName
    $newHostPoolStartIp = $instanceObject.az2.rack1.network.hostOverlayPoolStartIP
    $newHostPoolEndIp = $instanceObject.az2.rack1.network.hostOverlayPoolEndIP

    $vdsUplinkToNsxUplinkArray = @()
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink1"
        'vdsUplinkName' = "uplink1"
    }
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink2"
        'vdsUplinkName' = "uplink2"
    }

    If ($instanceObject.vsphereClusters[0].vdsProfile -in "NSX Traffic Separation","Profile-3")
    {
        $vdsName = $instanceObject.vsphereClusters[0].vds[1].vdsName
    }
    elseIf ($instanceObject.vsphereClusters[0].vdsProfile -in "Storage Traffic and NSX Traffic Separation","Profile-4")
    {
        $vdsName = $instanceObject.vsphereClusters[0].vds[2].vdsName
    }
    else
    {
        $vdsName = $instanceObject.vsphereClusters[0].vds[0].vdsName
    }

    $nsxtHostSwitchConfigs = @()
    $nsxtHostSwitchConfigs += [pscustomobject]@{
        'ipAddressPoolName' = $newHostPoolName
        'uplinkProfileName' = $newUplinkProfileName
        'vdsName' = $vdsName
        'vdsUplinkToNsxUplink' = $vdsUplinkToNsxUplinkArray
    }
                    
    $rackNetworkProfile = New-Object -type psobject
    $rackNetworkProfile | Add-Member -NotePropertyName 'isDefault' -NotePropertyValue $(If ($networkProfilesArray.count -eq 0) {$true} else {$false})
    $rackNetworkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newNetworkProfileName
    $rackNetworkProfile | Add-Member -NotePropertyName 'nsxtHostSwitchConfigs' -NotePropertyValue $nsxtHostSwitchConfigs
    $networkProfilesArray += $rackNetworkProfile

    $ipAddressPoolsSpecArray = @()  
    $ipAddressSpec = New-Object -type PSObject
    
    If ($instanceObject.az2.rack1.network.hostOverlayAddressing -in "IP Pool", "Static IP Pool")
    {
        $ipAddressSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $newHostPoolName
        If ($instanceObject.az2.rack1.network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
        {
            $ipAddressPoolRangesArray = @()
            $ipAddressPoolRangesArray += [pscustomobject]@{
                'start' = $newHostPoolStartIp
                'end' = $newHostPoolEndIp
            }
            
            $subnetsArray = @()
            $subnetsArray += [pscustomobject]@{
                'cidr' = $instanceObject.az2.rack1.network.hostOverlayCidr
                'gateway' = $instanceObject.az2.rack1.network.hostOverlayGw
                'ipAddressPoolRanges' = $ipAddressPoolRangesArray
            }
            $ipAddressSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
        }
        $ipAddressPoolsSpecArray += $ipAddressSpec

        $activeUplinksArray = @()
        $activeUplinksArray += "uplink1"
        $activeUplinksArray += "uplink2"
    
        $teamingsArray = @()
            $teamingsArray += [pscustomobject]@{
                'name' = "DEFAULT"
                'policy' = "LOADBALANCE_SRCID"
                'standByUplinks' = @()
                'activeUplinks' = $activeUplinksArray
            }
        
        $uplinkProfilesArray = @()
        $uplinkProfile = New-Object -type PSObject
        $uplinkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newUplinkProfileName
        $uplinkProfile | Add-Member -NotePropertyName 'transportVlan' -NotePropertyValue $([INT]($instanceObject.az2.rack1.network.hostOverlayVlanID))
        $uplinkProfile | Add-Member -NotePropertyName 'teamings' -NotePropertyValue $teamingsArray
        $uplinkProfilesArray += $uplinkProfile
    
        $nsxClusterObject = @()
        $nsxClusterObject += [pscustomobject]@{
            'ipAddressPoolsSpec' =  $ipAddressPoolsSpecArray
            'uplinkProfiles' = $uplinkProfilesArray
        }
    
        $networkObject = New-Object -TypeName psobject
        $networkObject | Add-Member -notepropertyname 'networkProfiles' -notepropertyvalue @($networkProfilesArray)
        $networkObject | Add-Member -notepropertyname 'nsxClusterSpec' -notepropertyvalue ($nsxClusterObject | Select-Object -Skip 0)
    
        $networkObject = @()
        $networkObject += [pscustomobject]@{
            'networkProfiles' = @($networkProfilesArray)
            'nsxClusterSpec' = ($nsxClusterObject | Select-Object -Skip 0)
        }
    }

    $witnessSpecObject = New-Object -TypeName psobject
    $witnessSpecObject | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $instanceObject.stretchCluster.witnessFqdn
    $witnessSpecObject | Add-Member -notepropertyname 'vsanCidr' -notepropertyvalue $instanceObject.stretchCluster.witnessVsanCidr
    $witnessSpecObject | Add-Member -notepropertyname 'vsanIp' -notepropertyvalue $instanceObject.stretchCluster.witnessVsanIp

    $stretchedClusterObject = New-Object -TypeName psobject
    If ($instanceObject.release -ne "vcf5")
    {
        $stretchedClusterObject | Add-Member -notepropertyname 'deployWithoutLicenseKeys' -notepropertyvalue $true
    }
    $stretchedClusterObject | Add-Member -notepropertyname 'hostSpecs' -notepropertyvalue $hostSpecsObject
    If ($instanceObject.az2.rack1.network.hostOverlayAddressing -in "IP Pool", "Static IP Pool")
    {
        $stretchedClusterObject | Add-Member -notepropertyname 'networkSpec' -notepropertyvalue ($networkObject | Select-Object -Skip 0)
    }
    else
    {
        $stretchedClusterObject | Add-Member -notepropertyname 'secondaryAzOverlayVlanId' -notepropertyvalue $([INT]($instanceObject.az2.rack1.network.hostOverlayVlanID))
    }
    $stretchedClusterObject | Add-Member -notepropertyname 'isEdgeClusterConfiguredForMultiAZ' -notepropertyvalue $true
    $stretchedClusterObject | Add-Member -notepropertyname 'witnessSpec' -notepropertyvalue $witnessSpecObject
    $stretchedClusterObject | Add-Member -notepropertyname 'witnessTrafficSharedWithVsanTraffic' -notepropertyvalue $false
    
    $jsonObject = New-Object -TypeName psobject
    $jsonObject | Add-Member -notepropertyname 'clusterStretchSpec' -notepropertyvalue $stretchedClusterObject
    LogMessage -Type INFO -Message "Exporting the Cluster stretch JSON to stretchClusterSpec-$($instanceObject.vsphereClusters[0].clusterName).json"
    ConvertTo-Json $jsonObject -depth 12 | Out-File -Encoding UTF8 -FilePath "stretchClusterSpec-$($instanceObject.vsphereClusters[0].clusterName).json"    
}

Function New-SingleOperationStretchedComputeClusterJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$clusterObject
    )
    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Domain, Host, Image and Datastore IDs from SDDC Manager/vCenter? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "SDDC Manager FQDN: " -skipnewline
            $sddcMgrFqdn = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator: " -skipnewline
            $sddcMgrUser = Read-Host
            LogMessage -type INFO -message "SDDC Manager Administrator password: " -skipnewline
            $adminPassword = Read-Host -AsSecureString
            $decodedPassword = New-DecodedPassword -securePassword $adminPassword
            New-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $decodedPassword *>$null
            If (!($accessToken))
            {
                LogMessage -type ERROR -message "Failed to connect to $sddcMgrFqdn. Please check details and try again"
            }
        } Until ($accessToken)
        Do
        {
            LogMessage -type INFO -message "vCenter FQDN: " -skipnewline
            $vCenterFqdn = Read-Host
            LogMessage -type INFO -message "vCenter Administrator: " -skipnewline
            $vCenterAdminUser = Read-Host
            LogMessage -type INFO -message "vCenter Administrator password: " -skipnewline
            $vCenterPassword = Read-Host -AsSecureString
            $decodedVcenterPassword = New-DecodedPassword -securePassword $vCenterPassword
            $vCenterConnection = Connect-VIServer -server $vCenterFQDN -user $vCenterAdminUser -password $decodedvCenterPassword -errorAction SilentlyContinue
            If (!($vCenterConnection))
            {
                LogMessage -type ERROR -message "Failed to connect to successfully read information from $vCenterFqdn. Please check details and try again"
            }
        } Until ($vCenterConnection)
    }
    
    $rack = "rack1"

    $vmnicObject = @()
    $vmnicObject += [pscustomobject]@{
        'id'      = $clusterObject.vsphereClusters[0].vds[0].pnics.split(",")[0]
        'vdsName' = $clusterObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink1"
    }
    $vmnicObject += [pscustomobject]@{
        'id'      = $clusterObject.vsphereClusters[0].vds[0].pnics.split(",")[1]
        'vdsName' = $clusterObject.vsphereClusters[0].vds[0].vdsName
        'uplink' = "uplink2"
    }
    If ($clusterObject.vsphereClusters[0].vdsProfile -in "Storage Traffic Separation","NSX Traffic Separation")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
    }
    If ($clusterObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic and NSX Traffic Separation")
    {
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[1].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'uplink' = "uplink2"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[2].pnics.split(",")[0]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink1"
        }
        $vmnicObject += [pscustomobject]@{
            'id'      = $clusterObject.vsphereClusters[0].vds[2].pnics.split(",")[1]
            'vdsName' = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'uplink' = "uplink2"
        }
    }     

    $hostArray = @()
    $hostCounter = 0
    #$selectedHosts = @(0..$([INT]$clusterObject.az1.$($rack).hosts.count -1))

    Foreach ($selectedHost in $clusterObject.az1.$($rack).hosts)
    {
        If ($interactiveEnabled -eq "Y")
        {
            $hostID = Get-VCFHostDetails -Status UNASSIGNED_USEABLE | Select-Object fqdn, id | Where-Object { $_.fqdn -eq $selectedHost.fqdn }
            If ($hostID)
            {
                LogMessage -Type INFO -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Found"
                $hostIdValue = $hostId.id
            }
            else
            {
                LogMessage -Type WARNING -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Not found. Not adding to JSON File"
                $hostIdValue = "None Found"
            }
        }
        else
        {
            $hostIdValue = "<--ENTER-SDDC-HOSTID-HERE-->"
        }
        
        $hostnetworkObject = @()
        $hostnetworkObject += [pscustomobject]@{
            "networkProfileName" =  "$($clusterObject.az1.$($rack).network.networkProfileName)"
            'vmNics' = $vmnicObject
        }
        If ($hostIdValue -ne "None Found")
        {
            $newHost = [pscustomobject]@{
                'id'                = $hostIdValue
                'hostname'          = $selectedHost.fqdn
                'azName'            = "$($clusterObject.vsphereClusters[0].clusterName)_primary-az-faultdomain"
                'hostNetworkSpec'   = ($hostnetworkObject | Select-Object -Skip 0)
            }
            $hostArray += $newHost
        }
        $hostCounter++
    }

    Foreach ($selectedHost in $clusterObject.az2.$($rack).hosts)
    {
        If ($interactiveEnabled -eq "Y")
        {
            $hostID = Get-VCFHostDetails -Status UNASSIGNED_USEABLE | Select-Object fqdn, id | Where-Object { $_.fqdn -eq $selectedHost.fqdn }
            If ($hostID)
            {
                LogMessage -Type INFO -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Found"
                $hostIdValue = $hostId.id
            }
            else
            {
                LogMessage -Type WARNING -Message "Obtaining Host ID from SDDC Manager for host $($selectedHost.fqdn): Not found. Not adding to JSON File"
                $hostIdValue = "None Found"
            }
        }
        else
        {
            $hostIdValue = "<--ENTER-SDDC-HOSTID-HERE-->"
        }
        
        $hostnetworkObject = @()
        $hostnetworkObject += [pscustomobject]@{
            "networkProfileName" =  "$($clusterObject.az2.$($rack).network.networkProfileName)"
            'vmNics' = $vmnicObject
        }
        If ($hostIdValue -ne "None Found")
        {
            $newHost = [pscustomobject]@{
                'id'                = $hostIdValue
                'hostname'          = $selectedHost.fqdn
                'azName'            = "$($clusterObject.vsphereClusters[0].clusterName)_secondary-az-faultdomain"
                'hostNetworkSpec'   = ($hostnetworkObject | Select-Object -Skip 0)
            }
            $hostArray += $newHost
        }
        $hostCounter++
    }

    
    If ($clusterObject.stretchCluster.networkTopology -eq "Asymmetric")
    {
        $siteAffinity = @()
        If ($clusterObject.stretchCluster.faultDomainMapping -eq "Primary")
        {
            $siteAffinity += [pscustomobject]@{
                'serverSite' = "$($clusterObject.vsphereClusters[0].vsanStorageClusterName)_primary-az-faultdomain"
                'clientSite' = "$($clusterObject.vsphereClusters[0].clusterName)_primary-az-faultdomain"
            }
            $siteAffinity += [pscustomobject]@{
                'serverSite' = "$($clusterObject.vsphereClusters[0].vsanStorageClusterName)_secondary-az-faultdomain"
                'clientSite' = "$($clusterObject.vsphereClusters[0].clusterName)_secondary-az-faultdomain"
            }        
        }
        else 
        {
            $siteAffinity += [pscustomobject]@{
                'serverSite' = "$($clusterObject.vsphereClusters[0].vsanStorageClusterName)_primary-az-faultdomain"
                'clientSite' = "$($clusterObject.vsphereClusters[0].clusterName)_secondary-az-faultdomain"
            }
            $siteAffinity += [pscustomobject]@{
                'serverSite' = "$($clusterObject.vsphereClusters[0].vsanStorageClusterName)_secondary-az-faultdomain"
                'clientSite' = "$($clusterObject.vsphereClusters[0].clusterName)_primary-az-faultdomain"
            }            
        }
    }
    
    If ($clusterObject.determinedClusterConfig -eq "Stretched Compute Only")
    {
        If ($interactiveEnabled -eq "Y")
        {
            $datastoreUuid = (Get-Datastore -name $clusterObject.vsphereClusters[0].vsanDatastore).ExtensionData.info.ContainerId
        }
        else
        {
            $datastoreUuid = '<-- ENTER UUID OF REMOTE DATASTORE HERE -->'
        }
        $vsanRemoteDatastoreObject = @()
        $vsanRemoteDatastoreObject += [pscustomobject]@{
            'datastoreUuid'      = $datastoreUuid
            'networkTopology'    = $clusterObject.stretchCluster.networkTopology
        }
        If ($clusterObject.stretchCluster.networkTopology -eq "Asymmetric")
        {
            $vsanRemoteDatastoreObject | Add-Member -NotePropertyName 'siteAffinity' -NotePropertyValue $siteAffinity
        }

        $vsanRemoteDatastoreSpecArray = @()
        $vsanRemoteDatastoreSpecArray += $vsanRemoteDatastoreObject

        $vsanRemoteDatastoreClusterSpecObject = New-Object -type psobject
        $vsanRemoteDatastoreClusterSpecObject | Add-Member -NotePropertyName 'isStretched' -NotePropertyValue $true
        $vsanRemoteDatastoreClusterSpecObject | Add-Member -NotePropertyName 'primaryAzName' -NotePropertyValue "$($clusterObject.vsphereClusters[0].clusterName)_primary-az-faultdomain"
        $vsanRemoteDatastoreClusterSpecObject | Add-Member -NotePropertyName 'vsanRemoteDatastoreSpec' -NotePropertyValue $vsanRemoteDatastoreSpecArray

        $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanRemoteDatastoreClusterSpec' = $vsanRemoteDatastoreClusterSpecObject
        }
    }

    $activeUplinksArray = @()
    $activeUplinksArray += "uplink1"
    $activeUplinksArray += "uplink2"

    $portgroupObject = @()
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.mgmt
        'transportType' = "MANAGEMENT"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vmotion
        'transportType' = "VMOTION"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    $portgroupObject += [pscustomobject]@{
        'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vsan
        'transportType' = "VSAN"
        'standByUplinks' = @()
        'teamingPolicy' = "loadbalance_loadbased"
        'activeUplinks' = $activeUplinksArray
    }
    If (($clusterObject.vsphereClusters[0].storageModel -eq "vSAN Storage Cluster") -and ($clusterObject.vsphereClusters[0].secondaryStorage -eq "vSAN Storage Client Network") -and ($clusterObject.vsphereClusters[0].vdsProfile -ne "Default"))
    {
        $portgroupObject += [pscustomobject]@{
            'name'          = $clusterObject.vsphereClusters[0].portgroupNames.az1.vsanClient
            'transportType' = "VSAN_EXTERNAL"
            'standByUplinks' = @()
            'teamingPolicy' = "loadbalance_loadbased"
            'activeUplinks' = $activeUplinksArray
        }
    }

    $vdsMtu = $clusterObject.vsphereClusters[0].vds[0].mtu -as [string]
    
    $transportZoneArray = @()
    $transportZoneArray += [pscustomobject]@{
        'name'          = "nsx-vlan-transportzone"
        'transportType' = "VLAN"
    }
    $transportZoneArray += [pscustomobject]@{
        'name'          = "overlay-tz-$($clusterObject.tzName)"
        'transportType' = "OVERLAY"
    }
    
    $nsxtSwitchConfigObject = New-Object -type psobject
    If ($clusterObject.vsphereClusters[0].nsxOperationDefaultMode -eq "Selected")
    {
        $operationMode = "ENS_INTERRUPT"
    }
    else
    {
        If ($clusterObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Standard")
        {
            $operationMode = "STANDARD"
        }
        elseif ($clusterObject.vsphereClusters[0].nsxOperationSelectedMode -eq "Enhanced Datapath Standard")
        {
            $operationMode = "ENS_INTERRUPT"
        }
        else 
        {
            < $operationMode = "ENS"
        }
    }
    $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'hostSwitchOperationalMode' -NotePropertyValue $operationMode
    $nsxtSwitchConfigObject | Add-Member -NotePropertyName 'transportZones' -NotePropertyValue $transportZoneArray
        
    $vdsObject = @()
    If ($clusterObject.vsphereClusters[0].vdsProfile -eq "Default")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }
    elseif ($clusterObject.vsphereClusters[0].vdsProfile -eq "Storage Traffic Separation")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
        }
    }
    elseif ($clusterObject.vsphereClusters[0].vdsProfile -eq "NSX Traffic Separation")
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN","VSAN_EXTERNAL"}
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }
    else
    {
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[0].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = $portgroupObject | Where-Object {$_.transportType -in "MANAGEMENT","VMOTION","VSAN_EXTERNAL"}
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[1].vdsName
            'mtu' = $vdsMtu
            'portGroupSpecs' = @($portgroupObject | Where-Object {$_.transportType -in "VSAN"})
        }
        $vdsObject += [pscustomobject]@{
            'name'         = $clusterObject.vsphereClusters[0].vds[2].vdsName
            'mtu' = $vdsMtu
            'nsxtSwitchConfig' = $nsxtSwitchConfigObject
        }
    }

    #uplink profiles
    $teamingsArray = @()
    $teamingsArray += [pscustomobject]@{
        'name' = "DEFAULT"
        'policy' = "LOADBALANCE_SRCID"
        'standByUplinks' = @()
        'activeUplinks' = $activeUplinksArray
    }

    
    If ($clusterObject.az1.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
    {
        $newAz1HostPoolName = $clusterObject.az1.$($rack).network.hostIpAddressPoolName
    }
    else
    {
        $newAz1HostPoolName = $null
    }
    $newAz1NetworkProfileName = $clusterObject.az1.$($rack).network.networkProfileName
    $newAz1UplinkProfileName = $clusterObject.az1.$($rack).network.uplinkProfileName
    $newAz1HostPoolStartIp = $clusterObject.az1.$($rack).network.hostOverlayPoolStartIP
    $newAz1HostPoolEndIp = $clusterObject.az1.$($rack).network.hostOverlayPoolEndIP

    If ($clusterObject.az2.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
    {
        $newAz2HostPoolName = $clusterObject.az2.$($rack).network.hostIpAddressPoolName
    }
    else
    {
        $newAz2HostPoolName = $null
    }
    $newAz2NetworkProfileName = $clusterObject.az2.$($rack).network.networkProfileName
    $newAz2UplinkProfileName = $clusterObject.az2.$($rack).network.uplinkProfileName
    $newAz2HostPoolStartIp = $clusterObject.az2.$($rack).network.hostOverlayPoolStartIP
    $newAz2HostPoolEndIp = $clusterObject.az2.$($rack).network.hostOverlayPoolEndIP

    $uplinkProfilesArray = @()
    
    $uplinkProfile = New-Object -type PSObject
    $uplinkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newAz1UplinkProfileName
    $uplinkProfile | Add-Member -NotePropertyName 'transportVlan' -NotePropertyValue $([INT]($clusterObject.az1.$($rack).network.hostOverlayVlanID))
    $uplinkProfile | Add-Member -NotePropertyName 'teamings' -NotePropertyValue $teamingsArray
    $uplinkProfilesArray += $uplinkProfile

    $uplinkProfile = New-Object -type PSObject
    $uplinkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newAz2UplinkProfileName
    $uplinkProfile | Add-Member -NotePropertyName 'transportVlan' -NotePropertyValue $([INT]($clusterObject.az2.$($rack).network.hostOverlayVlanID))
    $uplinkProfile | Add-Member -NotePropertyName 'teamings' -NotePropertyValue $teamingsArray
    $uplinkProfilesArray += $uplinkProfile

    #ipAddressPoolsSpec
    $ipAddressPoolsSpecArray = @()    
    $ipAddressPoolRangesArray = @()

    If (($clusterObject.az1.$($rack).network.hostOverlayAddressing -ne "Static IP Pool") -and ($clusterObject.az2.$($rack).network.hostOverlayAddressing -ne "Static IP Pool"))
    {
        $ipAddressPoolsSpecArray = $null
    }
    else 
    {
        If ($clusterObject.az1.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
        {
            If ($clusterObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
            {
                $ipAddressPoolRangesArray += [pscustomobject]@{
                    'start' = $newAz1HostPoolStartIp
                    'end' = $newAz1HostPoolEndIp
                }
            
                $subnetsArray = @()
                $subnetsArray += [pscustomobject]@{
                    'cidr' = $clusterObject.az1.$($rack).network.hostOverlayCidr
                    'gateway' = $clusterObject.az1.$($rack).network.hostOverlayGw
                    'ipAddressPoolRanges' = $ipAddressPoolRangesArray
                }
            }
    
            $ipAddressSpec = New-Object -type PSObject
            $ipAddressSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $newAz1HostPoolName
            If ($clusterObject.az1.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
            {
                $ipAddressSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
            }
            $ipAddressPoolsSpecArray += $ipAddressSpec
        }
        If ($clusterObject.az2.$($rack).network.hostOverlayAddressing -eq "Static IP Pool")
        {
            If ($clusterObject.az2.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
            {
                $ipAddressPoolRangesArray += [pscustomobject]@{
                    'start' = $newAz2HostPoolStartIp
                    'end' = $newAz2HostPoolEndIp
                }
            
                $subnetsArray = @()
                $subnetsArray += [pscustomobject]@{
                    'cidr' = $clusterObject.az2.$($rack).network.hostOverlayCidr
                    'gateway' = $clusterObject.az2.$($rack).network.hostOverlayGw
                    'ipAddressPoolRanges' = $ipAddressPoolRangesArray
                }
            }

            $ipAddressSpec = New-Object -type PSObject
            $ipAddressSpec | Add-Member -NotePropertyName 'name' -NotePropertyValue $newAz2HostPoolName
            If ($clusterObject.az2.$($rack).network.reuseExistingStaticIpPool -eq "Create New Static IP Pool")
            {
                $ipAddressSpec | Add-Member -NotePropertyName 'subnets' -NotePropertyValue $subnetsArray
            }
            $ipAddressPoolsSpecArray += $ipAddressSpec
        }
    }
    
    
    
    $nsxTClusterObject = @()
    $nsxTClusterObject += [pscustomobject]@{
        'ipAddressPoolsSpec' = $ipAddressPoolsSpecArray
        'uplinkProfiles' = $uplinkProfilesArray
    }   

    $nsxClusterObject = @()
    $nsxClusterObject += [pscustomobject]@{
        'nsxTClusterSpec' = ($nsxTClusterObject | Select-Object -Skip 0)
    }

    $vdsUplinkToNsxUplinkArray = @()
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink1"
        'vdsUplinkName' = "uplink1"
    }
    $vdsUplinkToNsxUplinkArray += [pscustomobject]@{
        'nsxUplinkName' = "uplink2"
        'vdsUplinkName' = "uplink2"
    }

    If ($clusterObject.vsphereClusters[0].vdsProfile -in "NSX Traffic Separation")
    {
        $vdsName = $clusterObject.vsphereClusters[0].vds[1].vdsName
    }
    elseIf ($clusterObject.vsphereClusters[0].vdsProfile -in "Storage Traffic and NSX Traffic Separation")
    {
        $vdsName = $clusterObject.vsphereClusters[0].vds[2].vdsName
    }
    else
    {
        $vdsName = $clusterObject.vsphereClusters[0].vds[0].vdsName
    }

    $nsxtAz1HostSwitchConfigs = @()
    $nsxtAz1HostSwitchConfigs += [pscustomobject]@{
        'ipAddressPoolName' = $newAz1HostPoolName
        'uplinkProfileName' = $newAz1UplinkProfileName
        'vdsName' = $vdsName
        'vdsUplinkToNsxUplink' = $vdsUplinkToNsxUplinkArray
    }

    $networkProfilesArray = @()
    $rackNetworkProfile = New-Object -type psobject
    $rackNetworkProfile | Add-Member -NotePropertyName 'isDefault' -NotePropertyValue $(If ($networkProfilesArray.count -eq 0) {$true} else {$false})
    $rackNetworkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newAz1NetworkProfileName
    $rackNetworkProfile | Add-Member -NotePropertyName 'nsxtHostSwitchConfigs' -NotePropertyValue $nsxtAz1HostSwitchConfigs
    $networkProfilesArray += $rackNetworkProfile  

    $nsxtAz2HostSwitchConfigs = @()
    $nsxtAz2HostSwitchConfigs += [pscustomobject]@{
        'ipAddressPoolName' = $newAz2HostPoolName
        'uplinkProfileName' = $newAz2UplinkProfileName
        'vdsName' = $vdsName
        'vdsUplinkToNsxUplink' = $vdsUplinkToNsxUplinkArray
    }
    
    $rackNetworkProfile = New-Object -type psobject
    $rackNetworkProfile | Add-Member -NotePropertyName 'isDefault' -NotePropertyValue $(If ($networkProfilesArray.count -eq 0) {$true} else {$false})
    $rackNetworkProfile | Add-Member -NotePropertyName 'name' -NotePropertyValue $newAz2NetworkProfileName
    $rackNetworkProfile | Add-Member -NotePropertyName 'nsxtHostSwitchConfigs' -NotePropertyValue $nsxtAz2HostSwitchConfigs
    $networkProfilesArray += $rackNetworkProfile  

    $networkObject = @()
    $networkObject += [pscustomobject]@{
        'vdsSpecs'       = $vdsObject
        'nsxClusterSpec' = ($nsxClusterObject | Select-Object -Skip 0)
        'networkProfiles' = $networkProfilesArray
    }

    $clusterSpecObject = @()
    $clusterSpecObject += [pscustomobject]@{
        'name'        = $clusterObject.vsphereClusters[0].clusterName
        'hostSpecs'     = $hostArray
        'datastoreSpec' = ($vsanObject | Select-Object -Skip 0)
        'networkSpec'   = ($networkObject | Select-Object -Skip 0)
    }
    
    If ($clusterObject.vsphereClusters[0].vlcmModel -eq "Images") 
    {
        If ($interactiveEnabled -eq "Y")
        {
            LogMessage -Type INFO -Message "Obtaining Cluster Image Personality ID from SDDC Manager"
            $clusterImageId = (Get-VCFPersonalityDetails | Where-Object { $_.personalityName -eq $clusterObject.vsphereClusters[0].imageName }).personalityId
        }
        else
        {
            $clusterImageId = "<--ENTER-SDDC-PERSONALITY-NAME-HERE-->"
        }
        $clusterSpecObject[0] | Add-Member -NotePropertyName 'clusterImageId' -NotePropertyValue $clusterImageId
    }

    $computeSpecObject = @()
    $computeSpecObject += [pscustomobject]@{
        'clusterSpecs' = $clusterSpecObject
    }

    If ($interactiveEnabled -eq "Y")
    {
        $domainID = (Get-VCFWorkloadDomainDetails -name $clusterObject.domainName).id
        If ($domainID)
        {
            LogMessage -Type INFO -Message "Obtaining Domain ID from SDDC Manager for domain $($clusterObject.domainName): Found"
            $domainIDValue = $domainID
        }
        else
        {
            LogMessage -Type ERROR -Message "Obtaining Domain ID from SDDC Manager for domain $($clusterObject.domainName): Not found. Adding placeholder to JSON File"
            $domainIDValue = "<--ENTER-SDDC-DOMAINID-HERE-->"
        }
    }
    else
    {
        $domainIDValue = "<--ENTER-SDDC-DOMAINID-HERE-->"
    }

    $clusterJsonObject = @()
    $clusterJsonObject += [pscustomobject]@{
        'domainId' = $domainIDValue
        'computeSpec'  = ($computeSpecObject | Select-Object -Skip 0)
    }
    $clusterJsonObject | Add-Member -notepropertyname 'deployWithoutLicenseKeys' -notepropertyvalue "true"
    LogMessage -Type INFO -Message "Exporting the Cluster Creation JSON to clusterSpec-$($clusterObject.vsphereClusters[0].clusterName).json"
    $clusterJsonObject | ConvertTo-Json -Depth 12 | Out-File -Encoding UTF8 -FilePath "clusterSpec-$($clusterObject.vsphereClusters[0].clusterName).json"
    LogMessage -Type NOTE -Message "Completed the Process of Generating the Cluster Creation JSON"
}

Function New-DecodedPassword
{
    Param (
        [Parameter (Mandatory = $true)] [securestring]$securePassword
    )
    If ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
    {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $decodedPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    else
    {
        $serializedSecureString = $securePassword | ConvertFrom-SecureString
        $byteArray = [byte[]] -split ($serializedSecureString -replace '..', '0x$& ')
        $decodedPassword = [System.Text.Encoding]::Unicode.GetString($byteArray)
    }
    Return $decodedPassword
}

#Edge JSON Files
Function New-EdgeJSONFile
{
    Param (
        [Parameter (Mandatory = $true)] [Object]$instanceObject
    )
    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve Transport Zone, Host Switch Profile and Target Infrastructure IDs from NSX Manager/vCenter? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "NSX Manager FQDN: " -skipnewline
            $nsxtManagerFqdn = Read-Host
            LogMessage -type INFO -message "NSX Manager Administrator: " -skipnewline
            $nsxtManagerAdminUser = Read-Host
            LogMessage -type INFO -message "NSX Manager Administrator password: " -skipnewline
            $nsxtManagerPassword = Read-Host -AsSecureString
            $decodedNsxPassword = New-DecodedPassword -securePassword $nsxtManagerPassword
            $overlayTransportZoneId = (Get-NsxTransportZones -nsxtManagerFqdn $nsxtManagerFqdn -nsxtusername $nsxtManagerAdminUser -nsxtpassword $decodedNsxPassword | Where-Object {$_.tz_type -in "OVERLAY_STANDARD","OVERLAY_BACKED" -and $_.is_default -eq "True"}).nsx_id
            If (!($overlayTransportZoneId))
            {
                LogMessage -type ERROR -message "Failed to connect to successfully read information from $nsxtManagerFqdn. Please check details and try again"
            }
        } Until ($overlayTransportZoneId)
        Do
        {
            LogMessage -type INFO -message "vCenter FQDN: " -skipnewline
            $vCenterFqdn = Read-Host
            LogMessage -type INFO -message "vCenter Administrator: " -skipnewline
            $vCenterAdminUser = Read-Host
            LogMessage -type INFO -message "vCenter Administrator password: " -skipnewline
            $vCenterPassword = Read-Host -AsSecureString
            $decodedVcenterPassword = New-DecodedPassword -securePassword $vCenterPassword
            $vCenterConnection = Connect-VIServer -server $vCenterFQDN -user $vCenterAdminUser -password $decodedvCenterPassword -errorAction SilentlyContinue
            If (!($vCenterConnection))
            {
                LogMessage -type ERROR -message "Failed to connect to successfully read information from $vCenterFqdn. Please check details and try again"
            }
        } Until ($vCenterConnection)
    }

    If ($interactiveEnabled -eq "Y")
    {
        $overlayTransportZonePath = (Get-NsxTransportZones -nsxtManagerFqdn $nsxtManagerFqdn -nsxtusername $nsxtManagerAdminUser -nsxtpassword $decodedNsxPassword | Where-Object {$_.tz_type -in "OVERLAY_BACKED" -and $_.is_default -eq "True"}).path
        $computeCollection1 = Get-NsxComputeCollections -nsxtManagerFqdn $nsxtManagerFqdn -nsxtUsername $nsxtManagerAdminUser -nsxtPassword $decodedNSXPassword  | Where-Object {$_.display_name -eq $instanceObject.edgeCluster.nodes.node1.clusterName}
        $computeCollection2 = Get-NsxComputeCollections -nsxtManagerFqdn $nsxtManagerFqdn -nsxtUsername $nsxtManagerAdminUser -nsxtPassword $decodedNSXPassword  | Where-Object {$_.display_name -eq $instanceObject.edgeCluster.nodes.node2.clusterName}
        $vCenterId = $computeCollection1.origin_id
        $computeId1 = $computeCollection1.cm_local_id
        $computeId2 = $computeCollection2.cm_local_id
        $storageId1 = (Get-Cluster -name $instanceObject.edgeCluster.nodes.node1.clusterName | Get-Datastore | Where-Object {$_.name -eq $instanceObject.edgeCluster.nodes.node1.datastoreName}).id.split("Datastore-")[1]
        $storageId2 = (Get-Cluster -name $instanceObject.edgeCluster.nodes.node2.clusterName | Get-Datastore | Where-Object {$_.name -eq $instanceObject.edgeCluster.nodes.node2.datastoreName}).id.split("Datastore-")[1]
        $edgeTrunk01PortgroupId = (Get-VDPortGroup -name $instanceObject.edgeCluster.edgeTrunk01PortgroupName).key
        $edgeTrunk02PortgroupId = (Get-VDPortGroup -name $instanceObject.edgeCluster.edgeTrunk02PortgroupName).key
        $mgmtPortGroupID1 = (Get-VDPortGroup -name $instanceObject.edgeCluster.nodes.node1.vmManagementPorgroupName).key
        $mgmtPortGroupID2 = (Get-VDPortGroup -name $instanceObject.edgeCluster.nodes.node2.vmManagementPorgroupName).key
    }
    else
    {
        $overlayTransportZonePath = '<-- ENTER OVERLAY TRANSPORT ZONE PATH HERE -->'
        $vCenterId = '<-- ENTER VCENTER ID HERE -->'
        $computeId1 = '<-- ENTER CLUSTER ID FOR FIRST EDGE NODE HERE -->'
        $computeId2 = '<-- ENTER CLUSTER ID FOR SECOND EDGE NODE HERE -->'
        $storageId1 = '<-- ENTER DATASTORE ID FOR FIRST EDGE NODE HERE -->'
        $storageId2 = '<-- ENTER DATASTORE ID FOR SECOND EDGE NODE HERE -->'
        $edgeTrunk01PortgroupId = '<-- ENTER EDGE TRUNK01 PORTGROUP ID HERE -->'
        $edgeTrunk02PortgroupId = '<-- ENTER EDGE TRUNK02 PORTGROUP ID HERE -->'
        $mgmtPortGroupID1 = '<-- ENTER MANAGEMENT PORTGROUP ID FOR FIRST EDGE NODE HERE -->'
        $mgmtPortGroupID2 = '<-- ENTER MANAGEMENT PORTGROUP ID FOR SECOND EDGE NODE HERE -->'
    }

    #Start JSON Creation

    $childrenArray = @()

    # Start ChildResource Reference Child

    #common
    $applianceConfigObject = New-Object -type psobject
    $applianceConfigObject | Add-Member -NotePropertyName 'search_domains' -NotePropertyValue @()
    $applianceConfigObject | Add-Member -NotePropertyName 'dns_servers' -NotePropertyValue @()

    #Edge Node 1
    $PolicyEdgeTransportNode1MgmtPortSubnetsArray = @()
    $PolicyEdgeTransportNode1MgmtPortSubnetsArray += [PSCustomObject]@{
        'ip_addresses' = @($instanceObject.edgeCluster.nodes.node1.mgmtAddress)
        'prefix_length' = ($instanceObject.edgeCluster.nodes.node1.mgmtPrefixLength -as [INT])
    }

    $PolicyEdgeTransportNode1IpAssignmentSpecsArray = @()
    $PolicyEdgeTransportNode1IpAssignmentSpecsArray += [PSCustomObject]@{
        'ip_assignment_type' = "StaticIpv4"
        'management_port_subnets' = @($PolicyEdgeTransportNode1MgmtPortSubnetsArray)
        'default_gateway' = @($instanceObject.edgeCluster.nodes.node1.mgmtGateway)
    }

    $PolicyEdgeTransportNode1ManagementInterfaceObject = New-Object -type psobject
    $PolicyEdgeTransportNode1ManagementInterfaceObject | Add-Member -NotePropertyName 'network_id' -NotePropertyValue $mgmtPortGroupID1
    $PolicyEdgeTransportNode1ManagementInterfaceObject | Add-Member -NotePropertyName 'ip_assignment_specs' -NotePropertyValue @($PolicyEdgeTransportNode1IpAssignmentSpecsArray)

    $pnic1Object = New-Object -type psobject
    $pnic1Object | Add-Member -NotePropertyName 'device_name' -NotePropertyValue "fp-eth0"
    $pnic1Object | Add-Member -NotePropertyName 'uplink_name' -NotePropertyValue "uplink-1"
    $pnic1Object | Add-Member -NotePropertyName 'datapath_network_id' -NotePropertyValue $edgeTrunk01PortgroupId

    $pnic2Object = New-Object -type psobject
    $pnic2Object | Add-Member -NotePropertyName 'device_name' -NotePropertyValue "fp-eth1"
    $pnic2Object | Add-Member -NotePropertyName 'uplink_name' -NotePropertyValue "uplink-2"
    $pnic2Object | Add-Member -NotePropertyName 'datapath_network_id' -NotePropertyValue $edgeTrunk02PortgroupId

    $profilePaths = @()
    $profilePaths += [PSCustomObject]@{
        'key' = "UplinkHostSwitchProfile"
        'value' = "/infra/host-switch-profiles/$($instanceObject.edgeCluster.hostSwitchProfileId)"
    }

    $ipAssignmentSpecArray = @()

    $ipAssignmentSpecObject = New-Object -type psobject
    $ipAssignmentSpecObject | Add-Member -NotePropertyName 'ip_assignment_type' -NotePropertyValue $instanceObject.edgeCluster.tepMode
    If ($instanceObject.edgeCluster.tepMode -eq "StaticIpv4List")
    {
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'ip_list' -NotePropertyValue @($instanceObject.edgeCluster.nodes.node1.overlayIpAddress1,$instanceObject.edgeCluster.nodes.node1.overlayIpAddress2)
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'default_gateway' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.overlayGateway
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'subnet_mask' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.overlayMask

    }
    elseIf ($instanceObject.edgeCluster.tepMode -eq "StaticIpv4Pool")
    {
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'ip_pool' -NotePropertyValue "/infra/ip-pools/$($instanceObject.edgeCluster.ipPoolName)"
    }
    $ipAssignmentSpecArray += $ipAssignmentSpecObject

    $tunnelEndpointsObject = New-Object -type psobject
    $tunnelEndpointsObject | Add-Member -NotePropertyName 'ip_assignment_specs' -NotePropertyValue $ipAssignmentSpecArray
    $tunnelEndpointsObject | Add-Member -NotePropertyName 'vlan' -NotePropertyValue ($instanceObject.edgeCluster.edgeNodeTunnelEndpointVlan -as [int])

    $PolicyEdgeTransportNode1SwitchObject = New-Object -type psobject
    $PolicyEdgeTransportNode1SwitchObject | Add-Member -NotePropertyName 'pnics' -NotePropertyValue @($pnic1Object,$pnic2Object)
    $PolicyEdgeTransportNode1SwitchObject | Add-Member -NotePropertyName 'overlay_transport_zone_paths' -NotePropertyValue @($overlayTransportZonePath)
    $PolicyEdgeTransportNode1SwitchObject | Add-Member -NotePropertyName 'vlan_transport_zone_paths' -NotePropertyValue @("/infra/sites/default/enforcement-points/default/transport-zones/$($instanceObject.edgeCluster.vlanTransportZoneId)")
    $PolicyEdgeTransportNode1SwitchObject | Add-Member -NotePropertyName 'profile_paths' -NotePropertyValue @($profilePaths)
    $PolicyEdgeTransportNode1SwitchObject | Add-Member -NotePropertyName 'tunnel_endpoints' -NotePropertyValue @($tunnelEndpointsObject)
    $PolicyEdgeTransportNode1SwitchObject | Add-Member -NotePropertyName 'switch_name' -NotePropertyValue "nsxDefaultHostSwitch"

    $PolicyEdgeTransportNode1SwitchesArray = @()
    $PolicyEdgeTransportNode1SwitchesArray += $PolicyEdgeTransportNode1SwitchObject

    $PolicyEdgeTransportNode1SwitchSpecObject = New-Object -type psobject
    $PolicyEdgeTransportNode1SwitchSpecObject | Add-Member -NotePropertyName 'switches' -NotePropertyValue @($PolicyEdgeTransportNode1SwitchesArray)

    $edge1DeploymentConfig = New-Object -type psobject
    $edge1DeploymentConfig | Add-Member -NotePropertyName 'vc_id' -NotePropertyValue $vCenterId
    $edge1DeploymentConfig | Add-Member -NotePropertyName 'compute_id' -NotePropertyValue $computeId1
    $edge1DeploymentConfig | Add-Member -NotePropertyName 'storage_id' -NotePropertyValue $storageId1
    $edge1DeploymentConfig | Add-Member -NotePropertyName 'placement_type' -NotePropertyValue $instanceObject.edgeCluster.placementType

    If ($instanceObject.edgeCluster.hostGroupAffinity -eq "yes")
    {
        $edge1HostAffinityConfigObject = New-Object -Type psobject
        $edge1HostAffinityConfigObject | Add-Member -NotePropertyName 'host_group_name' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.hostGroupName
        $edge1DeploymentConfig | Add-Member -NotePropertyName 'edge_host_affinity_config' -NotePropertyValue $edge1HostAffinityConfigObject
    }

    $PolicyEdgeTransportNode1Object = New-Object -type psobject
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.hostname
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'credentials' -NotePropertyValue (New-Object -type psobject)
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'deployment_type' -NotePropertyValue "VIRTUAL_MACHINE"
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "PolicyEdgeTransportNode"
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'display_name' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.name
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'id' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.name
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'vm_deployment_config' -NotePropertyValue $edge1DeploymentConfig
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'management_interface' -NotePropertyValue $PolicyEdgeTransportNode1ManagementInterfaceObject
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'switch_spec' -NotePropertyValue $PolicyEdgeTransportNode1SwitchSpecObject
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'form_factor' -NotePropertyValue $instanceObject.edgeCluster.nodes.node1.formfactor.toUpper()
    $PolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'appliance_config' -NotePropertyValue $applianceConfigObject

    $ChildPolicyEdgeTransportNode1Object = New-Object -type psobject
    $ChildPolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'PolicyEdgeTransportNode' -NotePropertyValue $PolicyEdgeTransportNode1Object
    $ChildPolicyEdgeTransportNode1Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildPolicyEdgeTransportNode"

    #Edge Node 2
    $PolicyEdgeTransportNode2MgmtPortSubnetsArray = @()
    $PolicyEdgeTransportNode2MgmtPortSubnetsArray += [PSCustomObject]@{
        'ip_addresses' = @($instanceObject.edgeCluster.nodes.node2.mgmtAddress)
        'prefix_length' = ($instanceObject.edgeCluster.nodes.node2.mgmtPrefixLength -as [INT])
    }

    $PolicyEdgeTransportNode2IpAssignmentSpecsArray = @()
    $PolicyEdgeTransportNode2IpAssignmentSpecsArray += [PSCustomObject]@{
        'ip_assignment_type' = "StaticIpv4"
        'management_port_subnets' = @($PolicyEdgeTransportNode2MgmtPortSubnetsArray)
        'default_gateway' = @($instanceObject.edgeCluster.nodes.node2.mgmtGateway)
    }

    $PolicyEdgeTransportNode2ManagementInterfaceObject = New-Object -type psobject
    $PolicyEdgeTransportNode2ManagementInterfaceObject | Add-Member -NotePropertyName 'network_id' -NotePropertyValue $mgmtPortGroupID2
    $PolicyEdgeTransportNode2ManagementInterfaceObject | Add-Member -NotePropertyName 'ip_assignment_specs' -NotePropertyValue @($PolicyEdgeTransportNode2IpAssignmentSpecsArray)

    $pnic1Object = New-Object -type psobject
    $pnic1Object | Add-Member -NotePropertyName 'device_name' -NotePropertyValue "fp-eth0"
    $pnic1Object | Add-Member -NotePropertyName 'uplink_name' -NotePropertyValue "uplink-1"
    $pnic1Object | Add-Member -NotePropertyName 'datapath_network_id' -NotePropertyValue $edgeTrunk01PortgroupId

    $pnic2Object = New-Object -type psobject
    $pnic2Object | Add-Member -NotePropertyName 'device_name' -NotePropertyValue "fp-eth1"
    $pnic2Object | Add-Member -NotePropertyName 'uplink_name' -NotePropertyValue "uplink-2"
    $pnic2Object | Add-Member -NotePropertyName 'datapath_network_id' -NotePropertyValue $edgeTrunk02PortgroupId

    $profilePaths = @()
    $profilePaths += [PSCustomObject]@{
        'key' = "UplinkHostSwitchProfile"
        'value' = "/infra/host-switch-profiles/$($instanceObject.edgeCluster.hostSwitchProfileId)"
    }

    $ipAssignmentSpecArray = @()

    $ipAssignmentSpecObject = New-Object -type psobject
    $ipAssignmentSpecObject | Add-Member -NotePropertyName 'ip_assignment_type' -NotePropertyValue $instanceObject.edgeCluster.tepMode
    If ($instanceObject.edgeCluster.tepMode -eq "StaticIpv4List")
    {
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'ip_list' -NotePropertyValue @($instanceObject.edgeCluster.nodes.node2.overlayIpAddress1,$instanceObject.edgeCluster.nodes.node2.overlayIpAddress2)
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'default_gateway' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.overlayGateway
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'subnet_mask' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.overlayMask

    }
    elseIf ($instanceObject.edgeCluster.tepMode -eq "StaticIpv4Pool")
    {
        $ipAssignmentSpecObject | Add-Member -NotePropertyName 'ip_pool' -NotePropertyValue "/infra/ip-pools/$($instanceObject.edgeCluster.ipPoolName)"
    }
    $ipAssignmentSpecArray += $ipAssignmentSpecObject

    $tunnelEndpointsObject = New-Object -type psobject
    $tunnelEndpointsObject | Add-Member -NotePropertyName 'ip_assignment_specs' -NotePropertyValue $ipAssignmentSpecArray
    $tunnelEndpointsObject | Add-Member -NotePropertyName 'vlan' -NotePropertyValue ($instanceObject.edgeCluster.edgeNodeTunnelEndpointVlan -as [int])

    $PolicyEdgeTransportNode2SwitchObject = New-Object -type psobject
    $PolicyEdgeTransportNode2SwitchObject | Add-Member -NotePropertyName 'pnics' -NotePropertyValue @($pnic1Object,$pnic2Object)
    $PolicyEdgeTransportNode2SwitchObject | Add-Member -NotePropertyName 'overlay_transport_zone_paths' -NotePropertyValue @($overlayTransportZonePath)
    $PolicyEdgeTransportNode2SwitchObject | Add-Member -NotePropertyName 'vlan_transport_zone_paths' -NotePropertyValue @("/infra/sites/default/enforcement-points/default/transport-zones/$($instanceObject.edgeCluster.vlanTransportZoneId)")
    $PolicyEdgeTransportNode2SwitchObject | Add-Member -NotePropertyName 'profile_paths' -NotePropertyValue @($profilePaths)
    $PolicyEdgeTransportNode2SwitchObject | Add-Member -NotePropertyName 'tunnel_endpoints' -NotePropertyValue @($tunnelEndpointsObject)
    $PolicyEdgeTransportNode2SwitchObject | Add-Member -NotePropertyName 'switch_name' -NotePropertyValue "nsxDefaultHostSwitch"

    $PolicyEdgeTransportNode2SwitchesArray = @()
    $PolicyEdgeTransportNode2SwitchesArray += $PolicyEdgeTransportNode2SwitchObject

    $PolicyEdgeTransportNode2SwitchSpecObject = New-Object -type psobject
    $PolicyEdgeTransportNode2SwitchSpecObject | Add-Member -NotePropertyName 'switches' -NotePropertyValue @($PolicyEdgeTransportNode2SwitchesArray)

    $edge2DeploymentConfig = New-Object -type psobject
    $edge2DeploymentConfig | Add-Member -NotePropertyName 'vc_id' -NotePropertyValue $vCenterId
    $edge2DeploymentConfig | Add-Member -NotePropertyName 'compute_id' -NotePropertyValue $computeId2
    $edge2DeploymentConfig | Add-Member -NotePropertyName 'storage_id' -NotePropertyValue $storageId2
    $edge2DeploymentConfig | Add-Member -NotePropertyName 'placement_type' -NotePropertyValue $instanceObject.edgeCluster.placementType

    If ($instanceObject.edgeCluster.hostGroupAffinity -eq "yes")
    {
        $edge2HostAffinityConfigObject = New-Object -Type psobject
        $edge2HostAffinityConfigObject | Add-Member -NotePropertyName 'host_group_name' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.hostGroupName
        $edge2DeploymentConfig | Add-Member -NotePropertyName 'edge_host_affinity_config' -NotePropertyValue $edge2HostAffinityConfigObject
    }

    $PolicyEdgeTransportNode2Object = New-Object -type psobject
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.hostname
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'credentials' -NotePropertyValue (New-Object -type psobject)
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'deployment_type' -NotePropertyValue "VIRTUAL_MACHINE"
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "PolicyEdgeTransportNode"
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'display_name' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.name
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'id' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.name
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'vm_deployment_config' -NotePropertyValue $edge2DeploymentConfig
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'management_interface' -NotePropertyValue $PolicyEdgeTransportNode2ManagementInterfaceObject
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'switch_spec' -NotePropertyValue $PolicyEdgeTransportNode2SwitchSpecObject
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'form_factor' -NotePropertyValue $instanceObject.edgeCluster.nodes.node2.formfactor.toUpper()
    $PolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'appliance_config' -NotePropertyValue $applianceConfigObject

    $ChildPolicyEdgeTransportNode2Object = New-Object -type psobject
    $ChildPolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'PolicyEdgeTransportNode' -NotePropertyValue $PolicyEdgeTransportNode2Object
    $ChildPolicyEdgeTransportNode2Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildPolicyEdgeTransportNode"

    $policyEdgeNodesArray = @()
    $policyEdgeNodesArray += [PSCustomObject]@{
        'id' = $instanceObject.edgeCluster.nodes.node1.name
        'edge_transport_node_path' = "/infra/sites/default/enforcement-points/default/edge-transport-nodes/$($instanceObject.edgeCluster.nodes.node1.name)"
    }
    $policyEdgeNodesArray += [PSCustomObject]@{
        'id' = $instanceObject.edgeCluster.nodes.node2.name
        'edge_transport_node_path' = "/infra/sites/default/enforcement-points/default/edge-transport-nodes/$($instanceObject.edgeCluster.nodes.node2.name)"
    }

    $policyEdgeClusterObject = New-Object -type psobject
    $policyEdgeClusterObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue $instanceObject.edgeCluster.name
    $policyEdgeClusterObject | Add-Member -NotePropertyName 'id' -NotePropertyValue $instanceObject.edgeCluster.name
    $policyEdgeClusterObject | Add-Member -NotePropertyName 'policy_edge_nodes' -NotePropertyValue $policyEdgeNodesArray
    $policyEdgeClusterObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "PolicyEdgeCluster"
    $policyEdgeClusterObject | Add-Member -NotePropertyName 'password_managed_by_vcf' -NotePropertyValue $true

    $ChildPolicyEdgeClusterObject = New-Object -type psobject
    $ChildPolicyEdgeClusterObject | Add-Member -NotePropertyName 'PolicyEdgeCluster' -NotePropertyValue $policyEdgeClusterObject
    $ChildPolicyEdgeClusterObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildPolicyEdgeCluster"

    $ChildResourceReferenceGrandchildrenArray = @()
    $ChildResourceReferenceGrandchildrenArray += $ChildPolicyEdgeTransportNode1Object
    $ChildResourceReferenceGrandchildrenArray += $ChildPolicyEdgeTransportNode2Object
    $ChildResourceReferenceGrandchildrenArray += $ChildPolicyEdgeClusterObject

    $ChildResourceReferenceChildrenObject = New-Object -type psobject
    $ChildResourceReferenceChildrenObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildResourceReference"
    $ChildResourceReferenceChildrenObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "default"
    $ChildResourceReferenceChildrenObject | Add-Member -NotePropertyName 'target_type' -NotePropertyValue "EnforcementPoint"
    $ChildResourceReferenceChildrenObject | Add-Member -NotePropertyName 'children' -NotePropertyValue $ChildResourceReferenceGrandchildrenArray

    $ChildResourceReferenceObject = New-Object -type psobject
    $ChildResourceReferenceObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildResourceReference"
    $ChildResourceReferenceObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "default"
    $ChildResourceReferenceObject | Add-Member -NotePropertyName 'target_type' -NotePropertyValue "Site"
    $ChildResourceReferenceObject | Add-Member -NotePropertyName 'children' -NotePropertyValue @($ChildResourceReferenceChildrenObject)
    # End ChildResource Reference Child

    # Start Tier0 Child
    $routeRedistributionTypesArray = @("TIER0_NAT","TIER0_STATIC","TIER0_CONNECTED","TIER0_DNS_FORWARDER_IP","TIER0_IPSEC_LOCAL_IP","TIER0_EVPN_TEP_IP","TIER1_CONNECTED","TIER1_STATIC","TIER1_NAT","TIER1_LB_VIP","TIER1_LB_SNAT","TIER1_DNS_FORWARDER_IP","TIER1_IPSEC_LOCAL_ENDPOINT","TGW_STATIC")
    $redistributionRulesArray = @()
    $redistributionRulesArray += [PSCustomObject]@{
        'route_redistribution_types' = $routeRedistributionTypesArray
        'destinations' = @("BGP")
    }
    $routeRedistributionConfigObject = New-Object -type psobject
    $routeRedistributionConfigObject | Add-Member -NotePropertyName "bgp_enabled" -NotePropertyValue $true
    $routeRedistributionConfigObject | Add-Member -NotePropertyName "redistribution_rules" -NotePropertyValue $redistributionRulesArray

    $bfdObject = New-Object -type psobject
    $bfdObject | Add-Member -NotePropertyName "enabled" -NotePropertyValue $false

    $BgpRoutingConfig1Object = New-Object -type psobject
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue "BgpNeighbor$($instanceObject.edgeCluster.bgp.peer1.id)"
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "id" -NotePropertyValue "BgpNeighbor$($instanceObject.edgeCluster.bgp.peer1.id)"
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "neighbor_address" -NotePropertyValue $instanceObject.edgeCluster.bgp.peer1.address
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "remote_as_num" -NotePropertyValue $instanceObject.edgeCluster.bgp.peer1.asn
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "bfd" -NotePropertyValue $bfdObject
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "BgpNeighborConfig"
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "password" -NotePropertyValue $instanceObject.edgeCluster.bgp.peer1.password
    $BgpRoutingConfig1Object | Add-Member -NotePropertyName "source_addresses" -NotePropertyValue @($instanceObject.edgeCluster.nodes.node1.uplink01IpAddress,$instanceObject.edgeCluster.nodes.node2.uplink01IpAddress)

    $BgpRoutingConfigChild1Object = New-Object -type psobject
    $BgpRoutingConfigChild1Object | Add-Member -NotePropertyName "BgpNeighborConfig" -NotePropertyValue $BgpRoutingConfig1Object
    $BgpRoutingConfigChild1Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildBgpNeighborConfig"

    $BgpRoutingConfig2Object = New-Object -type psobject
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue "BgpNeighbor$($instanceObject.edgeCluster.bgp.peer2.id)"
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "id" -NotePropertyValue "BgpNeighbor$($instanceObject.edgeCluster.bgp.peer2.id)"
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "neighbor_address" -NotePropertyValue $instanceObject.edgeCluster.bgp.peer2.address
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "remote_as_num" -NotePropertyValue $instanceObject.edgeCluster.bgp.peer2.asn
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "bfd" -NotePropertyValue $bfdObject
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "BgpNeighborConfig"
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "password" -NotePropertyValue $instanceObject.edgeCluster.bgp.peer2.password
    $BgpRoutingConfig2Object | Add-Member -NotePropertyName "source_addresses" -NotePropertyValue @($instanceObject.edgeCluster.nodes.node1.uplink02IpAddress,$instanceObject.edgeCluster.nodes.node2.uplink02IpAddress)

    $BgpRoutingConfigChild2Object = New-Object -type psobject
    $BgpRoutingConfigChild2Object | Add-Member -NotePropertyName "BgpNeighborConfig" -NotePropertyValue $BgpRoutingConfig2Object
    $BgpRoutingConfigChild2Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildBgpNeighborConfig"

    $BgpRoutingConfigChildrenArray = @()
    $BgpRoutingConfigChildrenArray += $BgpRoutingConfigChild1Object
    $BgpRoutingConfigChildrenArray += $BgpRoutingConfigChild2Object

    $BgpRoutingConfigObject = New-Object -type psobject
    $BgpRoutingConfigObject | Add-Member -NotePropertyName "id" -NotePropertyValue "bgp"
    $BgpRoutingConfigObject | Add-Member -NotePropertyName "local_as_num" -NotePropertyValue $instanceObject.edgeCluster.localAsnNumber
    $BgpRoutingConfigObject | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true
    $BgpRoutingConfigObject | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "BgpRoutingConfig"
    $BgpRoutingConfigObject | Add-Member -NotePropertyName "children" -NotePropertyValue $BgpRoutingConfigChildrenArray

    $ChildBgpRoutingConfigObject = New-Object -type psobject
    $ChildBgpRoutingConfigObject | Add-Member -NotePropertyName "BgpRoutingConfig" -NotePropertyValue $BgpRoutingConfigObject
    $ChildBgpRoutingConfigObject | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildBgpRoutingConfig"

    $Tier0Interface1SubnetsObject = New-Object -type psobject
    $Tier0Interface1SubnetsObject | Add-Member -NotePropertyName "ip_addresses" -NotePropertyValue @($instanceObject.edgeCluster.nodes.node1.uplink01IpAddress)
    $Tier0Interface1SubnetsObject | Add-Member -NotePropertyName "prefix_len" -NotePropertyValue ($instanceObject.edgeCluster.uplink01PrefixLength -as [INT])

    $Tier0Interface1Object = New-Object -type psobject
    $Tier0Interface1Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node1.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink01VlanId)"
    $Tier0Interface1Object | Add-Member -NotePropertyName "id" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node1.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink01VlanId)"
    $Tier0Interface1Object | Add-Member -NotePropertyName "subnets" -NotePropertyValue @($Tier0Interface1SubnetsObject)
    $Tier0Interface1Object | Add-Member -NotePropertyName "mtu" -NotePropertyValue ($instanceObject.edgeCluster.uplink01Mtu -as [int])
    $Tier0Interface1Object | Add-Member -NotePropertyName "edge_path" -NotePropertyValue "/infra/sites/default/enforcement-points/default/edge-clusters/$($instanceObject.edgeCluster.name)/edge-nodes/$($instanceObject.edgeCluster.nodes.node1.name)"
    $Tier0Interface1Object | Add-Member -NotePropertyName "segment_path" -NotePropertyValue "/infra/segments/vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node1.name)"
    $Tier0Interface1Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "Tier0Interface"
    $Tier0Interface1Object | Add-Member -NotePropertyName "type" -NotePropertyValue "EXTERNAL"

    $ChildTier0Interface1Object = New-Object -TypeName psobject
    $ChildTier0Interface1Object | Add-Member -NotePropertyName "Tier0Interface" -NotePropertyValue $Tier0Interface1Object
    $ChildTier0Interface1Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildTier0Interface"

    $Tier0Interface2SubnetsObject = New-Object -type psobject
    $Tier0Interface2SubnetsObject | Add-Member -NotePropertyName "ip_addresses" -NotePropertyValue  @($instanceObject.edgeCluster.nodes.node1.uplink02IpAddress)
    $Tier0Interface2SubnetsObject | Add-Member -NotePropertyName "prefix_len" -NotePropertyValue ($instanceObject.edgeCluster.uplink02PrefixLength -as [INT])

    $Tier0Interface2Object = New-Object -type psobject
    $Tier0Interface2Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node1.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink02VlanId)"
    $Tier0Interface2Object | Add-Member -NotePropertyName "id" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node1.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink02VlanId)"
    $Tier0Interface2Object | Add-Member -NotePropertyName "subnets" -NotePropertyValue @($Tier0Interface2SubnetsObject)
    $Tier0Interface2Object | Add-Member -NotePropertyName "mtu" -NotePropertyValue ($instanceObject.edgeCluster.uplink02Mtu -as [int])
    $Tier0Interface2Object | Add-Member -NotePropertyName "edge_path" -NotePropertyValue "/infra/sites/default/enforcement-points/default/edge-clusters/$($instanceObject.edgeCluster.name)/edge-nodes/$($instanceObject.edgeCluster.nodes.node1.name)"
    $Tier0Interface2Object | Add-Member -NotePropertyName "segment_path" -NotePropertyValue "/infra/segments/vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node1.name)"
    $Tier0Interface2Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "Tier0Interface"
    $Tier0Interface2Object | Add-Member -NotePropertyName "type" -NotePropertyValue "EXTERNAL"

    $ChildTier0Interface2Object = New-Object -TypeName psobject
    $ChildTier0Interface2Object | Add-Member -NotePropertyName "Tier0Interface" -NotePropertyValue $Tier0Interface2Object
    $ChildTier0Interface2Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildTier0Interface"

    $Tier0Interface3SubnetsObject = New-Object -type psobject
    $Tier0Interface3SubnetsObject | Add-Member -NotePropertyName "ip_addresses" -NotePropertyValue @($instanceObject.edgeCluster.nodes.node2.uplink01IpAddress)
    $Tier0Interface3SubnetsObject | Add-Member -NotePropertyName "prefix_len" -NotePropertyValue ($instanceObject.edgeCluster.uplink01PrefixLength -as [INT])

    $Tier0Interface3Object = New-Object -type psobject
    $Tier0Interface3Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node2.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink01VlanId)"
    $Tier0Interface3Object | Add-Member -NotePropertyName "id" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node2.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink01VlanId)"
    $Tier0Interface3Object | Add-Member -NotePropertyName "subnets" -NotePropertyValue @($Tier0Interface3SubnetsObject)
    $Tier0Interface3Object | Add-Member -NotePropertyName "mtu" -NotePropertyValue ($instanceObject.edgeCluster.uplink01Mtu -as [int])
    $Tier0Interface3Object | Add-Member -NotePropertyName "edge_path" -NotePropertyValue "/infra/sites/default/enforcement-points/default/edge-clusters/$($instanceObject.edgeCluster.name)/edge-nodes/$($instanceObject.edgeCluster.nodes.node2.name)"
    $Tier0Interface3Object | Add-Member -NotePropertyName "segment_path" -NotePropertyValue "/infra/segments/vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node2.name)"
    $Tier0Interface3Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "Tier0Interface"
    $Tier0Interface3Object | Add-Member -NotePropertyName "type" -NotePropertyValue "EXTERNAL"

    $ChildTier0Interface3Object = New-Object -TypeName psobject
    $ChildTier0Interface3Object | Add-Member -NotePropertyName "Tier0Interface" -NotePropertyValue $Tier0Interface3Object
    $ChildTier0Interface3Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildTier0Interface"

    $Tier0Interface4SubnetsObject = New-Object -type psobject
    $Tier0Interface4SubnetsObject | Add-Member -NotePropertyName "ip_addresses" -NotePropertyValue @($instanceObject.edgeCluster.nodes.node2.uplink02IpAddress)
    $Tier0Interface4SubnetsObject | Add-Member -NotePropertyName "prefix_len" -NotePropertyValue ($instanceObject.edgeCluster.uplink02PrefixLength -as [INT])

    $Tier0Interface4Object = New-Object -type psobject
    $Tier0Interface4Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node2.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink02VlanId)"
    $Tier0Interface4Object | Add-Member -NotePropertyName "id" -NotePropertyValue "$($instanceObject.edgeCluster.nodes.node2.name)-uplink01-interface-$($instanceObject.edgeCluster.uplink02VlanId)"
    $Tier0Interface4Object | Add-Member -NotePropertyName "subnets" -NotePropertyValue @($Tier0Interface4SubnetsObject)
    $Tier0Interface4Object | Add-Member -NotePropertyName "mtu" -NotePropertyValue  ($instanceObject.edgeCluster.uplink02Mtu -as [int])
    $Tier0Interface4Object | Add-Member -NotePropertyName "edge_path" -NotePropertyValue "/infra/sites/default/enforcement-points/default/edge-clusters/$($instanceObject.edgeCluster.name)/edge-nodes/$($instanceObject.edgeCluster.nodes.node2.name)"
    $Tier0Interface4Object | Add-Member -NotePropertyName "segment_path" -NotePropertyValue "/infra/segments/vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node2.name)"
    $Tier0Interface4Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "Tier0Interface"
    $Tier0Interface4Object | Add-Member -NotePropertyName "type" -NotePropertyValue "EXTERNAL"

    $ChildTier0Interface4Object = New-Object -TypeName psobject
    $ChildTier0Interface4Object | Add-Member -NotePropertyName "Tier0Interface" -NotePropertyValue $Tier0Interface4Object
    $ChildTier0Interface4Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildTier0Interface"

    $localeServicesChildrenArray = @()
    $localeServicesChildrenArray += $ChildBgpRoutingConfigObject
    $localeServicesChildrenArray += $ChildTier0Interface1Object
    $localeServicesChildrenArray += $ChildTier0Interface2Object
    $localeServicesChildrenArray += $ChildTier0Interface3Object
    $localeServicesChildrenArray += $ChildTier0Interface4Object

    $localeServicesObject = New-Object -type psobject
    $localeServicesObject | Add-Member -NotePropertyName "id" -NotePropertyValue $instanceObject.edgeCluster.localServicesID
    $localeServicesObject | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "LocaleServices"
    $localeServicesObject | Add-Member -NotePropertyName "edge_cluster_path" -NotePropertyValue "/infra/sites/default/enforcement-points/default/edge-clusters/$($instanceObject.edgeCluster.name)"
    $localeServicesObject | Add-Member -NotePropertyName "route_redistribution_config" -NotePropertyValue $routeRedistributionConfigObject
    $localeServicesObject | Add-Member -NotePropertyName "children" -NotePropertyValue $localeServicesChildrenArray

    $childLocaleServicesObject =  New-Object -type psobject
    $childLocaleServicesObject | Add-Member -NotePropertyName "LocaleServices" -NotePropertyValue $localeServicesObject
    $childLocaleServicesObject | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "ChildLocaleServices"

    $tier0Object = New-Object -type psobject
    $tier0Object | Add-Member -NotePropertyName "display_name" -NotePropertyValue $instanceObject.edgeCluster.t0DisplayName
    $tier0Object | Add-Member -NotePropertyName "id" -NotePropertyValue $instanceObject.edgeCluster.t0DisplayName 
    $tier0Object | Add-Member -NotePropertyName "ha_mode" -NotePropertyValue $instanceObject.edgeCluster.haMode 
    $tier0Object | Add-Member -NotePropertyName "resource_type" -NotePropertyValue "Tier0"
    $tier0Object | Add-Member -NotePropertyName "children" -NotePropertyValue @($childLocaleServicesObject)

    $childTier0Object = New-Object -type psobject
    $childTier0Object | Add-Member -NotePropertyName 'Tier0' -NotePropertyValue $tier0Object
    $childTier0Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildTier0"
    # End Tier Child

    # Start Segment Children
    $teaming1AdvancedConfigObject = New-Object -type psobject
    $teaming1AdvancedConfigObject | Add-Member -NotePropertyName 'uplink_teaming_policy_name' -NotePropertyValue "teaming-1"

    $teaming2AdvancedConfigObject = New-Object -type psobject
    $teaming2AdvancedConfigObject | Add-Member -NotePropertyName 'uplink_teaming_policy_name' -NotePropertyValue "teaming-2"

    $childSegment1SegmentObject = New-Object -type psobject
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'vlan_ids' -NotePropertyValue @($instanceObject.edgeCluster.uplink01VlanId)
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'transport_zone_path' -NotePropertyValue "/infra/sites/default/enforcement-points/default/transport-zones/$($instanceObject.edgeCluster.vlanTransportZoneId)"
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'path' -NotePropertyValue "/infra/segments/vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node1.name)"
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'advanced_config' -NotePropertyValue $teaming1AdvancedConfigObject
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "Segment"
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node1.name)"
    $childSegment1SegmentObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node1.name)"
    $childSegment1Object = New-Object -type psobject
    $childSegment1Object | Add-Member -NotePropertyName 'Segment' -NotePropertyValue $childSegment1SegmentObject
    $childSegment1Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildSegment"

    $childSegment2SegmentObject = New-Object -type psobject
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'vlan_ids' -NotePropertyValue @($instanceObject.edgeCluster.uplink02VlanId)
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'transport_zone_path' -NotePropertyValue "/infra/sites/default/enforcement-points/default/transport-zones/$($instanceObject.edgeCluster.vlanTransportZoneId)"
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'path' -NotePropertyValue "/infra/segments/vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node1.name)"
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'advanced_config' -NotePropertyValue $teaming2AdvancedConfigObject
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "Segment"
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node1.name)"
    $childSegment2SegmentObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node1.name)"
    $childSegment2Object = New-Object -type psobject
    $childSegment2Object | Add-Member -NotePropertyName 'Segment' -NotePropertyValue $childSegment2SegmentObject
    $childSegment2Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildSegment"

    $childSegment3SegmentObject = New-Object -type psobject
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'vlan_ids' -NotePropertyValue @($instanceObject.edgeCluster.uplink01VlanId)
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'transport_zone_path' -NotePropertyValue "/infra/sites/default/enforcement-points/default/transport-zones/$($instanceObject.edgeCluster.vlanTransportZoneId)"
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'path' -NotePropertyValue "/infra/segments/vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node2.name)"
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'advanced_config' -NotePropertyValue $teaming1AdvancedConfigObject
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "Segment"
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node2.name)"
    $childSegment3SegmentObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "vlan-segment-teaming-1-$($instanceObject.edgeCluster.nodes.node2.name)"
    $childSegment3Object = New-Object -type psobject
    $childSegment3Object | Add-Member -NotePropertyName 'Segment' -NotePropertyValue $childSegment3SegmentObject
    $childSegment3Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildSegment"

    $childSegment4SegmentObject = New-Object -type psobject
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'vlan_ids' -NotePropertyValue @($instanceObject.edgeCluster.uplink02VlanId)
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'transport_zone_path' -NotePropertyValue "/infra/sites/default/enforcement-points/default/transport-zones/$($instanceObject.edgeCluster.vlanTransportZoneId)"
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'path' -NotePropertyValue "/infra/segments/vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node2.name)"
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'advanced_config' -NotePropertyValue $teaming2AdvancedConfigObject
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "Segment"
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node2.name)"
    $childSegment4SegmentObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "vlan-segment-teaming-2-$($instanceObject.edgeCluster.nodes.node2.name)"
    $childSegment4Object = New-Object -type psobject
    $childSegment4Object | Add-Member -NotePropertyName 'Segment' -NotePropertyValue $childSegment4SegmentObject
    $childSegment4Object | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildSegment"

    $externalIpAddressBlockObject = New-Object -type psobject
    $externalIpAddressBlockObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue 'IpAddressBlock'
    $externalIpAddressBlockObject | Add-Member -NotePropertyName 'visibility' -NotePropertyValue 'EXTERNAL'
    $externalIpAddressBlockObject | Add-Member -NotePropertyName 'cidr' -NotePropertyValue $instanceObject.edgeCluster.externalIpBlocks
    $externalIpAddressBlockObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "External-ip-address-block-$($instanceObject.edgeCluster.externalIpBlocks)"
    $externalIpAddressBlockObject | Add-Member -NotePropertyName 'id' -NotePropertyValue (New-Guid).guid

    $externalChildIpAddressBlockObject = New-Object -type psobject
    $externalChildIpAddressBlockObject | Add-Member -NotePropertyName 'IpAddressBlock' -NotePropertyValue $externalIpAddressBlockObject
    $externalChildIpAddressBlockObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue 'ChildIpAddressBlock'

    $privateIpAddressBlockObject = New-Object -type psobject
    $privateIpAddressBlockObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue 'IpAddressBlock'
    $privateIpAddressBlockObject | Add-Member -NotePropertyName 'visibility' -NotePropertyValue 'PRIVATE'
    $privateIpAddressBlockObject | Add-Member -NotePropertyName 'cidr' -NotePropertyValue $instanceObject.edgeCluster.privateTgwIpBlocks
    $privateIpAddressBlockObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "Private-ip-address-block-$($instanceObject.edgeCluster.privateTgwIpBlocks)"
    $privateIpAddressBlockObject | Add-Member -NotePropertyName 'id' -NotePropertyValue (New-Guid).guid

    $privateChildIpAddressBlockObject = New-Object -type psobject
    $privateChildIpAddressBlockObject | Add-Member -NotePropertyName 'IpAddressBlock' -NotePropertyValue $privateIpAddressBlockObject
    $privateChildIpAddressBlockObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue 'ChildIpAddressBlock'
  
    $childrenArray += $ChildResourceReferenceObject
    $childrenArray += $childTier0Object
    $childrenArray += $childSegment1Object
    $childrenArray += $childSegment2Object
    $childrenArray += $childSegment3Object
    $childrenArray += $childSegment4Object
    $childrenArray += $externalChildIpAddressBlockObject
    $childrenArray += $privateChildIpAddressBlockObject

    # End Segment Children

    # Start Create External Connection
    $GatewayConnectionObject = New-Object -type psobject
    $GatewayConnectionObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "GatewayConnection"
    $GatewayConnectionObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "1b0a7021-abde-4b4f-9862-c18ce36b505c"
    $GatewayConnectionObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "Gateway-connection-$($instanceObject.edgeCluster.t0DisplayName)"
    $GatewayConnectionObject | Add-Member -NotePropertyName 'tier0_path' -NotePropertyValue "/infra/tier-0s/$($instanceObject.edgeCluster.t0DisplayName)"

    $ChildGatewayConnectionObject = New-Object -type psobject
    $ChildGatewayConnectionObject | Add-Member -NotePropertyName 'GatewayConnection' -NotePropertyValue $GatewayConnectionObject
    $ChildGatewayConnectionObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildGatewayConnection"
    $childrenArray += $ChildGatewayConnectionObject

    # End Ceate External Connection

    # Start ChildVpcConnectivityProfile & ChildTransitGateway

    If ($tier0Object.ha_mode -ne "ACTIVE_ACTIVE")
    {
        $snatValue = $true
    }
    else
    {
        $snatValue = $false
    }
    $natConfigObject = New-Object -type psobject
    $natConfigObject | Add-Member -NotePropertyName 'enable_default_snat' -NotePropertyValue $snatValue

    $serviceGatwayObject = New-Object -type psobject
    $serviceGatwayObject | Add-Member -NotePropertyName 'edge_cluster_paths' -NotePropertyValue @("/infra/sites/default/enforcement-points/default/edge-clusters/$($instanceObject.edgeCluster.name)")
    $serviceGatwayObject | Add-Member -NotePropertyName 'enable' -NotePropertyValue $true
    $serviceGatwayObject | Add-Member -NotePropertyName 'nat_config' -NotePropertyValue $natConfigObject

    
    If ($interactiveEnabled -eq "Y")
    {
        $vpcConnectivityProfileRevision = ((Get-NsxVpcConnectivityProfiles -nsxtUsername $nsxtManagerAdminUser -nsxtManagerFqdn $nsxtManagerFqdn -nsxtPassword $decodedNSXPassword) | Where-Object {$_.display_name -eq "Default VPC Connectivity Profile"})._revision
    }
    else {
        $vpcConnectivityProfileRevision = 0
    }
    $VpcConnectivityProfileObject = New-Object -type psobject
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'unique_id' -NotePropertyValue "8837db1b-4da3-4fa3-96bf-96cda11472d2"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_last_modified_user' -NotePropertyValue "Administrator"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_revision' -NotePropertyValue "$($vpcConnectivityProfileRevision)"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'owner_id' -NotePropertyValue "2527c603-904c-4acb-ad9c-5535ba0aa631"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_system_owned' -NotePropertyValue $false
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "VpcConnectivityProfile"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_protection' -NotePropertyValue "NOT_PROTECTED"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'realization_id' -NotePropertyValue "8837db1b-4da3-4fa3-96bf-96cda11472d2"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_last_modified_time' -NotePropertyValue 1742554717837
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'overridden' -NotePropertyValue $false
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'is_default' -NotePropertyValue $true
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "Default VPC Connectivity Profile"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'remote_path' -NotePropertyValue ""
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_create_user' -NotePropertyValue "system"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'service_gateway' -NotePropertyValue $serviceGatwayObject
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName '_create_time' -NotePropertyValue 1741799452828
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'path' -NotePropertyValue "/orgs/default/projects/default/vpc-connectivity-profiles/default"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'marked_for_delete' -NotePropertyValue $false
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'transit_gateway_path' -NotePropertyValue "/orgs/default/projects/default/transit-gateways/default"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'parent_path' -NotePropertyValue "/orgs/default/projects/default"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "default"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'relative_path' -NotePropertyValue "default"
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'external_ip_blocks' -NotePropertyValue @("/infra/ip-blocks/$($externalIpAddressBlockObject.id)")
    $VpcConnectivityProfileObject | Add-Member -NotePropertyName 'private_tgw_ip_blocks' -NotePropertyValue @("/infra/ip-blocks/$($privateIpAddressBlockObject.id)")

    $ChildVpcConnectivityProfileObject = New-Object -type psobject
    $ChildVpcConnectivityProfileObject | Add-Member -NotePropertyName 'VpcConnectivityProfile' -NotePropertyValue $VpcConnectivityProfileObject
    $ChildVpcConnectivityProfileObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildVpcConnectivityProfile"

    $TransitGatewayAttachmentObject = New-Object -type psobject
    $TransitGatewayAttachmentObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "TransitGatewayAttachment"
    $TransitGatewayAttachmentObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "af6f2717-dd15-467e-9ba9-ec6f27977dc0"
    $TransitGatewayAttachmentObject | Add-Member -NotePropertyName 'connection_path' -NotePropertyValue "/infra/gateway-connections/1b0a7021-abde-4b4f-9862-c18ce36b505c"

    $ChildTransitGatewayAttachmentObject = New-Object -type psobject
    $ChildTransitGatewayAttachmentObject | Add-Member -NotePropertyName 'TransitGatewayAttachment' -NotePropertyValue $TransitGatewayAttachmentObject
    $ChildTransitGatewayAttachmentObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildTransitGatewayAttachment"

    If ($interactiveEnabled -eq "Y")
    {
        $transitGatewayRevision = ((Get-NsxTransitGateways -nsxtUsername $nsxtManagerAdminUser -nsxtManagerFqdn $nsxtManagerFqdn -nsxtPassword $decodedNSXPassword) | Where-Object {$_.display_name -eq "Default Transit Gateway"})._revision
    }
    else {
        $transitGatewayRevision = 0
    }

    $TransitGatewayObject = New-Object -type psobject
    $TransitGatewayObject | Add-Member -NotePropertyName 'unique_id' -NotePropertyValue "e518bda4-a011-448b-b5e8-99f2746546ea"
    $TransitGatewayObject | Add-Member -NotePropertyName '_last_modified_user' -NotePropertyValue "admin"
    $TransitGatewayObject | Add-Member -NotePropertyName '_revision' -NotePropertyValue "$($transitGatewayRevision)"
    $TransitGatewayObject | Add-Member -NotePropertyName 'owner_id' -NotePropertyValue "2527c603-904c-4acb-ad9c-5535ba0aa631"
    $TransitGatewayObject | Add-Member -NotePropertyName '_system_owned' -NotePropertyValue $false
    $TransitGatewayObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "TransitGateway"
    $TransitGatewayObject | Add-Member -NotePropertyName '_protection' -NotePropertyValue "NOT_PROTECTED"
    $TransitGatewayObject | Add-Member -NotePropertyName 'realization_id' -NotePropertyValue "e518bda4-a011-448b-b5e8-99f2746546ea"
    $TransitGatewayObject | Add-Member -NotePropertyName '_last_modified_time' -NotePropertyValue 1742575290271
    $TransitGatewayObject | Add-Member -NotePropertyName 'overridden' -NotePropertyValue $false
    $TransitGatewayObject | Add-Member -NotePropertyName 'is_default' -NotePropertyValue $true
    $TransitGatewayObject | Add-Member -NotePropertyName 'display_name' -NotePropertyValue "Default Transit Gateway"
    $TransitGatewayObject | Add-Member -NotePropertyName 'remote_path' -NotePropertyValue ""
    $TransitGatewayObject | Add-Member -NotePropertyName 'transit_subnets' -NotePropertyValue @($instanceObject.edgeCluster.transitSubnet)
    $TransitGatewayObject | Add-Member -NotePropertyName '_create_user' -NotePropertyValue "system"
    $TransitGatewayObject | Add-Member -NotePropertyName '_create_time' -NotePropertyValue 1741799452768
    $TransitGatewayObject | Add-Member -NotePropertyName 'path' -NotePropertyValue "/orgs/default/projects/default/transit-gateways/default"
    $TransitGatewayObject | Add-Member -NotePropertyName 'marked_for_delete' -NotePropertyValue $false
    $TransitGatewayObject | Add-Member -NotePropertyName 'parent_path' -NotePropertyValue "/orgs/default/projects/default"
    $TransitGatewayObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "default"
    $TransitGatewayObject | Add-Member -NotePropertyName 'relative_path' -NotePropertyValue "default"
    $TransitGatewayObject | Add-Member -NotePropertyName 'children' -NotePropertyValue @($ChildTransitGatewayAttachmentObject)

    $ChildTransitGatewayObject = New-Object -type psobject
    $ChildTransitGatewayObject | Add-Member -NotePropertyName 'TransitGateway' -NotePropertyValue $TransitGatewayObject
    $ChildTransitGatewayObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildTransitGateway"

    $ChildResourceReferenceObject2 = New-Object -type psobject
    $ChildResourceReferenceObject2 | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "ChildResourceReference"
    $ChildResourceReferenceObject2 | Add-Member -NotePropertyName 'id' -NotePropertyValue "default"
    $ChildResourceReferenceObject2 | Add-Member -NotePropertyName 'target_type' -NotePropertyValue "Project"
    $ChildResourceReferenceObject2 | Add-Member -NotePropertyName 'children' -NotePropertyValue @($ChildVpcConnectivityProfileObject,$ChildTransitGatewayObject)

    $singleApiChildrenArray = @()
    $singleApiChildrenArray += [PSCustomObject]@{
        'resource_type' = "ChildResourceReference"
        'id' = "default"
        'target_type' = "Infra"
        'children' = $childrenArray
    }
    $singleApiChildrenArray += [PSCustomObject]@{
        'resource_type' = "ChildResourceReference"
        'id' = "default"
        'target_type' = "Org"
        'children' = @($ChildResourceReferenceObject2)
    }

    $singleApiObject = New-Object -type psobject
    $singleApiObject | Add-Member -NotePropertyName 'resource_type' -NotePropertyValue "OrgRoot"
    $singleApiObject | Add-Member -NotePropertyName 'children' -NotePropertyValue $singleApiChildrenArray
    LogMessage -Type INFO -Message "Exporting the Edge Deployment JSON to edgeDeploymentSpec-$($instanceObject.edgeCluster.name).json"
    ConvertTo-Json $singleApiObject -depth 20 | Out-File "edgeDeploymentSpec-$($instanceObject.edgeCluster.name).json"
}

#Day N Aria JSON Files
Function New-DayNOpsAndAutomationJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$sharedInstanceObject
    )

    $vcfOperationsManagementSpecObject = @()
    $vcfOperationsManagementSpecObject += [pscustomobject]@{
        'hostname' = $sharedInstanceObject.fleetManager.fqdn
        'rootUserPassword' = $sharedInstanceObject.fleetManager.rootUserPassword
        'adminUserPassword' = $sharedInstanceObject.fleetManager.adminUserPassword
        'useExistingDeployment' = $false
    }
    
    $vcfOpsNodesObject = @()
    If ($sharedInstanceObject.operations.fleetManagementDeploymentModel -eq "Standard")
    {
        $vcfOpsNodesObject += [pscustomobject]@{
            'hostname' = $sharedInstanceObject.operations.nodeAFqdn
            'type' = 'master'
            'rootUserPassword' = $sharedInstanceObject.operations.rootUserPassword
        }
    }
    elseif ($sharedInstanceObject.operations.fleetManagementDeploymentModel -eq "Cluster")
    {
        $vcfOpsNodesObject += [pscustomobject]@{
            'hostname' = $sharedInstanceObject.operations.nodeAFqdn
            'type' = 'master'
            'rootUserPassword' = $sharedInstanceObject.operations.rootUserPassword
        }
        $vcfOpsNodesObject += [pscustomobject]@{
            'hostname' = $sharedInstanceObject.operations.nodeBFqdn
            'type' = 'replica'
            'rootUserPassword' = $sharedInstanceObject.operations.rootUserPassword
        }
        $vcfOpsNodesObject += [pscustomobject]@{
            'hostname' = $sharedInstanceObject.operations.nodeCFqdn
            'type' = 'data'
            'rootUserPassword' = $sharedInstanceObject.operations.rootUserPassword
        }
    }
    
    $vcfOperationsSpecObject = @()
    $vcfOperationsSpecObject += [pscustomobject]@{
        'nodes' = $vcfOpsNodesObject
        'adminUserPassword' = $sharedInstanceObject.operations.adminUserPassword
        'applianceSize' = $sharedInstanceObject.operations.applianceSize
        'useExistingDeployment' = $false
        'loadBalancerFqdn' = $sharedInstanceObject.operations.vipFqdn
    }
    
    $vcfOperationsCloudProxySpecObject = @()
    $vcfOperationsCloudProxySpecObject += [pscustomobject]@{
        'hostname' = $sharedInstanceObject.operations.opsCollectorFqdn
        'rootUserPassword' = $sharedInstanceObject.operations.opsCollectorRootUserPassword
        'applianceSize' = $sharedInstanceObject.operations.collectorApplianceSize
        'useExistingDeployment' = $false
    }
    
    #vcfAutomationSpecObject
    $ipPoolObject = @()
    $ipPoolObject += $sharedInstanceObject.automation.nodeAIpAddress
    $ipPoolObject += $sharedInstanceObject.automation.nodeBIpAddress
    If ($sharedInstanceObject.automation.fleetManagementDeploymentModel -eq "Cluster")
    {
        $ipPoolObject += $sharedInstanceObject.automation.nodeCIpAddress
        $ipPoolObject += $sharedInstanceObject.automation.extraNodeIpAddress    
    }
    $vcfAutomationSpecObjectObject = @()
    $vcfAutomationSpecObjectObject += [pscustomobject]@{
        'hostname' = $sharedInstanceObject.automation.vipFqdn   
        'adminUserPassword' = $sharedInstanceObject.automation.adminUserPassword
        'nodePrefix' = $sharedInstanceObject.automation.vcfaNodePrefix
        'useExistingDeployment' = $false
        'ipPool' = $ipPoolObject
        'internalClusterCidr' = $sharedInstanceObject.automation.internalClusterCidr
    }
    
    $localRegionNetworkObject = @()
    $localRegionNetworkObject += [pscustomobject]@{
        'networkName' = $sharedInstanceObject.operations.collectorMgmtPortgroup
        'subnetMask' = $sharedInstanceObject.operations.collectorMgmtSubnetMask
        'gateway' = $sharedInstanceObject.operations.collectorMgmtGw
    }

    $xRegionNetworkObject = @()
    $xRegionNetworkObject += [pscustomobject]@{
        'networkName' = $sharedInstanceObject.operations.fltMgmtPortgroup
        'subnetMask' = $sharedInstanceObject.operations.fltMgmtSubnetMask
        'gateway' = $sharedInstanceObject.operations.fltMgmtGw
    }
    
    $vcfMangementComponentsInfrastructureSpecObject = @()
    $vcfMangementComponentsInfrastructureSpecObject += [pscustomobject]@{
        'localRegionNetwork' = ($localRegionNetworkObject | Select-Object -Skip 0)
        'xRegionNetwork' = ($xRegionNetworkObject | Select-Object -Skip 0)
    }
    
    $dayNOpsAndAutomationSpecObject = New-Object -TypeName psobject
    $dayNOpsAndAutomationSpecObject | Add-Member -notepropertyname 'vcfOperationsFleetManagementSpec' -notepropertyvalue ($vcfOperationsManagementSpecObject | Select-Object -Skip 0)
    $dayNOpsAndAutomationSpecObject | Add-Member -notepropertyname 'vcfOperationsSpec' -notepropertyvalue ($vcfOperationsSpecObject | Select-Object -Skip 0)
    $dayNOpsAndAutomationSpecObject | Add-Member -notepropertyname 'vcfOperationsCollectorSpec' -notepropertyvalue ($vcfOperationsCloudProxySpecObject | Select-Object -Skip 0)
    $dayNOpsAndAutomationSpecObject | Add-Member -notepropertyname 'vcfAutomationSpec' -notepropertyvalue ($vcfAutomationSpecObjectObject | Select-Object -Skip 0)
    $dayNOpsAndAutomationSpecObject | Add-Member -notepropertyname 'vcfMangementComponentsInfrastructureSpec' -notepropertyvalue ($vcfMangementComponentsInfrastructureSpecObject | Select-Object -Skip 0)
    LogMessage -Type INFO -Message "Exporting the VCF Operations and Automation Post Bringup JSON to opsAutomation-dayNDeploymentSpec.json"
    ConvertTo-Json $dayNOpsAndAutomationSpecObject -depth 12 | Out-File -Encoding UTF8 -FilePath "opsAutomation-dayNDeploymentSpec.json"
}

Function createBasicAuthHeader {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password))) # Create Basic Authentication Encoded Credentials
    $headers = @{"Accept" = "application/json" }
    $headers.Add("Authorization", "Basic $base64AuthInfo")
    $headers.Add("Content-Type", "application/json")
    $headers
}

Function Request-FleetManagerToken {
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password
    )

    

    Try {
        $uri = "https://$fqdn/lcmversion"
        if ($PSEdition -eq 'Core') {
            $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -SkipCertificateCheck -UseBasicParsing # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        } else {
            $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -UseBasicParsing
        }
    } Catch {
        Write-Error $_.Exception.Message
    }
    Return $fmToken
}

Function Get-FleetManagerLockerPassword 
{
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password
    )

    $fmHeaders = createBasicAuthHeader $username $password
    Try 
    {
        $uri = "https://$fqdn/lcm/locker/api/v2/passwords?size=100"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $fmHeaders
        $response.passwords
    } Catch {
        Write-Error $_.Exception.Message
    }
}

Function Get-FleetManagerLockerCertificate {
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password
    )
    $fmHeaders = createBasicAuthHeader $username $password
    Try 
    {
        $uri = "https://$fqdn/lcm/locker/api/v2/certificates"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $fmHeaders
        $response.certificates
    } Catch {
        Write-Error $_.Exception.Message
    }
}

Function New-DayNIdbJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$sharedInstanceObject
    )

    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve locker information from Fleet Manager? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "Fleet Manager FQDN: " -skipnewline
            $fleetManagerFqdn = Read-Host
            LogMessage -type INFO -message "Fleet Manager Administrator: " -skipnewline
            $fleetManagerAdminUser = Read-Host
            LogMessage -type INFO -message "Fleet Manager Administrator password: " -skipnewline
            $fleetManagerPassword = Read-Host -AsSecureString
            $decodedFmPassword = New-DecodedPassword -securePassword $fleetManagerPassword
            $uri = "https://$fleetManagerFqdn/lcmversion"
            $fmHeaders = createBasicAuthHeader $fleetManagerAdminUser $decodedFmPassword
            if ($PSEdition -eq 'Core') {
                $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -SkipCertificateCheck -UseBasicParsing # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
            } else {
                $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -UseBasicParsing
            }
            If (!($fmResponse))
            {
                LogMessage -type ERROR -message "Failed to connect to successfully read information from $fleetManagerFqdn. Please check details and try again"
            }
        } Until ($fmResponse)
    }

    
    If ($interactiveEnabled -eq "Y")
    {
        $vcLockerPasswordEntry = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -like "*$($sharedInstanceObject.idb.vCenter)*"})
        $vcLockerPasswordUsername = $vcLockerPasswordEntry.userName
        $vcLockerPasswordId = $vcLockerPasswordEntry.vmid
        $idblockerCertId = (Get-FleetManagerLockerCertificate -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.idb.certAlias}).vmid
        $idblockerPasswordVmid = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.idb.systemUserPasswordAlias}).vmid
    }
    else
    {
        $vcLockerPasswordUsername = '<-- REPLACE WITH VC-LOCKER-PASSWORD-USERNAME -->'
        $vcLockerPasswordId = '<-- REPLACE WITH VC-LOCKER-PASSWORD-ID -->'
        $idblockerCertId = '<-- REPLACE WITH FLT-IDB-LOCKER-CERT-ID -->'
        $idblockerPasswordVmid = '<-- REPLACE WITH IDB-LOCKER-PASSWORD-ID -->'
    }

    $infraStructurePropertiesObject = New-Object -type psobject
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'dataCenterVmid' -NotePropertyValue 'DEFAULT_DC'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'regionName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'zoneName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vCenterName' -NotePropertyValue $sharedInstanceObject.idb.vCenter
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vCenterHost' -NotePropertyValue $sharedInstanceObject.idb.vCenter
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcUsername' -NotePropertyValue $vcLockerPasswordUsername
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcPassword' -NotePropertyValue "locker:password:$($vcLockerPasswordId):VCF-$($sharedInstanceObject.idb.vCenter)-vcPassword"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'acceptEULA' -NotePropertyValue "false"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'enableTelemetry' -NotePropertyValue "true"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'defaultPassword' -NotePropertyValue ""
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:$($idblockerCertId)"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'cluster' -NotePropertyValue $sharedInstanceObject.idb.cluster
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'storage' -NotePropertyValue $sharedInstanceObject.idb.datastore
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'folderName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'resourcePool' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'diskMode' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'network' -NotePropertyValue $sharedInstanceObject.idb.portgroup
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'masterVidmEnabled' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vmwareSSOEnabled' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'dns' -NotePropertyValue $sharedInstanceObject.idb.dnsServers
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'domain' -NotePropertyValue $sharedInstanceObject.idb.domainName
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'gateway' -NotePropertyValue $sharedInstanceObject.idb.gateway
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'netmask' -NotePropertyValue $sharedInstanceObject.idb.mask
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'searchpath' -NotePropertyValue $sharedInstanceObject.idb.searchpath
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'timeSyncMode' -NotePropertyValue $sharedInstanceObject.idb.timeSyncMode
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ntp' -NotePropertyValue $sharedInstanceObject.idb.ntpServers
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'isDhcp' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcfProperties' -NotePropertyValue '{\"vcfEnabled\":true,\"sddcManagerDetails\":[]}'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_selectedProducts' -NotePropertyValue ('[{\"id\":\"vidb\",\"type\":\"new\",\"selected\":true,\"sizes\":{\"'+$sharedInstanceObject.version+'\":[\"small\"]},\"selectedVersion\":\"'+$sharedInstanceObject.version+'\",\"selectedDeploymentType\":\"small\",\"selectedAuthenticationType\":\"\",\"tenantId\":\"Standalone vRASSC\",\"description\":\"VIDB_DESCRIPTION_TRANSLATION_KEY\",\"detailsHref\":\"https://docs.vmware.com/en/.../index.html\",\"errorMessage\":null,\"productVersions\":[{\"version\":\"'+$sharedInstanceObject.version+'\",\"deploymentType\":[\"small\"],\"productDeploymentMetaData\":{\"sizingURL\":null,\"productInfo\":\"Identity Broker - '+$sharedInstanceObject.version+'\",\"deploymentType\":[\"Small\"],\"deploymentItems\":{\"Node Count\":[\"3\"]},\"additionalInfo\":[\"*Small - Three node will be deployed\"],\"disasterRecovery\":null}}],\"disasterRecoveryEnabled\":\"false\"}]')
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_isRedeploy' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_isResume' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_leverageProximity' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '__isInstallerRequest' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ipv6Gateway' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ipv6Netmask' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv4' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv6' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv4AndIpv6' -NotePropertyValue ''
    $infraStructureObject = New-Object -type psobject
    $infraStructureObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $infraStructurePropertiesObject

    $productsNodesPropertiesObject = New-Object -type psobject
    $productsNodesPropertiesObject | Add-Member -NotePropertyName 'vmNamePrefix' -NotePropertyValue $sharedInstanceObject.idb.nodePrefix
    $productsNodesPropertiesObject | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue "$($sharedInstanceObject.idb.nodeAIpAddress)-$($sharedInstanceObject.idb.extraNodeIpAddress)"
    $productsNodesPropertiesObject | Add-Member -NotePropertyName 'internalClusterCidr' -NotePropertyValue $sharedInstanceObject.idb.internalClusterCidr
    $productsNodesPropertiesObject | Add-Member -NotePropertyName 'primaryVip' -NotePropertyValue $sharedInstanceObject.idb.vipAddress
    $productsNodesPropertiesObject | Add-Member -NotePropertyName 'additionalVips' -NotePropertyValue ''

    $productNodesObject = New-Object -type psobject
    $productNodesObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vidb-primary'
    $productNodesObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesPropertiesObject

    $productNodesArray = @($productNodesObject)

    $productsPropertiesObject = New-Object -type psobject
    $productsPropertiesObject | Add-Member -NotePropertyName 'authenticationType' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:$($idblockerCertId)"
    $productsPropertiesObject | Add-Member -NotePropertyName 'productPassword' -NotePropertyValue "locker:password:$($idblockerPasswordVmid)"
    $productsPropertiesObject | Add-Member -NotePropertyName 'productHostName' -NotePropertyValue $sharedInstanceObject.idb.vipFqdn
    $productsPropertiesObject | Add-Member -NotePropertyName 'deployOption' -NotePropertyValue 'small'

    $clusterVIPObject = New-Object -type psobject
    $clusterVIPObject | Add-Member -NotePropertyName 'clusterVips' -NotePropertyValue @()
    
    $productsObject = New-Object -type psobject
    $productsObject | Add-Member -NotePropertyName 'tenant' -NotePropertyValue 'default'
    $productsObject | Add-Member -NotePropertyName 'version' -NotePropertyValue $sharedInstanceObject.version
    $productsObject | Add-Member -NotePropertyName 'id' -NotePropertyValue 'vidb'
    $productsObject | Add-Member -NotePropertyName 'fleetEnabled' -NotePropertyValue $true
    $productsObject | Add-Member -NotePropertyName 'nodes' -NotePropertyValue $productNodesArray
    $productsObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsPropertiesObject
    $productsObject | Add-Member -NotePropertyName 'references' -NotePropertyValue @()
    $productsObject | Add-Member -NotePropertyName 'clusterVIP' -NotePropertyValue $clusterVIPObject
    
    $idbJsonObject = New-Object -type psobject
    $idbJsonObject | Add-Member -NotePropertyName 'infrastructure' -NotePropertyValue $infraStructureObject
    $idbJsonObject | Add-Member -NotePropertyName 'products' -NotePropertyValue @($productsObject)
    $idbJsonObject | Add-Member -NotePropertyName 'metaData' -NotePropertyValue (New-Object -type psobject)
    $idbJsonObject | Add-Member -NotePropertyName 'requestId' -NotePropertyValue $null
    $idbJsonObject | Add-Member -NotePropertyName 'fleet' -NotePropertyValue $true

    LogMessage -Type INFO -Message "Exporting the IDB Deployment JSON to idbDeploymentSpec-$(($sharedInstanceObject.idb.vipFqdn).split(".")[0]).json"
    ConvertTo-Json $idbJsonObject -depth 20 | Out-File "idbDeploymentSpec-$(($sharedInstanceObject.idb.vipFqdn).split(".")[0]).json"
}

Function New-DayNLogsJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$sharedInstanceObject
    )

    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve locker information from Fleet Manager? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "Fleet Manager FQDN: " -skipnewline
            $fleetManagerFqdn = Read-Host
            LogMessage -type INFO -message "Fleet Manager Administrator: " -skipnewline
            $fleetManagerAdminUser = Read-Host
            LogMessage -type INFO -message "Fleet Manager Administrator password: " -skipnewline
            $fleetManagerPassword = Read-Host -AsSecureString
            $decodedFmPassword = New-DecodedPassword -securePassword $fleetManagerPassword
            $uri = "https://$fleetManagerFqdn/lcmversion"
            $fmHeaders = createBasicAuthHeader $fleetManagerAdminUser $decodedFmPassword
            if ($PSEdition -eq 'Core') {
                $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -SkipCertificateCheck -UseBasicParsing # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
            } else {
                $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -UseBasicParsing
            }
            If (!($fmResponse))
            {
                LogMessage -type ERROR -message "Failed to connect to successfully read information from $fleetManagerFqdn. Please check details and try again"
            }
        } Until ($fmResponse)
    }

    
    If ($interactiveEnabled -eq "Y")
    {
        $vcLockerPasswordEntry = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -like "*$($sharedInstanceObject.logs.vCenter)*"})
        $vcLockerPasswordUsername = $vcLockerPasswordEntry.userName
        $vcLockerPasswordId = $vcLockerPasswordEntry.vmid
        $logslockerCertId = (Get-FleetManagerLockerCertificate -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.logs.certAlias}).vmid
        $logslockerAdminPasswordVmid = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.logs.systemUserPasswordAlias}).vmid
        $logslockerRootPasswordVmid = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.logs.rootUserPasswordAlias}).vmid
    }
    else
    {
        $vcLockerPasswordUsername = '<-- REPLACE WITH VC-LOCKER-PASSWORD-USERNAME -->'
        $vcLockerPasswordId = '<-- REPLACE WITH VC-LOCKER-PASSWORD-ID -->'
        $logslockerCertId = '<-- REPLACE WITH FLT-LOGS-LOCKER-CERT-ID -->'
        $logslockerAdminPasswordVmid = '<-- REPLACE WITH LOGS-ADMIN-LOCKER-PASSWORD-ID -->'
        $logslockerRootPasswordVmid = '<-- REPLACE WITH LOGS-ROOT-LOCKER-PASSWORD-ID -->'
    }

    $infraStructurePropertiesObject = New-Object -type psobject
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'dataCenterVmid' -NotePropertyValue 'DEFAULT_DC'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'regionName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'zoneName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vCenterName' -NotePropertyValue $sharedInstanceObject.logs.vCenter
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vCenterHost' -NotePropertyValue $sharedInstanceObject.logs.vCenter
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcUsername' -NotePropertyValue $vcLockerPasswordUsername
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcPassword' -NotePropertyValue "locker:password:$($vcLockerPasswordId):VCF-$($sharedInstanceObject.logs.vCenter)-vcPassword"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'acceptEULA' -NotePropertyValue "false"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'enableTelemetry' -NotePropertyValue "true"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'defaultPassword' -NotePropertyValue ""
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:$($logslockerCertId)"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'cluster' -NotePropertyValue $sharedInstanceObject.logs.cluster
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'storage' -NotePropertyValue $sharedInstanceObject.logs.datastore
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'folderName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'resourcePool' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'diskMode' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'network' -NotePropertyValue $sharedInstanceObject.logs.portgroup
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'masterVidmEnabled' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vmwareSSOEnabled' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'dns' -NotePropertyValue $sharedInstanceObject.logs.dnsServers
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'domain' -NotePropertyValue $sharedInstanceObject.logs.domainName
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'gateway' -NotePropertyValue $sharedInstanceObject.logs.gateway
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'netmask' -NotePropertyValue $sharedInstanceObject.logs.mask
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'searchpath' -NotePropertyValue $sharedInstanceObject.logs.searchpath
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'timeSyncMode' -NotePropertyValue $sharedInstanceObject.logs.timeSyncMode
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ntp' -NotePropertyValue $sharedInstanceObject.logs.ntpServers
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'isDhcp' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcfProperties' -NotePropertyValue '{\"vcfEnabled\":true,\"sddcManagerDetails\":[]}'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_selectedProducts' -NotePropertyValue ('[{\"id\":\"vrli\",\"type\":\"new\",\"selected\":true,\"sizes\":{\"'+$sharedInstanceObject.version+'\":[\"standard\",\"cluster\"]},\"selectedVersion\":\"'+$sharedInstanceObject.version+'\",\"selectedDeploymentType\":\"' + $sharedInstanceObject.logs.deploymentType.toLower() + '\",\"selectedAuthenticationType\":\"\",\"tenantId\":\"Standalone vRASSC\",\"description\":\"Operations-logs delivers heterogeneous and highly scalable log management with intuitive, actionable dashboards, sophisticated analytics and broad third-party extensibility, providing deep operational visibility and faster troubleshooting.\",\"detailsHref\":\"https://docs.vmware.com/en/VMware-Aria-Operations-for-Logs/index.html\",\"errorMessage\":null,\"productVersions\":[{\"version\":\"'+$sharedInstanceObject.version+'\",\"deploymentType\":[\"standard\",\"cluster\"],\"productDeploymentMetaData\":{\"sizingURL\":null,\"productInfo\":\"Operations-logs - '+$sharedInstanceObject.version+'\",\"deploymentType\":[\"Standalone\",\"Cluster\"],\"deploymentItems\":{\"Virtual Machines\":[\"10,000\",\"30,000\"],\"Node Count\":[\"1\",\"3\"],\"Log Ingest Rate Per Day In Gbs\":[\"30\",\"75\"],\"Events Per Second\":[\"2,000\",\"5,000\"]},\"additionalInfo\":[\"*Standalone - Master node provisioned by default\",\"*Cluster - Master and two worker nodes provisioned by default\",\"#Refer to Operations-logs Installation Guide\"],\"disasterRecovery\":null}}],\"disasterRecoveryEnabled\":\"false\"}]')
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_isRedeploy' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_isResume' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_leverageProximity' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '__isInstallerRequest' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ipv6Gateway' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ipv6Netmask' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv4' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv6' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv4AndIpv6' -NotePropertyValue ''
    $infraStructureObject = New-Object -type psobject
    $infraStructureObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $infraStructurePropertiesObject

    $productsNodesNodeAPropertiesObject = New-Object -type psobject
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.logs.nodeAFqdn).split(".")[0]
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.logs.nodeAFqdn
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.logs.nodeAIpAddress
    
    If ($sharedInstanceObject.logs.deploymentType -eq "Cluster")
    {
        $productsNodesNodeBPropertiesObject = New-Object -type psobject
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.logs.nodeBFqdn).split(".")[0]
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.logs.nodeBFqdn
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.logs.nodeBIpAddress
    
        $productsNodesNodeCPropertiesObject = New-Object -type psobject
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.logs.nodeCFqdn).split(".")[0]
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.logs.nodeCFqdn
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.logs.nodeCIpAddress
    }

    Foreach ($nodeObject in "productsNodesNodeAPropertiesObject","productsNodesNodeBPropertiesObject","productsNodesNodeCPropertiesObject")
    {
        $object = (Get-Variable -name $nodeObject -errorAction SilentlyContinue).value
        If ($object)
        {
            $object | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue ""
            $object | Add-Member -NotePropertyName 'additionalVips' -NotePropertyValue ""
            $object | Add-Member -NotePropertyName 'installationType' -NotePropertyValue "new"
            $object | Add-Member -NotePropertyName 'gateway' -NotePropertyValue $sharedInstanceObject.logs.gateway
            $object | Add-Member -NotePropertyName 'domain' -NotePropertyValue $sharedInstanceObject.logs.domainName
            $object | Add-Member -NotePropertyName 'searchpath' -NotePropertyValue $sharedInstanceObject.logs.searchpath
            $object | Add-Member -NotePropertyName 'dns' -NotePropertyValue $sharedInstanceObject.logs.dnsServers
            $object | Add-Member -NotePropertyName 'netmask' -NotePropertyValue $sharedInstanceObject.logs.mask
            $object | Add-Member -NotePropertyName 'rootPassword' -NotePropertyValue "locker:$($logslockerRootPasswordVmid):$($sharedInstanceObject.logs.vipFqdn.Split(".")[0])"
            $object | Add-Member -NotePropertyName 'vrliAdminUser' -NotePropertyValue ""
            $object | Add-Member -NotePropertyName 'vrliAdminEmail' -NotePropertyValue ""
            $object | Add-Member -NotePropertyName 'vCenterHost' -NotePropertyValue $sharedInstanceObject.logs.vCenter
            $object | Add-Member -NotePropertyName 'cluster' -NotePropertyValue $sharedInstanceObject.logs.cluster
            $object | Add-Member -NotePropertyName 'resourcePool' -NotePropertyValue ''
            $object | Add-Member -NotePropertyName 'folderName' -NotePropertyValue ''
            $object | Add-Member -NotePropertyName 'network' -NotePropertyValue $sharedInstanceObject.logs.portgroup
            $object | Add-Member -NotePropertyName 'storage' -NotePropertyValue $sharedInstanceObject.logs.datastore
            $object | Add-Member -NotePropertyName 'diskMode' -NotePropertyValue 'thin'
            $object | Add-Member -NotePropertyName 'contentLibraryItemId' -NotePropertyValue ''
            $object | Add-Member -NotePropertyName 'vCenterName' -NotePropertyValue $sharedInstanceObject.logs.vCenter
            $object | Add-Member -NotePropertyName 'vcUsername' -NotePropertyValue $vcLockerPasswordUsername
            $object | Add-Member -NotePropertyName 'vcPassword' -NotePropertyValue "locker:password:$($vcLockerPasswordId):VCF-$($sharedInstanceObject.logs.vCenter)-vcPassword"
        }        
    }
    
    $productNodeAObject = New-Object -type psobject
    $productNodeAObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrli-master'
    $productNodeAObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesNodeAPropertiesObject
    
    $productNodesArray = @($productNodeAObject)
    If ($sharedInstanceObject.logs.deploymentType -eq "Cluster")
    {
        $productNodeBObject = New-Object -type psobject
        $productNodeBObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrli-worker'
        $productNodeBObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesNodeBPropertiesObject
        $productNodesArray += $productNodeBObject

        $productNodeCObject = New-Object -type psobject
        $productNodeCObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrli-worker'
        $productNodeCObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesNodeCPropertiesObject
        $productNodesArray += $productNodeCObject
    }

    $productsPropertiesObject = New-Object -type psobject
    $productsPropertiesObject | Add-Member -NotePropertyName 'authenticationType' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'ntp' -NotePropertyValue $sharedInstanceObject.logs.ntpServers
    $productsPropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:$($logslockerCertId)"
    $productsPropertiesObject | Add-Member -NotePropertyName 'contentLibraryItemId' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'productPassword' -NotePropertyValue "locker:password:$($logslockerAdminPasswordVmid)"
    $productsPropertiesObject | Add-Member -NotePropertyName 'adminEmail' -NotePropertyValue $sharedInstanceObject.logs.adminEmail
    If ($sharedInstanceObject.logs.fipsMode -eq 'Selected')
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'fipsMode' -NotePropertyValue 'true'
    }
    else
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'fipsMode' -NotePropertyValue 'false'
    }
    
    $productsPropertiesObject | Add-Member -NotePropertyName 'licenseRef' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'nodeSize' -NotePropertyValue $sharedInstanceObject.logs.nodeSize.tolower()
    $productsPropertiesObject | Add-Member -NotePropertyName 'configureClusterVIP' -NotePropertyValue 'true'
    If ($sharedInstanceObject.logs.configureAffinity -eq 'Selected')
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'affinityRule' -NotePropertyValue $true
    }
    else
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'affinityRule' -NotePropertyValue $false
    }
    $productsPropertiesObject | Add-Member -NotePropertyName 'isUpgradeVmCompatibility' -NotePropertyValue $true
    $productsPropertiesObject | Add-Member -NotePropertyName 'vrliAlwaysUseEnglish' -NotePropertyValue $true
    $productsPropertiesObject | Add-Member -NotePropertyName 'masterVidmEnabled' -NotePropertyValue 'false'
    $productsPropertiesObject | Add-Member -NotePropertyName 'configureAffinitySeparateAll' -NotePropertyValue 'true'
    $productsPropertiesObject | Add-Member -NotePropertyName 'timeSyncMode' -NotePropertyValue $sharedInstanceObject.logs.timeSyncMode
    $productsPropertiesObject | Add-Member -NotePropertyName 'monitorWithvROps' -NotePropertyValue 'false'
    $productsPropertiesObject | Add-Member -NotePropertyName 'vmwareSSOEnabled' -NotePropertyValue 'false'

    $clusterVIPObject = New-Object -type psobject
    $clusterVIPObject | Add-Member -NotePropertyName 'clusterVips' -NotePropertyValue @()
    
    $productsObject = New-Object -type psobject
    $productsObject | Add-Member -NotePropertyName 'tenant' -NotePropertyValue 'default'
    $productsObject | Add-Member -NotePropertyName 'version' -NotePropertyValue $sharedInstanceObject.version
    $productsObject | Add-Member -NotePropertyName 'id' -NotePropertyValue 'vrli'
    $productsObject | Add-Member -NotePropertyName 'clusterVIP' -NotePropertyValue $clusterVIPObject
    $productsObject | Add-Member -NotePropertyName 'fleetEnabled' -NotePropertyValue $true
    $productsObject | Add-Member -NotePropertyName 'nodes' -NotePropertyValue $productNodesArray
    $productsObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsPropertiesObject
    $productsObject | Add-Member -NotePropertyName 'references' -NotePropertyValue @()
    
    $logsJsonObject = New-Object -type psobject
    $logsJsonObject | Add-Member -NotePropertyName 'infrastructure' -NotePropertyValue $infraStructureObject
    $logsJsonObject | Add-Member -NotePropertyName 'products' -NotePropertyValue @($productsObject)
    $logsJsonObject | Add-Member -NotePropertyName 'metaData' -NotePropertyValue (New-Object -type psobject)
    $logsJsonObject | Add-Member -NotePropertyName 'requestId' -NotePropertyValue $null
    $logsJsonObject | Add-Member -NotePropertyName 'fleet' -NotePropertyValue $true

    LogMessage -Type INFO -Message "Exporting the Logs Deployment JSON to opsLogsDeploymentSpec-$(($sharedInstanceObject.logs.vipFqdn).split(".")[0]).json"
    ConvertTo-Json $logsJsonObject -depth 20 | Out-File "opsLogsDeploymentSpec-$(($sharedInstanceObject.logs.vipFqdn).split(".")[0]).json"
}

Function New-DayNNetworksJsonFile
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$sharedInstanceObject
    )

    Do
    {
        LogMessage -Type QUESTION -Message "Do you wish to interactively retrieve locker information from Fleet Manager? (Y/N): " -skipnewline
        $interactiveEnabled = Read-Host    
    } Until ($interactiveEnabled -in "Y","N")
    $interactiveEnabled = $interactiveEnabled -replace "`t|`n|`r", ""
    If ($interactiveEnabled -eq "Y")
    {
        Do
        {
            LogMessage -type INFO -message "Fleet Manager FQDN: " -skipnewline
            $fleetManagerFqdn = Read-Host
            LogMessage -type INFO -message "Fleet Manager Administrator: " -skipnewline
            $fleetManagerAdminUser = Read-Host
            LogMessage -type INFO -message "Fleet Manager Administrator password: " -skipnewline
            $fleetManagerPassword = Read-Host -AsSecureString
            $decodedFmPassword = New-DecodedPassword -securePassword $fleetManagerPassword
            $uri = "https://$fleetManagerFqdn/lcmversion"
            $fmHeaders = createBasicAuthHeader $fleetManagerAdminUser $decodedFmPassword
            if ($PSEdition -eq 'Core') {
                $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -SkipCertificateCheck -UseBasicParsing # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
            } else {
                $fmResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $fmHeaders -UseBasicParsing
            }
            If (!($fmResponse))
            {
                LogMessage -type ERROR -message "Failed to connect to successfully read information from $fleetManagerFqdn. Please check details and try again"
            }
        } Until ($fmResponse)
    }

    
    If ($interactiveEnabled -eq "Y")
    {
        $vcLockerPasswordEntry = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -like "*$($sharedInstanceObject.networks.vCenter)*"})
        $vcLockerPasswordUsername = $vcLockerPasswordEntry.userName
        $vcLockerPasswordId = $vcLockerPasswordEntry.vmid
        $networkslockerCertId = (Get-FleetManagerLockerCertificate -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.networks.certAlias}).vmid
        $networkslockerAdminPasswordVmid = (Get-FleetManagerLockerPassword -fqdn $fleetManagerFqdn -username $fleetManagerAdminUser -password $decodedFmPassword | Where-Object {$_.alias -eq $sharedInstanceObject.networks.systemUserPasswordAlias}).vmid
    }
    else
    {
        $vcLockerPasswordUsername = '<-- REPLACE WITH VC-LOCKER-PASSWORD-USERNAME -->'
        $vcLockerPasswordId = '<-- REPLACE WITH VC-LOCKER-PASSWORD-ID -->'
        $networkslockerCertId = '<-- REPLACE WITH FLT-NETWORKS-LOCKER-CERT-ID -->'
        $networkslockerAdminPasswordVmid = '<-- REPLACE WITH NETWORKS-ADMIN-LOCKER-PASSWORD-ID -->'
    }

    $infraStructurePropertiesObject = New-Object -type psobject
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'dataCenterVmid' -NotePropertyValue 'DEFAULT_DC'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'regionName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'zoneName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vCenterName' -NotePropertyValue $sharedInstanceObject.networks.vCenter
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vCenterHost' -NotePropertyValue $sharedInstanceObject.networks.vCenter
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcUsername' -NotePropertyValue $vcLockerPasswordUsername
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcPassword' -NotePropertyValue "locker:password:$($vcLockerPasswordId):VCF-$($sharedInstanceObject.networks.vCenter)-vcPassword"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'acceptEULA' -NotePropertyValue "false"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'enableTelemetry' -NotePropertyValue "true"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'defaultPassword' -NotePropertyValue ""
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:$($networkslockerCertId)"
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'cluster' -NotePropertyValue $sharedInstanceObject.networks.cluster
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'storage' -NotePropertyValue $sharedInstanceObject.networks.datastore
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'folderName' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'resourcePool' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'diskMode' -NotePropertyValue 'thin'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'network' -NotePropertyValue $sharedInstanceObject.networks.nodePortgroup
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'masterVidmEnabled' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vmwareSSOEnabled' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'dns' -NotePropertyValue $sharedInstanceObject.networks.dnsServers
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'domain' -NotePropertyValue $sharedInstanceObject.networks.domainName
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'gateway' -NotePropertyValue $sharedInstanceObject.networks.nodeGateway
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'netmask' -NotePropertyValue $sharedInstanceObject.networks.nodeNetmask
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'searchpath' -NotePropertyValue $sharedInstanceObject.networks.searchpath
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'timeSyncMode' -NotePropertyValue $sharedInstanceObject.networks.timeSyncMode
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ntp' -NotePropertyValue $sharedInstanceObject.networks.ntpServers
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'isDhcp' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'vcfProperties' -NotePropertyValue '{\"vcfEnabled\":true,\"sddcManagerDetails\":[]}'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_selectedProducts' -NotePropertyValue ('[{\"id\":\"vrni\",\"type\":\"new\",\"selected\":true,\"sizes\":{\"'+$sharedInstanceObject.version+'\":[\"standard\",\"cluster\"]},\"selectedVersion\":\"'+$sharedInstanceObject.version+'\",\"selectedDeploymentType\":\"' + $sharedInstanceObject.networks.deploymentType.toLower() + '\",\"selectedAuthenticationType\":\"\",\"tenantId\":\"Standalone vRASSC\",\"description\":\"Operations-networks integrates with NSX to deliver intelligent operations for software defined networking. The key features and use cases of Operations-networks include 360 degree visibility and end-to-end troubleshooting across converged infrastructure and physical and virtual networks, performance optimization and topology mapping, physical switch vendor integration, advanced monitoring to ensure health and availability of NSX, rich traffic analytics, change tracking, planning and monitoring of micro-segmentation, and best practice compliance checking.\",\"detailsHref\":\"https://docs.vmware.com/en/VMware-Aria-Operations-for-Networks/index.html\",\"errorMessage\":null,\"productVersions\":[{\"version\":\"'+$sharedInstanceObject.version+'\",\"deploymentType\":[\"standard\",\"cluster\"],\"productDeploymentMetaData\":{\"sizingURL\":null,\"productInfo\":\"Operations-networks - '+$sharedInstanceObject.version+'\",\"deploymentType\":[\"Standalone\",\"Cluster\"],\"deploymentItems\":{\"Number of managed VMs (without flows)\":[\"5,000\",\"30,000\"],\"Platform\":[\"1\",\"3\"],\"Node Count\":[\"2\",\"4\"],\"Flows\":[\"10,000,000\",\"60,000,000\"],\"Collector\":[\"1\",\"1\"],\"Number of managed VMs (with flows)\":[\"3,000\",\"18,000\"]},\"additionalInfo\":[\"*Cluster - Operations-networks clustering is a scale-out solution of platform VM\",\"# Refer to Operations-networks Installation Guide\"],\"disasterRecovery\":null}}],\"disasterRecoveryEnabled\":\"false\"}]')
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_isRedeploy' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_isResume' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '_leverageProximity' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName '__isInstallerRequest' -NotePropertyValue 'false'
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ipv6Gateway' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'ipv6Netmask' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv4' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv6' -NotePropertyValue ''
    $infraStructurePropertiesObject | Add-Member -NotePropertyName 'useIpv4AndIpv6' -NotePropertyValue ''
    $infraStructureObject = New-Object -type psobject
    $infraStructureObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $infraStructurePropertiesObject

    $productsNodesNodeAPropertiesObject = New-Object -type psobject
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.networks.nodeAFqdn).split(".")[0]
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'vrniNodeSize' -NotePropertyValue $sharedInstanceObject.networks.nodeASize.tolower()
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.networks.nodeAFqdn
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.networks.nodeAIpAddress
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue ""
    $productsNodesNodeAPropertiesObject | Add-Member -NotePropertyName 'additionalVips' -NotePropertyValue ""
    
    If ($sharedInstanceObject.networks.deploymentType -eq "Cluster")
    {
        $productsNodesNodeBPropertiesObject = New-Object -type psobject
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.networks.nodeBFqdn).split(".")[0]
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'vrniNodeSize' -NotePropertyValue $sharedInstanceObject.networks.nodeBSize.tolower()
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.networks.nodeBFqdn
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.networks.nodeBIpAddress
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue ""
        $productsNodesNodeBPropertiesObject | Add-Member -NotePropertyName 'additionalVips' -NotePropertyValue ""
    
    
        $productsNodesNodeCPropertiesObject = New-Object -type psobject
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.networks.nodeCFqdn).split(".")[0]
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'vrniNodeSize' -NotePropertyValue $sharedInstanceObject.networks.nodeCSize.tolower()
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.networks.nodeCFqdn
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.networks.nodeCIpAddress
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue ""
        $productsNodesNodeCPropertiesObject | Add-Member -NotePropertyName 'additionalVips' -NotePropertyValue ""
    }

    $productsNodesCollectorPropertiesObject = New-Object -type psobject
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'vmName' -NotePropertyValue ($sharedInstanceObject.networks.proxyFqdn).split(".")[0]
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'vrniNodeSize' -NotePropertyValue $sharedInstanceObject.networks.proxySize.tolower()
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'hostName' -NotePropertyValue $sharedInstanceObject.networks.proxyFqdn
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'ip' -NotePropertyValue $sharedInstanceObject.networks.proxyIpAddress
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'ipPool' -NotePropertyValue ""
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'additionalVips' -NotePropertyValue ""
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'network' -NotePropertyValue $sharedInstanceObject.networks.proxyPortgroup
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'gateway' -NotePropertyValue $sharedInstanceObject.networks.proxyGateway
    $productsNodesCollectorPropertiesObject | Add-Member -NotePropertyName 'netmask' -NotePropertyValue $sharedInstanceObject.networks.proxyNetmask
    
    $productNodeAObject = New-Object -type psobject
    $productNodeAObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrni-platform'
    $productNodeAObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesNodeAPropertiesObject
    
    $productNodesArray = @($productNodeAObject)
    If ($sharedInstanceObject.networks.deploymentType -eq "Cluster")
    {
        $productNodeBObject = New-Object -type psobject
        $productNodeBObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrni-platform'
        $productNodeBObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesNodeBPropertiesObject
        $productNodesArray += $productNodeBObject

        $productNodeCObject = New-Object -type psobject
        $productNodeCObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrni-platform'
        $productNodeCObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesNodeCPropertiesObject
        $productNodesArray += $productNodeCObject
    }

    $productCollectorObject = New-Object -type psobject
    $productCollectorObject | Add-Member -NotePropertyName 'type' -NotePropertyValue 'vrni-collector'
    $productCollectorObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsNodesCollectorPropertiesObject
    $productCollectorArray += $productCollectorObject

    $productsPropertiesObject = New-Object -type psobject
    $productsPropertiesObject | Add-Member -NotePropertyName 'authenticationType' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:$($networkslockerCertId)"
    $productsPropertiesObject | Add-Member -NotePropertyName 'contentLibraryItemId:platform' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'contentLibraryItemId:proxy' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'productPassword' -NotePropertyValue "locker:password:$($networkslockerAdminPasswordVmid)"
    $productsPropertiesObject | Add-Member -NotePropertyName 'licenseRef' -NotePropertyValue ''
    $productsPropertiesObject | Add-Member -NotePropertyName 'ntp' -NotePropertyValue $sharedInstanceObject.networks.ntpServers
    If ($sharedInstanceObject.networks.configureAffinity -eq 'Selected')
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'affinityRule' -NotePropertyValue $true
    }
    else
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'affinityRule' -NotePropertyValue $false
    }
    $productsPropertiesObject | Add-Member -NotePropertyName 'configureAffinitySeparateAll' -NotePropertyValue 'true'
    $productsPropertiesObject | Add-Member -NotePropertyName 'masterVidmEnabled' -NotePropertyValue 'false'
    If ($sharedInstanceObject.networks.fipsMode -eq 'Selected')
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'fipsMode' -NotePropertyValue 'true'
    }
    else
    {
        $productsPropertiesObject | Add-Member -NotePropertyName 'fipsMode' -NotePropertyValue 'false'
    }    
    $productsPropertiesObject | Add-Member -NotePropertyName 'monitorWithvROps' -NotePropertyValue 'false'

    $clusterVIPObject = New-Object -type psobject
    $clusterVIPObject | Add-Member -NotePropertyName 'clusterVips' -NotePropertyValue @()
    
    $productsObject = New-Object -type psobject
    $productsObject | Add-Member -NotePropertyName 'tenant' -NotePropertyValue 'default'
    $productsObject | Add-Member -NotePropertyName 'version' -NotePropertyValue $sharedInstanceObject.version
    $productsObject | Add-Member -NotePropertyName 'id' -NotePropertyValue 'vrni'
    $productsObject | Add-Member -NotePropertyName 'clusterVIP' -NotePropertyValue $clusterVIPObject
    $productsObject | Add-Member -NotePropertyName 'fleetEnabled' -NotePropertyValue $true
    $productsObject | Add-Member -NotePropertyName 'nodes' -NotePropertyValue $productNodesArray
    $productsObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $productsPropertiesObject
    $productsObject | Add-Member -NotePropertyName 'references' -NotePropertyValue @()
    
    $networksJsonObject = New-Object -type psobject
    $networksJsonObject | Add-Member -NotePropertyName 'infrastructure' -NotePropertyValue $infraStructureObject
    $networksJsonObject | Add-Member -NotePropertyName 'products' -NotePropertyValue @($productsObject)
    $networksJsonObject | Add-Member -NotePropertyName 'metaData' -NotePropertyValue (New-Object -type psobject)
    $networksJsonObject | Add-Member -NotePropertyName 'requestId' -NotePropertyValue $null
    $networksJsonObject | Add-Member -NotePropertyName 'fleet' -NotePropertyValue $true

    LogMessage -Type INFO -Message "Exporting the Logs Deployment JSON to opsNetworksDeploymentSpec-$(($sharedInstanceObject.networks.nodeAFqdn).split(".")[0]).json"
    ConvertTo-Json $networksJsonObject -depth 20 | Out-File "opsNetworksDeploymentSpec-$(($sharedInstanceObject.networks.nodeAFqdn).split(".")[0]).json"
}