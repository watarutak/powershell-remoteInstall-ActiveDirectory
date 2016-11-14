# Arg1 = Computer name or Computer list
# Arg2 = Installer name
# Arg3 = Silent install option

# Check if first argument is file or just a computer name
if (Test-Path $Args[0]) {
    $Computers = (Get-Content $Args[0]) -as [string[]]
} else {
    $Computers = @($Args[0]);
}

# Define values
$InstallerName = $Args[1]
if ($Args[2]) {
	$SilentOption = $Args[2]
} else {
	$SilentOption = ""
}
$DownloadExecName = "exec.txt"
$LocalExecName = "exec.cmd"
$UncTargetShare = "\MIS_Temp$\"
$LocalTargetBase = "C:\MIS_Temp\"

$DownloadBase = "http://sspwebsrv01v.stripes.int/SoftwareDistribution/"
$DownloadUrlBat = $DownloadBase +  $DownloadExecName
$DownloadUrlInstaller = $DownloadBase +  $InstallerName


$LocalExecPath = $LocalTargetBase + $LocalExecName
$LocalInstallerPath = $LocalTargetBase + $InstallerName


# Repeat installation for listed computers
foreach ($Computer in $Computers) {

    $UncTargetBase = "\\" + $Computer + $UncTargetShare
    $UncBatPath = $UncTargetBase + $LocalExecName
    $UncInstallerPath = $UncTargetBase + $InstallerName

    # Delete if same name file exists in remote target folder
    if (Test-Path $UncBatPath) {
        Invoke-Command -ComputerName $Computer -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
    }
    if (Test-Path $UncInstallerPath) {
        Invoke-Command -ComputerName $Computer -Scriptblock{del $args[0]} -ArgumentList $LocalInstaller
    }

    # Download installer and exec script to remote computer
    Invoke-WebRequest -Uri $DownloadUrlBat -OutFile $UncBatPath
    Invoke-WebRequest -Uri $DownloadUrlInstaller -OutFile $UncInstallerPath

    # Kick downloaded installer
    Invoke-Command -ComputerName $Computer -Scriptblock{C:\MIS_Temp\exec.cmd $args[0] $args[1]} -ArgumentList $InstallerName,$SilentOption

    # Delete finished files
    Invoke-Command -ComputerName $Computer -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
    Invoke-Command -ComputerName $Computer -Scriptblock{del $args[0]} -ArgumentList $LocalInstallerPath
}