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
set -name RESULT_SUCCESS -value 1 -option constant
set -name RESULT_FALSE -value 0 -option constant
set -name RESULT_YET -value 3 -option constant

# Array for results
$result = @()

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
        #Invoke-Command -Session $s -Scriptblock{C:\MIS_Temp\installation.ps1 $args[0] $args[1]} -ArgumentList $InstallerName,$SilentOption -AsJob -errorAction stop
        $jobName = $ret["computer"] + $InstallerName
        Invoke-Command -Session $s -Scriptblock{ Start-Job -Name $args[0] -Scriptblock{C:\MIS_Temp\installation.ps1 $args[1] $args[2]}} -ArgumentList $jobName,$InstallerName,$SilentOption -errorAction stop
        $ret.add("result",$RESULT_YET)

    }
    catch
    {
        # Add error handling
        $ret.add("result",$RESULT_FALSE)
        # Delete used files
        if (Test-Path $UncBatPath) {
            Invoke-Command -ComputerName $ret["computer"] -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
        }
        if (Test-Path $UncInstallerPath) {
            Invoke-Command -ComputerName $ret["computer"] -Scriptblock{del $args[0]} -ArgumentList $LocalInstaller
        }

        # 結果をテキストに出力 (False)
        $text = $ret["computer"] + " : " + "Failed`n"
        $text | Out-File $LogFile -Append
    }
    finally
    {
        if ($s){
            $s = Disconnect-PSSession -Session $s
            $ret.add("session",$s)
        }
        $result += $ret
    }
}

# 結果確認ループ
# 初期化
$resultCount = 1
while ($resultCount -ne 0) {
    #結果確認
    $resultCount = $result.Length
    # 結果ファイル読み込み
    $fileTexts = (Get-Content $LogFile) -as [string[]]
    for ($i = 0;$i -lt $result.Length; $i++) {
        if ($result[$i]["result"] -eq $RESULT_YET) {
            #結果確認
            Connect-PSSession -Session $result[$i]["session"]  # ターゲットコンピュータに再接続
            # 結果取得
            $jobName = $result[$i]["computer"] + $InstallerName
            $jobResult = Invoke-Command -Session $result[$i]["session"] -ScriptBlock { Receive-Job -Name $args[0]} -ArgumentList $jobName
            if (($jobResult -eq $RESULT_SUCCESS) -Or ($jobResult -eq $RESULT_FALSE)) {
                # returnが1ならインストールされているプログラムの一覧にアプリ名とバージョンがあるか確認
                $result[$i]["result"] = $jobResult
                $resultCount--

                # Delete finished files
                Invoke-Command -Session $result[$i]["session"] -Scriptblock{del $args[0]} -ArgumentList $LocalExecPath
                Invoke-Command -Session $result[$i]["session"] -Scriptblock{del $args[0]} -ArgumentList $LocalInstallerPath

                if ($jobResult) {
                    $resultText = $result[$i]["computer"] + " : " + "Success`n"
                } else {
                    $resultText = $result[$i]["computer"] + " : " + "Failed`n"
                }
            } else {
                $resultText = $result[$i]["computer"] + " : " + "Unknown`n"
            }

            # $fileTextsに$result[$i]["computer"] + " : " + "Unknown`n"が含まれていれば$resultTextと入れ替える
            $unknown = $result[$i]["computer"] + " : " + "Unknown`n"
            $flg = 0
            for ($ii=0; $ii -lt $fileTexts.Length; $ii++) {
                if ($fileTexts[$ii] -eq $unknown) {
                    $fileTexts[$ii] = $resultText
                    $flg = 1
                }
            }
            if (!$flg) {
              $fileTexts +=$resultText
            }

            # Disconnect-PSSession
            Disconnect-PSSession -Session $result[$i]["session"]

        } else {  # もう結果確認が終了したターゲットコンピュータ
            # セッションがあれば削除
            if ($result[$i]["session"]) {
                Remove-PSSession -Session $result[$i]["session"]
            }
            $resultCount--
        }
    }

    # 結果ファイルを一旦削除して作り直し
    Remove-Item $LogFile
    New-Item $LogFile -ItemType File
    for ($i=0; $i -lt $fileTexts.Length; $i++) {
        $fileTexts[$i] | Out-File $LogFile -Append
    }

    # 次回確認までのWait処理 - 5分
    Start-Sleep -Seconds 300
}
