#  WSL compact, v3.2023.01.30
# 
#  (C) 2023 Oscar Lopez. 
#  For more information visit: https://github.com/okibcn/wslcompact
# 

$sf = 1.05
$compact = $false
$data = $false
$force = $false
$help = $false
$target_distros = foreach ($arg in $args) {
    if ($arg[0] -eq '-') { 
        $compact = $compact -or ("Cc" -match $arg[1])
        $data = $data -or ("Dd" -match $arg[1])
        $force = $force -or ("Yy" -match $arg[1])
        $help = $help -or ("Hh" -match $arg[1])
    }
    else { 
        $arg
    }
}
Write-Host " WSL compact, v3.2023.01.30
 (C) 2023 Oscar Lopez 
 wslcompact -h for help. For more information visit: https://github.com/okibcn/wslcompact"

if ($help) {
    Write-Host "
    
    Usage: wslcompact [OPTIONS] [DISTROS]

    wslcompact compacts the images of WSL distros by removing unsused space.
    If no option is provided, it will default to info mode, without modifying any image.
    If no distro is provided it will process all the installed images.
    NOTE: WSL will be shutdown for compacting the images.

    Options:
        -c   Compacting mode: process the selected distros compacting the images.
        -d   Enable the processing of data images. Default is disabled.
        -y   Perform actions without asking for confirmation.
        -h   Prints this help

    Examples: 
        wslcompact
        wslcompact -c -d
        wslcompact -c -y Ubuntu Kali

    "
    exit 0
}
$tmp_folder = "$Env:TEMP\wslcompact"
$freedisk = (Get-PSDrive $env:TEMP[0]).free
mkdir "$tmp_folder" -ErrorAction SilentlyContinue | Out-Null
Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\`{* | ForEach-Object {
    $wsl_ = Get-ItemProperty $_.PSPath
    $wsl_distro = $wsl_.DistributionName
    $wsl_path = if ($wsl_.BasePath.StartsWith('\\')) { $wsl_.BasePath.Substring(4) } else { $wsl_.BasePath }
    if ( !$target_distros -or ($wsl_distro -in $target_distros) ) {
        # The wsl_distro is marked for processing
        $size1 = (Get-Item -Path "$wsl_path\ext4.vhdx").Length / 1MB
        Write-Host "`n Distro's name:  $wsl_distro"
        Write-Host " Image file:     $wsl_path\ext4.vhdx"
        Write-Host " Current size:   $size1 MB"
        if ("$wsl_distro" -match "data") {
            Write-Host " The image is not a WSL OS, but a data partition. No size estimation is available at this time."
            $estimated = [long]($size1)
        }
        else {
            $estimated = ((wsl -d "$wsl_distro" -e df /) | select-string " +\d+ +(\d+)").Matches[0].Groups[1].Value
            $estimated = [long]($estimated/1024)
            Write-Host " Estimated size: $([long]($estimated * ((($sf - 1) / 2) + 1))) +/- $([long]($estimated * ($sf - 1) / 2)) MB"
            Write-Host " The estimated process time using an SSD is about $([math]::ceiling($estimated/4000)) minutes."
        }
        if (($estimated * $sf) -lt ($freedisk/1MB)) {
            # There is enough free space in the TEMP drive or a data image.
            if ($compact) {
                # we are not in info mode we process the image.
                if ((!$data) -and ("$wsl_distro" -match "data")) {
                    Write-Host " Bypassing data image. use -d option to force processing of data images."
                    Continue
                }
                $answer = if ($force) {'y'} else {read-host -prompt " Are you sure to process the image (y/N)"}
                if ($answer -match 'y') {
                    Write-Host " " -NoNewLine
                    remove-item "$tmp_folder/*" -Recurse -Force 
                    wsl --shutdown
                    cmd /c "wsl --export ""$wsl_distro"" - | wsl --import wslclean ""$tmp_folder"" -"
                    wsl --shutdown
                    if (Test-Path "$tmp_folder/ext4.vhdx") {
                        Move-Item "$tmp_folder/ext4.vhdx" "$wsl_path" -Force
                        wsl --unregister wslclean | Out-Null
                        $size2 = (Get-Item -Path "$wsl_path\ext4.vhdx").Length / 1MB
                        Write-Host " Compacted from $size1 MB to $size2 MB`n"
                    }
                    else {
                        Write-Host " WARNING: wslcompact found errors in the current image. It could be a storage problem,"
                        Write-Host "          a corrupted ext4 filesystem, or any other issue. Image not processed."
                    }            
                }            
            }        
        }
        else {
            # There isn't enough free space in the TEMP drive
            write-Host " WARNING: there isn't enough free space in temp drive"(Get-PSDrive $env:TEMP[0])"to process $wsl_distro."
            write-Host "          There are only $([long]($freedisk / 1MB)) MB available."
            write-Host ""
            write-Host " Please, change the TEMP folder to a drive with at least $([long]($estimated * $sf / 1MB)) MB of free space."
            write-Host " You cand do it by typing `$env:TEMP=`"Z:/your/new/temp/folder`" before using wslcompact.`n"
        }
    }
}
Remove-Item -Recurse -Force "$tmp_folder"
write-Host ""
