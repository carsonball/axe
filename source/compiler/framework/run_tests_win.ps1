cd ..

Set-StrictMode -Version Latest

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
Set-Location $scriptDir

if (-not (Test-Path "../axc.exe")) {
    Write-Host "ERROR: axc not found in $PWD\axc" -ForegroundColor Red
    exit 1
}

$failed = 0
$counts = @{ total = 0; passed = 0; failed = 0 }
$failedFiles = @()
$stdFolder = "..\\std"
if (Test-Path $stdFolder) {
    Write-Host ""
    Write-Host "Compiling std files in $stdFolder..."

    Get-ChildItem -Path $stdFolder -Recurse -Filter *.axe -File | ForEach-Object {
        $file = $_.FullName
        $counts.total++
        Write-Host "------------------------------"
        Write-Host "Compiling $file"

        & ..\axc $file
        $exit = $LASTEXITCODE

        if ($exit -ne 0) {
            Write-Host "FAILED: $file" -ForegroundColor Red
            $failed++
            $counts.failed++
            $failedFiles += $file
        } else {
            Write-Host "OK: $file" -ForegroundColor Green
            $counts.passed++
        }
    }
} else {
    Write-Host "Skipping missing std folder: $stdFolder"
}

$folders = @("..\\..\\tests\\self_tests", "..\\..\\tests\\legacy_tests")

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        Write-Host "Skipping missing folder: $folder"
        continue
    }

    Write-Host ""
    Write-Host "Running tests in $folder..."

    Get-ChildItem -Path $folder -Recurse -Filter *.axe -File | ForEach-Object {
        $file = $_.FullName
        $counts.total++
        Write-Host "------------------------------"
        Write-Host "Running $file"

        & ..\axc $file
        $exit = $LASTEXITCODE

        $isErrorTest = $_.Name -like '*_error.axe'

        if ($isErrorTest) {
            if ($exit -ne 0) {
                Write-Host "OK (expected failure): $file" -ForegroundColor Green
                $counts.passed++
            } else {
                Write-Host "FAILED (expected error but succeeded): $file" -ForegroundColor Red
                $failed++
                $counts.failed++
                $failedFiles += $file
            }
        } else {
            if ($exit -ne 0) {
                Write-Host "FAILED: $file" -ForegroundColor Red
                $failed++
                $counts.failed++
                $failedFiles += $file
            } else {
                Write-Host "OK: $file" -ForegroundColor Green
                $counts.passed++
            }
        }
    }
}

Write-Host ""
Write-Host "Summary: Total=$($counts.total) Passed=$($counts.passed) Failed=$($counts.failed)"
if ($failed -eq 0) {
    Write-Host "All tests passed." -ForegroundColor Green
} else {
    Write-Host "Some tests failed." -ForegroundColor Yellow
    Write-Host "\nFailed files:"
    foreach ($f in $failedFiles) {
        Write-Host " - $f" -ForegroundColor Red
    }
}

exit $failed
