param(
    [string]$Root = 'D:\Doctor Who',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$videoExtensions = @('.mkv', '.mp4', '.avi', '.rmvb', '.mov', '.wmv', '.m4v', '.ts', '.webm')
$sourceDirectories = Get-ChildItem -LiteralPath $Root -Directory | Where-Object {
    $_.Name -notin @('Doctor Who (1963)', 'Doctor Who (2005)')
}

function Clean-Title([string]$value) {
    $value = $value -replace '^\s*(?:\d{1,3}|War Doctor)\s*[-–]\s*', ''
    $value = $value -replace '-\d{3}$', ''
    $value = $value -replace '_', "'"
    $value = $value -replace '[<>:"/\\|?*]', '-'
    $value = $value -replace '\s+', ' '
    return $value.Trim(' ', '.')
}

function Source-Number([System.IO.FileInfo]$file) {
    if ($file.BaseName -match 'Doctor Who\s+0*(\d{1,3})\s*-') {
        return [int]$Matches[1]
    }
    return $null
}

function Add-Plan($source, $destination, [ref]$plan) {
    $plan.Value.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
    })
}

# Canonical classic-series story/season/episode offsets, extracted from the
# Fandom page requested by the user.
$wikiUrl = 'https://doctorwho.fandom.com/pt/api.php?action=parse&page=Lista_de_epis%C3%B3dios_de_Doctor_Who&prop=wikitext&format=json'
$wikiText = (Invoke-RestMethod -Uri $wikiUrl).parse.wikitext.'*'
$storyMetadata = @{}
$storyMatches = [regex]::Matches(
    $wikiText,
    '(?ms)^!\s*scope="row"[^|]*\|(\d{3})\s*$\r?\n\|(.*?)\r?\n\|(.*?)\r?\n\|'
)
foreach ($match in $storyMatches) {
    $before = $wikiText.Substring(0, $match.Index)
    $seasonMatches = [regex]::Matches($before, '===\s*\[\[(\d+)ª Temporada \(SC\)\]\]')
    if ($seasonMatches.Count -eq 0) { continue }
    $season = [int]$seasonMatches[$seasonMatches.Count - 1].Groups[1].Value
    $episodeCell = $match.Groups[3].Value -replace 'style="[^"]*"\s*\|', ''
    $plainCell = ($episodeCell -replace '\{\{.*?\}\}', '' -replace '\[\[.*?\]\]', '' -replace '<[^>]+>', ' ').Trim()
    if ($plainCell -match '^\d+$') {
        $count = [int]$plainCell
    } else {
        $count = @($episodeCell -split '<br\s*/?>' | Where-Object {
            (($_ -replace '<[^>]+>', '') -replace '\s+', ' ').Trim().Length -gt 0
        }).Count
    }
    $titleCell = $match.Groups[2].Value
    $title = $titleCell
    if ($titleCell -match "\[\[(?:[^\]|]+\|)?([^\]]+)\]\]") { $title = $Matches[1] }
    $title = Clean-Title (($title -replace "''", '') -replace '<br.*$', '')
    $storyMetadata[[int]$match.Groups[1].Value] = [pscustomobject]@{
        Season = $season
        Count = $count
        Title = $title
    }
}

foreach ($season in 1..26) {
    $offset = 1
    foreach ($story in ($storyMetadata.Keys | Where-Object { $storyMetadata[$_].Season -eq $season } | Sort-Object)) {
        $storyMetadata[$story] | Add-Member -NotePropertyName StartEpisode -NotePropertyValue $offset
        $offset += $storyMetadata[$story].Count
    }
}
$globalOffset = 1
foreach ($story in ($storyMetadata.Keys | Sort-Object)) {
    $storyMetadata[$story] | Add-Member -NotePropertyName GlobalStart -NotePropertyValue $globalOffset
    $globalOffset += $storyMetadata[$story].Count
}

$regularModern = @{}
function Map-Range([string]$folderPattern, [int[]]$numbers, [int]$season, [int]$firstEpisode = 1) {
    for ($i = 0; $i -lt $numbers.Count; $i++) {
        $regularModern["$folderPattern|$($numbers[$i])"] = @($season, $firstEpisode + $i)
    }
}
Map-Range '9º' (1..13) 1
Map-Range '10º' (3..15) 2
Map-Range '10º' (17..29) 3
Map-Range '10º' (33..45) 4
Map-Range '11º' @(1,3,4,5,6,8,9,10,11,12,13,14,15) 5
Map-Range '11º' @(21,22,24,25,26,27,29,31,32,33,34,36,38) 6
Map-Range '11º' @(47,48,49,50,51,57,58,59,60,62,63,64,66) 7
Map-Range '12º' (1..12) 8
Map-Range '12º' (16..27) 9
Map-Range '12º' @(30,31,32,33) 10
Map-Range '12º' (35..41) 10 6
Map-Range '13ª' (1..10) 11
Map-Range '13ª' (12..21) 12
Map-Range '13ª' @(23,24,25,26,27,28) 13

$plan = [System.Collections.Generic.List[object]]::new()
$unmatched = [System.Collections.Generic.List[string]]::new()
$specialCandidates = [System.Collections.Generic.List[object]]::new()

foreach ($directory in $sourceDirectories) {
    $isClassic = $directory.Name -match '^[1-7][º°ª]'
    $isModern = $directory.Name -match '^(?:9º|10º|11º|12º|13ª)'
    $isBridge = $directory.Name -match '^(?:8º|War Doctor)'
    $files = Get-ChildItem -LiteralPath $directory.FullName -Recurse -File |
        Where-Object { $_.Extension.ToLowerInvariant() -in ($videoExtensions + '.srt') }

    foreach ($file in $files) {
        $title = Clean-Title $file.BaseName
        $destinationDirectory = $null
        $destinationBase = $null

        if ($isClassic) {
            $doctorNumber = [int]([regex]::Match($directory.Name, '^\d+').Value)
            $sourceNumber = Source-Number $file
            if ($doctorNumber -eq 6 -and $null -ne $sourceNumber) {
                if ($sourceNumber -le 4) {
                    $season = 21; $episode = 20 + $sourceNumber
                } elseif ($sourceNumber -le 17) {
                    $season = 22; $episode = $sourceNumber - 4
                } else {
                    $season = 23; $episode = $sourceNumber - 17
                }
                $destinationDirectory = Join-Path $Root ("Doctor Who (1963)\Season {0:D2}" -f $season)
                $destinationBase = "Doctor Who (1963) - S{0:D2}E{1:D2} - {2}" -f $season, $episode, $title
            } else {
                $relative = $file.FullName.Substring($directory.FullName.Length)
                $localStoryMatch = [regex]::Match($relative, 'Doctor Who\s+0*(\d{1,2})\s*-', 'IgnoreCase')
                $threeDigitMatches = [regex]::Matches($relative, '(?<!\d)(0(?:0[1-9]|[1-9]\d)|1[0-5]\d)(?!\d)')
                if ($doctorNumber -eq 1 -and $localStoryMatch.Success) {
                    $serial = [int]$localStoryMatch.Groups[1].Value
                } elseif ($doctorNumber -eq 2 -and $localStoryMatch.Success) {
                    $serial = 29 + [int]$localStoryMatch.Groups[1].Value
                } elseif ($doctorNumber -eq 3 -and $localStoryMatch.Success) {
                    $serial = 50 + [int]$localStoryMatch.Groups[1].Value
                } elseif ($threeDigitMatches.Count) {
                    $serial = [int]$threeDigitMatches[0].Value
                } else {
                    $unmatched.Add($file.FullName); continue
                }
                if (-not $storyMetadata.ContainsKey($serial)) {
                    $unmatched.Add($file.FullName); continue
                }
                $metadata = $storyMetadata[$serial]
                $leadingNumber = [regex]::Match($file.BaseName, '(?<!\d)(\d{3})(?!\d)')
                $afterLeading = if ($leadingNumber.Success) { $file.BaseName.Substring($leadingNumber.Index + $leadingNumber.Length) } else { $file.BaseName }
                $partMatch = [regex]::Match($afterLeading, '(?:part[e]?|[-.])\s*0*(\d{1,2})(?=[ ._(-]|$)', 'IgnoreCase')
                if ($partMatch.Success) {
                    $part = [int]$partMatch.Groups[1].Value
                } elseif ($leadingNumber.Success -and [int]$leadingNumber.Groups[1].Value -ne $serial) {
                    $part = [int]$leadingNumber.Groups[1].Value - $metadata.GlobalStart + 1
                } else {
                    $part = 1
                }
                $episode = $metadata.StartEpisode + $part - 1
                $season = $metadata.Season
                $destinationDirectory = Join-Path $Root ("Doctor Who (1963)\Season {0:D2}" -f $season)
                $destinationBase = "Doctor Who (1963) - S{0:D2}E{1:D2} - {2} - Part {3} - {4}" -f $season, $episode, $metadata.Title, $part, $title
            }
        } elseif ($isModern) {
            $folderKey = [regex]::Match($directory.Name, '^(?:9º|10º|11º|12º|13ª)').Value
            $number = Source-Number $file
            $key = "$folderKey|$number"
            if ($null -ne $number -and $regularModern.ContainsKey($key)) {
                $season, $episode = $regularModern[$key]
                $destinationDirectory = Join-Path $Root ("Doctor Who (2005)\Season {0:D2}" -f $season)
                $destinationBase = "Doctor Who (2005) - S{0:D2}E{1:D2} - {2}" -f $season, $episode, $title
            } else {
                $rank = switch ($folderKey) { '9º' { 9 }; '10º' { 10 }; '11º' { 11 }; '12º' { 12 }; '13ª' { 13 } }
                $specialCandidates.Add([pscustomobject]@{
                    File = $file; Rank = $rank; Number = $(if ($null -eq $number) { 999 } else { $number }); Title = $title
                })
                continue
            }
        } elseif ($isBridge) {
            $rank = if ($directory.Name -match '^8º') { 8 } else { 8.5 }
            $number = Source-Number $file
            $specialCandidates.Add([pscustomobject]@{
                File = $file; Rank = $rank; Number = $(if ($null -eq $number) { 999 } else { $number }); Title = $title
            })
            continue
        } else {
            continue
        }

        Add-Plan $file.FullName (Join-Path $destinationDirectory ($destinationBase + $file.Extension.ToLowerInvariant())) ([ref]$plan)
    }
}

# TMDB's special numbering changes independently of broadcast chronology. Keep
# specials legible and isolated without assigning a potentially wrong TMDB ID.
foreach ($item in ($specialCandidates | Sort-Object Rank, Number, @{Expression={$_.File.Extension -ne '.srt'}}, Title)) {
    $destinationDirectory = Join-Path $Root 'Doctor Who (2005)\Season 00'
    $destinationBase = "Doctor Who (2005) - SPECIAL - $($item.Title)"
    Add-Plan $item.File.FullName (Join-Path $destinationDirectory ($destinationBase + $item.File.Extension.ToLowerInvariant())) ([ref]$plan)
}

$duplicateDestinations = $plan | Group-Object Destination | Where-Object Count -gt 1
$existingDestinations = $plan | Where-Object {
    (Test-Path -LiteralPath $_.Destination) -and ($_.Source -ne $_.Destination)
}

Write-Host ("Planned moves: {0}" -f $plan.Count)
Write-Host ("Unmatched files: {0}" -f $unmatched.Count)
Write-Host ("Duplicate destinations: {0}" -f $duplicateDestinations.Count)
Write-Host ("Existing destination collisions: {0}" -f $existingDestinations.Count)

if ($unmatched.Count) {
    Write-Host "`nUNMATCHED:"
    $unmatched | ForEach-Object { Write-Host $_ }
}
if ($duplicateDestinations.Count) {
    Write-Host "`nDUPLICATES:"
    $duplicateDestinations | ForEach-Object { Write-Host $_.Name; $_.Group.Source | ForEach-Object { Write-Host "  $_" } }
}
if ($existingDestinations.Count) {
    Write-Host "`nCOLLISIONS:"
    $existingDestinations | ForEach-Object { Write-Host "$($_.Source) -> $($_.Destination)" }
}

if (-not $Apply) {
    $plan | Select-Object -First 30 | Format-Table -AutoSize
    Write-Host "`nDry run only. Re-run with -Apply after resolving all reported issues."
    exit 0
}
if ($unmatched.Count -or $duplicateDestinations.Count -or $existingDestinations.Count) {
    throw 'Safety check failed; no files were moved.'
}

foreach ($item in $plan) {
    $parent = Split-Path -Parent $item.Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    Move-Item -LiteralPath $item.Source -Destination $item.Destination
}
Write-Host ("Moved {0} files successfully." -f $plan.Count)
