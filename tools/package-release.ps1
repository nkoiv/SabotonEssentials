$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$tocPath = Join-Path $root 'SabotonEssentials.toc'
$tocLines = @(Get-Content -LiteralPath $tocPath)
$versionLines = @($tocLines | Where-Object { $_ -match '^## Version:\s*(\S+)\s*$' })
if ($versionLines.Count -ne 1 -or $versionLines[0] -notmatch '^## Version:\s*(\d+\.\d+\.\d+(?:-(?:alpha|beta)(?:\.\d+)?)?)\s*$') {
    throw 'The TOC must contain exactly one valid release version.'
}
$version = $Matches[1]

foreach ($line in $tocLines) {
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith('#')) { continue }
    $path = Join-Path $root $entry
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing TOC file: $entry"
    }
}

$runtimeFiles = @('SabotonEssentials.toc', 'LICENSE', 'README.md')
$runtimeFiles += @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -File -Recurse | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
$runtimeFiles += @(Get-ChildItem -LiteralPath (Join-Path $root 'Media') -File | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
foreach ($sound in @('squeak.mp3', 'kaching.mp3', 'HumanMaleAggroA.ogg', 'clear-bell-chime.mp3', 'impact-thud.mp3')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root "Media\$sound") -PathType Leaf)) {
        throw "Missing sound: $sound"
    }
}

$outputDirectory = Join-Path $root 'releases'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$archivePath = Join-Path $outputDirectory "SabotonEssentials-$version.zip"
if (Test-Path -LiteralPath $archivePath) {
    throw "Archive already exists: $archivePath. Move or remove it before rebuilding this version."
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $runtimeFiles) {
        $entryName = 'SabotonEssentials/' + $file.Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $file), $entryName) | Out-Null
    }
} catch {
    $archive.Dispose()
    Remove-Item -LiteralPath $archivePath
    throw
} finally {
    $archive.Dispose()
}

Write-Output "Created $archivePath"