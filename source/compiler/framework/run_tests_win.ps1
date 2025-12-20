cd ..

Set-StrictMode -Version Latest

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
Set-Location $scriptDir

if (-not (Test-Path "../axc.exe")) {
    Write-Host "ERROR: axc not found in $PWD\axc" -ForegroundColor Red
    exit 1
}

$axcPath = Resolve-Path "../axc.exe"
$axcDir  = Split-Path $axcPath -Parent
$failed  = 0

Write-Host "Running 'saw test' in $axcDir..."
Push-Location $axcDir
& saw test
$sawExit = $LASTEXITCODE
Pop-Location

if ($sawExit -ne 0) {
    Write-Host "FAILED: saw test" -ForegroundColor Red
    exit 1
} else {
    Write-Host "OK: saw test" -ForegroundColor Green
}
 
$counts = @{ total = 0; passed = 0; failed = 0 }
$failedFiles = @()
$stdFolder = "..\\std"

Write-Host ""
Write-Host "Testing self-compilation: building axc2 with tested axc..."
Push-Location $axcDir
$counts.total++
$axc2Path = Join-Path $axcDir "axc2.exe"

if (Test-Path $axc2Path) {
    Remove-Item $axc2Path -Force -ErrorAction SilentlyContinue
}
Write-Host "Running: & .\axc axc -o axc2"
& .\axc axc -o axc2
$scExit = $LASTEXITCODE

Write-Host "Running: & .\axc2 axc -o axc3"
& .\axc2 axc -o axc3
$scExit = $LASTEXITCODE

Pop-Location

if ($scExit -ne 0) {
    Write-Host "FAILED: self-compilation (axc -> axc2) - exit code $scExit" -ForegroundColor Red
    $failed++
    $counts.failed++
    $failedFiles += "self-compilation (exit $scExit)"
} else {
    if (Test-Path $axc2Path) {
        Write-Host "OK: self-compilation (exit 0) produced $axc2Path" -ForegroundColor Green
    } else {
        Write-Host "WARNING: self-compilation returned exit 0 but $axc2Path not found" -ForegroundColor Yellow
        $failed++
        $counts.failed++
        $failedFiles += "self-compilation (missing axc2)"
    }
}

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
Write-Host "Summary: Total=$($counts.total) Passed=$($counts.passed + 1) Failed=$($counts.failed)"

if ($failed -eq 0) {
    Write-Host "All tests passed." -ForegroundColor Green
} else {
    Write-Host "Some tests failed." -ForegroundColor Yellow
    Write-Host "`nFailed files:"
    foreach ($f in $failedFiles) {
        Write-Host " - $f" -ForegroundColor Red
    }
}

