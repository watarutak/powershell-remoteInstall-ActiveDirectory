# Arg0 = Computer name or Computer list
# Arg1 = Installer name
# Arg2 = Silent install option


# Process arguments

# Check if first argument is file or just a computer name
if (Test-Path $Args[0]) {
    $computers = (Get-Content $Args[0]) -as [string[]]
} else {
    $computers = @($Args[0]);
}

$InstallerName = $Args[1]
if ($Args[2]) {
	$SilentOption = $Args[2]
} else {
	$SilentOption = ""
}


# Define values

# Result file
$Date = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = ".\result_" + $Date + ".txt"
New-Item $LogFile -ItemType File

#$DownloadExecName = "exec.txt"
$DownloadExecName = "installation.txt"
#$LocalExecName = "exec.cmd"
$LocalExecName = "installation.ps1"
$UncTargetShare = "\MIS_Temp$\"
$LocalTargetBase = "C:\MIS_Temp\"

$DownloadBase = "http://sspwebsrv01v.stripes.int/SoftwareDistribution/"
$DownloadUrlBat = $DownloadBase +  $DownloadExecName
$DownloadUrlInstaller = $DownloadBase +  $InstallerName

$LocalExecPath = $LocalTargetBase + $LocalExecName
$LocalInstallerPath = $LocalTargetBase + $InstallerName

# Define result code
set -name JOB_RESULT_COMPLETED -value "Completed" -option constant

set -name JOB_RESULT_RUNNING -value "Running" -option constant
set -name JOB_RESULT_SUSPENDING -value "Suspending" -option constant
set -name JOB_RESULT_STOPPING -value "Stopping" -option constant

set -name JOB_RESULT_NOTSTARTED -value "NotStarted" -option constant
set -name JOB_RESULT_FAILED -value "Failed" -option constant
set -name JOB_RESULT_STOPPED -value "Stopped" -option constant
set -name JOB_RESULT_BLOCKED -value "Blocked" -option constant
set -name JOB_RESULT_SUSPENDED -value "Suspended" -option constant
set -name JOB_RESULT_DISCONNECTED -value "Disconnected" -option constant

$ary_success = @($JOB_RESULT_COMPLETED)
$ary_running = @($JOB_RESULT_RUNNING, $JOB_RESULT_SUSPENDING, $JOB_STOPPING)
$ary_fail = @($JOB_RESULT_NOTSTARTED, $JOB_RESULT_FAILED, $JOB_RESULT_STOPPED, $JOB_RESULT_BLOCKED, $JOB_RESULT_SUSPENDED, $JOB_RESULT_DISCONNECTED)

# Define session state
set -name SESSION_STATE_OPENED -value "Opened" -option constant
set -name SESSION_STATE_DISCONNECTED -value "Disconnected" -option constant
set -name SESSION_STATE_CLOSED -value "Closed" -option constant
set -name SESSION_STATE_BROKEN -value "Broken" -option constant




# Array for results
$result = @()
$checkCount = 0
# Repeat installation for listed computers
for ($i = 0; $i -lt $computers.Length; $i++) {

    # Initialize
    $ret = @{}
    $ret.add("computer",$computers[$i])

    $UncTargetBase = "\\" + $ret["computer"] + $UncTargetShare
    $UncBatPath = $UncTargetBase + $LocalExecName
    $UncInstallerPath = $UncTargetBase + $InstallerName

    try {
        # Open new session for target computer
        $s = New-PSSession -ComputerName $ret["computer"] -errorAction stop

        # Delete if same name file exists in remote target folder
        if (Test-Path $UncBatPath) {
            Invoke-Command -Session $s -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath -errorAction stop
        }
        if (Test-Path $UncInstallerPath) {
            Invoke-Command -Session $s -Scriptblock{del $args[0]} -ArgumentList $LocalInstallerPath -errorAction stop
        }

        # Download installer and exec script to target computer
        Invoke-WebRequest -Uri $DownloadUrlBat -OutFile $UncBatPath -errorAction stop
        Invoke-WebRequest -Uri $DownloadUrlInstaller -OutFile $UncInstallerPath -errorAction stop

        # Kick downloaded installer as a Background job
        $job = Invoke-Command -Session $s -Scriptblock{ Start-Job -Scriptblock{C:\MIS_Temp\$args[0] $args[1]}} -ArgumentList $InstallerName,$SilentOption -errorAction stop
        $ret.add("job", $job)
        $ret.add("result",$job.State)
        $checkCount++
    }
    catch
    {
        # Add error handling
        $ret.add("result",$JOB_RESULT_FAILED)
        # Delete used files
        if (Test-Path $UncBatPath) {
            Invoke-Command -ComputerName $ret["computer"] -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
        }
        if (Test-Path $UncInstallerPath) {
            Invoke-Command -ComputerName $ret["computer"] -Scriptblock{del $args[0]} -ArgumentList $LocalInstaller
        }

        # Export result to text file
        $text = $ret["computer"] + " : " + "Failed`n"
        $text | Out-File $LogFile -Append
    }
    finally
    {
        if ($s.State -eq $SESSION_STATE_OPENED){
            $s = Disconnect-PSSession -Session $s
        }
        $ret.add("session",$s)
        $result += $ret
    }
}

# Check result loop
while ($checkCount -gt 0) {

    # Check results
    $checkCount = $result.Length
    $fileTexts = @()
    try {
        for ($i = 0;$i -lt $result.Length; $i++) {
           
            if ($ary_running -contains $result[$i]["result"]) {
                # Check result
                Connect-PSSession -Session $result[$i]["session"]  # Reconnect to target computer
                $result[$i]["result"] = Invoke-Command -Session $result[$i]["session"] -ScriptBlock{ Get-Job -Id $args[0]} -ArgumentList $result[$i]["job"].Id

                if (($ary_success -contains $result[$i]["result"].State) -Or ($ary_fail -contains $result[$i]["result"].State)) {
                    # [TODO] If return is 1, check appication name and version are in list of installed programs 
                   
                    # Delete finished files
                    Invoke-Command -Session $result[$i]["session"] -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
                    Invoke-Command -Session $result[$i]["session"] -Scriptblock{del $args[0]} -ArgumentList $LocalInstallerPath

                    # Remove PSSession
                    Remove-PSSession -Session $result[$i]["session"]

                    $checkCount--
                } else {
                    # Disconnect-PSSession
                    Disconnect-PSSession -Session $result[$i]["session"]
                }


            } else {  # Target computers which finished checking result
                # Delete session if it exists
                if (($result[$i]["session"].State -eq $SESSION_STATE_OPENED) -Or ($result[$i]["session"].State -eq $SESSION_STATE_DISCONNECTED)) {
                    Remove-PSSession -Session $result[$i]["session"]
                }
                $checkCount--
            }

            # Create message for result file
            $resultText = $result[$i]["computer"] + " : " + $result[$i]["result"].State + "`n"
            $fileTexts += $resultText

        }
    }
    catch
    {
        Write-Host "error exits"
    }
 
    # Re-create result file after once delete
    Remove-Item $LogFile
    New-Item $LogFile -ItemType File
    for ($i=0; $i -lt $fileTexts.Length; $i++) {
        $fileTexts[$i] | Out-File $LogFile -Append
    }

    # Wait 5 min to next check loop
    Start-Sleep -Seconds 10
}