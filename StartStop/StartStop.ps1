#
# Start and stop VMs in Azure using a schedule set on the tags of the VM
#


# Parse the time range and do a check. Copied from the https://automys.com/library/asset/scheduled-virtual-machine-shutdown-startup-microsoft-azure runbook
function CheckScheduleEntry ([string]$TimeRange)
{    
    # Initialize variables
    $rangeStart, $rangeEnd, $parsedDay = $null
    $currentTime = (Get-Date).ToUniversalTime()
    $midnight = $currentTime.AddDays(1).Date            

    try
    {
        # Parse as range if contains '->'
        if($TimeRange -like "*->*")
        {
            $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
            if($timeRangeComponents.Count -eq 2)
            {
                $rangeStart = Get-Date $timeRangeComponents[0]
                $rangeEnd = Get-Date $timeRangeComponents[1]
    
                # Check for crossing midnight
                if($rangeStart -gt $rangeEnd)
                {
                    # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                    if($currentTime -ge $rangeStart -and $currentTime -lt $midnight)
                    {
                        $rangeEnd = $rangeEnd.AddDays(1)
                    }
                    # Otherwise interpret start time as yesterday and end time as today   
                    else
                    {
                        $rangeStart = $rangeStart.AddDays(-1)
                    }
                }
            }
            else
            {
                Write-Output "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'" 
            }
        }
        # Otherwise attempt to parse as a full day entry, e.g. 'Monday' or 'December 25' 
        else
        {
            # If specified as day of week, check if today
            if([System.DayOfWeek].GetEnumValues() -contains $TimeRange)
            {
                if($TimeRange -eq (Get-Date).DayOfWeek)
                {
                    $parsedDay = Get-Date "00:00"
                }
                else
                {
                    # Skip detected day of week that isn't today
                }
            }
            # Otherwise attempt to parse as a date, e.g. 'December 25'
            else
            {
                $parsedDay = Get-Date $TimeRange
            }
        
            if($parsedDay -ne $null)
            {
                $rangeStart = $parsedDay # Defaults to midnight
                $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59) # End of the same day
            }
        }
    }
    catch
    {
        # Record any errors and return false by default
        Write-Output "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). Check the syntax of entry, e.g. '<StartTime> -> <EndTime>', or days/dates like 'Sunday' and 'December 25'"   
        return $false
    }
    
    # Check if current time falls within range
    if($currentTime -ge $rangeStart -and $currentTime -le $rangeEnd)
    {
        return $true
    }
    else
    {
        return $false
    }
    
} 

try{
    # Fetch all the VMs
    $vms =  az resource list --resource-type "Microsoft.Compute/virtualMachines" -o json | ConvertFrom-Json

    Write-Output "$($vms.Count) virtual machines found, processing entries..."

    # Iterate through them
    foreach ($vm in $vms)
    {
        # Write-Host "Checking VM with ID "  $vm.id  " and tag "  $vm.tags 

        $schedule = $null
    
        # Retrieve the tag which has the schedule
        if($vm.tags -and $vm.tags.AutoShutdownSchedule)
        {          
            $schedule = $vm.tags.AutoShutdownSchedule
            Write-Output "Found VM called $($vm.name) with schedule tag with value: $schedule"
        }

        # If we do not have a tag, continue with the rest
        if($schedule -eq $null)
        {
            Write-Output "Skipping $($vm.Name) as it had no tag."
            continue
        }

        # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
        $timeRangeList = @($schedule -split "," | foreach {$_.Trim()})
        
        # Check each range against the current time to see if any schedule is matched
        $scheduleMatched = $false
        $matchedSchedule = $null
        foreach($entry in $timeRangeList)
        {
            if((CheckScheduleEntry -TimeRange $entry) -eq $true)
            {
                $scheduleMatched = $true
                $matchedSchedule = $entry
                break
            }
        }

        # Fetch current state
        $currentState = (az vm show -d --ids $vm.id -o json | ConvertFrom-Json).powerState

        Write-Host "Current state of $($vm.Name) is $($currentState) and the schedule is matched is $($scheduleMatched)"

        if($scheduleMatched -and $currentState -notmatch "running")
        {
            # this machine needs to be on
            Write-Host "Turning on VM $($vm.Name)"
            az vm start --ids $vm.id --no-wait
        }
        elseif (!$scheduleMatched -and $currentState -notmatch "deallocated"){
            # this machine needs to be turned off
            Write-Host "Deallocating the VM $($vm.Name) to reduce cost"
            az vm deallocate --ids $vm.id --no-wait
        }
        else {
            Write-Host "No action needed for VM $($vm.Name) as it is in the correct state"
        }
    
    }
}
catch
{
    $errorMessage = $_.Exception.Message
    throw "Unexpected exception: $errorMessage"
}