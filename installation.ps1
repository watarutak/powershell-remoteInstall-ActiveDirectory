# Args[0]  installer name
# Args[1]  silent install option

$path = "./" + $Args[0]
$process = (Start-Process -FilePath $path -ArgumentList $Args[1] -Wait)

Exit $process.ExitCode