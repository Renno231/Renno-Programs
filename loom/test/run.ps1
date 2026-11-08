# Runs loom's regression tests on Ocelot Harness: a tier-3 machine with QuickOS and loom boots,
# runs loomtest.lua (widgets driven by pushed signals) and one check with real typed keys.
# Prints the results; exits 1 if any test failed. The project folder is deleted afterwards.
param(
    [string]$Harness = (Join-Path $env:USERPROFILE "Documents\AgenticResearch\ocelotharness"),
    [string]$QuickOS = (Join-Path $env:USERPROFILE "Documents\GitHub\QuickOS"),
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "loomtest")
)
$ErrorActionPreference = "Stop"
$ctl = Join-Path $Harness "scripts\ocelotctl.cmd"
$daemon = Join-Path $Harness "scripts\ocelot-harnessd.cmd"
$loom = Split-Path $PSScriptRoot

function Ctl {
    $output = & $ctl --project $Work @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ocelotctl $($args -join ' ') failed:`n$($output -join "`n")" }
    return ($output -join "`n")
}
function Wait-Screen([string]$Text, [string]$Timeout = "120s") {
    $result = Ctl screen wait pc-screen --contains $Text --max-ticks 20000 --timeout $Timeout
    if (-not (Ctl screen read pc-screen).Contains($Text)) {
        $screen = ((Ctl screen read pc-screen) -split "`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ }) -join "`n"
        throw "screen never showed '$Text' ($result). Screen:`n$screen"
    }
}
function Send-Line([string]$Text) {
    Ctl screen type pc-screen $Text | Out-Null
    Ctl screen key-down pc-screen enter | Out-Null
    Ctl screen key-up pc-screen enter | Out-Null
}

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
$disk = Join-Path $Work "pc"
New-Item $disk -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot "ocelot-harness.conf") $Work
Get-ChildItem $QuickOS -Force | Where-Object { $_.Name -ne ".git" } | Copy-Item -Destination $disk -Recurse -Force
Copy-Item (Join-Path $loom "lib\*") (Join-Path $disk "usr\lib") -Recurse -Force
New-Item (Join-Path $disk "home") -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot "*.lua") (Join-Path $disk "home") -Force
[IO.File]::WriteAllText((Join-Path $disk "etc\hostname"), "pc", (New-Object Text.UTF8Encoding($false)))

$started = $false
$failed = $true
try {
    & $daemon up --project $Work | Out-Null
    $started = $true
    Ctl machine start pc | Out-Null
    Wait-Screen "pc:/home #"
    Send-Line "loomtest"
    Wait-Screen "loomtest done" "120s"
    $results = Get-Content (Join-Path $disk "home\loomtest.txt")

    # Real keyboard input: touch the field, type, press Enter.
    Send-Line "typetest"
    Wait-Screen "Name:"
    Ctl screen touch pc-screen 8 2 | Out-Null
    Ctl screen type pc-screen "Ada Lovelace" | Out-Null
    Ctl screen key-down pc-screen enter | Out-Null
    Ctl screen key-up pc-screen enter | Out-Null
    Wait-Screen "typetest done"
    $typed = (Get-Content (Join-Path $disk "home\typetest.txt") -Raw).Trim()
    $results += $(if ($typed -eq "Ada Lovelace") { "PASS real keys typed and submitted" } else { "FAIL real keys typed and submitted  got '$typed'" })

    $results | ForEach-Object { $_ }
    $failed = @($results | Where-Object { $_ -like "FAIL*" }).Count -gt 0
} finally {
    if ($started) { & $daemon down --project $Work | Out-Null }
    if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
}
if ($failed) { exit 1 }
