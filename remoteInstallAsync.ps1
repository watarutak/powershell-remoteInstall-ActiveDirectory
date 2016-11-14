# Arg0 = Computer name or Computer list
# Arg1 = Installer name
# Arg2 = Silent install option

# Check if first argument is file or just a computer name
if (Test-Path $Args[0]) {
    $computers = (Get-Content $Args[0]) -as [string[]]
} else {
    $computers = @($Args[0]);
}

# Define values
$InstallerName = $Args[1]
if ($Args[2]) {
	$SilentOption = $Args[2]
} else {
	$SilentOption = ""
}
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
set -name RESULT_SUCCESS -value 1 -option constant
set -name RESULT_FALSE -value 0 -option constant
set -name RESULT_YET -value 3 -option constant

#Array for Result
$check = @()

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
        # Store Session name


        # Delete if same name file exists in remote target folder
        if (Test-Path $UncBatPath) {
            Invoke-Command -Session $s -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath -errorAction stop
        }
        if (Test-Path $UncInstallerPath) {
            Invoke-Command -Session $s -Scriptblock{del $args[0]} -ArgumentList $LocalInstaller -errorAction stop
        }

        # Download installer and exec script to target computer
        Invoke-WebRequest -Uri $DownloadUrlBat -OutFile $UncBatPath -errorAction stop
        Invoke-WebRequest -Uri $DownloadUrlInstaller -OutFile $UncInstallerPath -errorAction stop

        # Kick downloaded installer as a Background job
        #Invoke-Command -Session $s -Scriptblock{C:\MIS_Temp\exec.cmd $args[0] $args[1]} -ArgumentList $InstallerName,$SilentOption -AsJob
        Invoke-Command -Session $s -Scriptblock{C:\MIS_Temp\installation.ps1 $args[0] $args[1]} -ArgumentList $InstallerName,$SilentOption -AsJob -errorAction stop
        $ret.add("result",$RESULT_YET)
        $ret.add("session",$s)
    }
    catch
    {
        # Add error handling
        $ret.add("result",$RESULT_FALSE)
    }
    finally
    {
        $check += $ret
    }
}

# 結果確認ループ
$checkCount = $check.Length
while ($checkCount -ne 0) {
    #結果確認
    $checkCount = $check.Length
    for ($i = 0;$i -lt $totalcheck; $i++) {
        if ($check[$i]["result"] -eq $RESULT_YET) {
            #結果確認
            if () {
                # returnが1ならインストールされているプログラムの一覧にアプリ名とバージョンがあるか確認

                $check[$i]["result"] = $RESULT_SUCCESS
                $checkCount--
            } else if () {
                $check[$i]["result"] = $RESULT_FALSE
                $checkCount--
            }

        } else {
            $checkCount--
        }
    }
}

# 結果をテキストに出力
for ($i = 0; $i -lt $result.Count; $i++) {
  # 書き出し処理
}





# Delete finished files
Invoke-Command -ComputerName $Computer -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
Invoke-Command -ComputerName $Computer -Scriptblock{del $args[0]} -ArgumentList $LocalInstallerPath
