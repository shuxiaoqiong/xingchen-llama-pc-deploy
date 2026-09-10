<#
.SYNOPSIS
    XingChen4-29B llama.cpp one-click deploy script (Windows, GPU or CPU)
.DESCRIPTION
    1. Check dependencies (git, cmake, VS2022, nvcc)
    2. Auto-detect CUDA Toolkit path (skipped in CPU mode)
    3. Clone / update llama.cpp repo
    4. Switch to xingchen4-port branch
    5. Download Web UI assets (from HF mirror)
    6. Build llama.cpp (GPU or CPU backend)
    7. Launch llama-server and auto-open browser
.NOTES
    All environment-sensitive paths (CUDA, VS, model, static files) are auto-detected.
    Usage:
      .\deploy-xingchen4.ps1                  # default: GPU
      .\deploy-xingchen4.ps1 -Backend cpu     # CPU mode
      .\deploy-xingchen4.ps1 -Port 8086
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ModelPath   = "xingchen4-iq4-00001-of-00002.gguf",
    [int]   $ContextSize = 262144,
    [ValidateSet('gpu','cpu',IgnoreCase=$true)]
    [string]$Backend    = "gpu",
    [int]   $GpuLayers   = 999,
    [int]   $Port        = 8086,
    [string]$HostAddr    = "0.0.0.0",
    [string]$StaticPath  = "",
    [string]$CloneBase   = "https://github.com/shuxiaoqiong",
    [string]$WorkDir     = $PSScriptRoot
)

# If ModelPath is relative, resolve against WorkDir
if (-not [System.IO.Path]::IsPathRooted($ModelPath)) {
    $ModelPath = Join-Path $WorkDir $ModelPath
}

# ============================================================================
# 0. Helper functions
# ============================================================================
# PowerShell 5.1 treats native-command stderr as terminating errors when
# ErrorActionPreference is Stop. We use Continue so git/cmake stderr (progress,
# warnings) does not abort the script. Manual exit-code checks handle real failures.
$ErrorActionPreference = "Continue"
Set-StrictMode -Version 3.0
# Force TLS 1.2 for HTTPS downloads (PS 5.1 defaults to TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step  { param([string]$Msg) Write-Host "`n========== $Msg ==========" -ForegroundColor Cyan }
function Write-OK    { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn2 { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }
function Write-Info  { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor DarkGray }

function Exit-Script {
    param([string]$Msg = "")
    if ($Msg) { Write-Err $Msg }
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ============================================================================
# 1. Dependency check
# ============================================================================
Write-Step "1/7  Dependency check"

$missing = @()

# Git
if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
    $gitVer = git --version 2>&1
    Write-OK "Git: $gitVer"
} else {
    Write-Err "Git not found. Install: https://git-scm.com"
    $missing += "Git"
}

# CMake
if (Get-Command cmake -CommandType Application -ErrorAction SilentlyContinue) {
    $cmakeVer = cmake --version 2>&1 | Select-Object -First 1
    Write-OK "CMake: $cmakeVer"
} else {
    Write-Err "CMake not found. Install: https://cmake.org/download"
    $missing += "CMake"
}

# Visual Studio 2022 (via vswhere)
$vsFound = $false
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) {
        Write-OK "Visual Studio 2022: $vsPath"
        $vsFound = $true
    }
}
if (-not $vsFound) {
    Write-Err "Visual Studio 2022 (with C++ desktop) not found. Install: https://visualstudio.microsoft.com/downloads"
    $missing += "Visual Studio 2022"
}

if ($missing.Count -gt 0) {
    Exit-Script "Missing $($missing.Count) dependency(ies). Please install and retry."
}

# ============================================================================
# 2. Auto-detect CUDA Toolkit (skip in CPU mode)
# ============================================================================
Write-Step "2/7  Auto-detect CUDA Toolkit"

$cudaRoot = $null

if ($Backend -eq 'cpu') {
    Write-OK "CPU mode selected, CUDA detection skipped"
} else {
    # Method A: via nvcc (most reliable)
    # Select-Object -First 1 in case multiple CUDA versions are in PATH
    $nvcc = Get-Command nvcc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nvcc) {
        $cudaRoot = Split-Path (Split-Path $nvcc.Source -Parent) -Parent
        Write-OK "CUDA detected via nvcc: $cudaRoot"
    }

    # Method B: env var CUDA_PATH / CUDA_PATH_V*
    if (-not $cudaRoot -and $env:CUDA_PATH) {
        $cudaRoot = $env:CUDA_PATH
        Write-OK "CUDA detected via CUDA_PATH: $cudaRoot"
    }
    if (-not $cudaRoot) {
        $cudaEnvVars = Get-ChildItem 'env:CUDA_PATH*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'CUDA_PATH' -and $_.Value } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($cudaEnvVars) {
            $cudaRoot = $cudaEnvVars.Value
            Write-OK "CUDA detected via $($cudaEnvVars.Name): $cudaRoot"
        }
    }

    # Method C: scan default install directory (newest version)
    if (-not $cudaRoot) {
        $cudaBase = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
        if (Test-Path $cudaBase) {
            $latest = Get-ChildItem $cudaBase -Directory |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($latest) {
                $cudaRoot = $latest.FullName
                Write-OK "CUDA detected via directory scan: $cudaRoot"
            }
        }
    }

    # Verify nvcc executable
    if ($cudaRoot -and (Test-Path "$cudaRoot\bin\nvcc.exe")) {
        $nvccVer = & "$cudaRoot\bin\nvcc.exe" --version 2>&1 |
            Select-String "release" |
            Select-Object -First 1
        Write-OK "CUDA nvcc version: $($nvccVer.ToString().Trim())"
    } else {
        Exit-Script "CUDA Toolkit not found. Install: https://developer.nvidia.com/cuda-toolkit-archive"
    }
}

# ============================================================================
# 3. Clone / update llama.cpp repo
# ============================================================================
Write-Step "3/7  Clone / update llama.cpp"

$llamaCppDir = Join-Path $WorkDir "llama.cpp"
$llamaCppUrl = "$CloneBase/llama.cpp"

if (Test-Path (Join-Path $llamaCppDir ".git")) {
    Write-Info "llama.cpp exists, running git pull ..."
    Push-Location $llamaCppDir
    git pull 2>&1 | ForEach-Object { Write-Info $_ }
    if ($LASTEXITCODE -ne 0) { Exit-Script "git pull failed for llama.cpp (exit $LASTEXITCODE)" }
    Pop-Location
} else {
    Write-Info "Cloning llama.cpp -> $llamaCppDir"
    git clone $llamaCppUrl $llamaCppDir 2>&1 | ForEach-Object { Write-Info $_ }
    if ($LASTEXITCODE -ne 0) { Exit-Script "git clone llama.cpp failed (exit $LASTEXITCODE)" }
}
if (-not (Test-Path $llamaCppDir)) {
    Exit-Script "Failed to clone llama.cpp"
}
Write-OK "llama.cpp ready"

# ============================================================================
# 4. Switch to xingchen4-port branch
# ============================================================================
Write-Step "4/7  Switch to xingchen4-port branch"

Push-Location $llamaCppDir
try {
    git fetch origin 2>&1 | ForEach-Object { Write-Info $_ }
    if ($LASTEXITCODE -ne 0) { Exit-Script "git fetch failed (exit $LASTEXITCODE)" }

    $branchExists = git branch --list "xingchen4-port" 2>$null
    if ($branchExists) {
        git checkout xingchen4-port 2>&1 | ForEach-Object { Write-Info $_ }
    } else {
        git checkout -b xingchen4-port origin/xingchen4-port 2>&1 | ForEach-Object { Write-Info $_ }
    }

    $currentBranch = git rev-parse --abbrev-ref HEAD
    if ($currentBranch -ne "xingchen4-port") {
        Exit-Script "Branch switch failed. Current: $currentBranch"
    }
    Write-OK "Current branch: $currentBranch"
} finally {
    Pop-Location
}

# ============================================================================
# 5. Download Web UI assets (from HF mirror)
# ============================================================================
Write-Step "5/7  Download Web UI assets"

$uiDistDir    = Join-Path $llamaCppDir "tools\ui\dist"
$uiArchive    = Join-Path $env:TEMP "llama-ui-dist.tar.gz"
$uiSha256File = "$uiArchive.sha256"
$hfBaseUrl    = "https://hf-mirror.com/buckets/ggml-org/llama-ui/resolve/latest"

if (Test-Path (Join-Path $uiDistDir "index.html")) {
    Write-OK "Web UI assets already present: $uiDistDir"
} else {
    Write-Info "Downloading from HF mirror ..."
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $downloadOk = $false

    try {
        Invoke-WebRequest -Uri "$hfBaseUrl/dist.tar.gz" -OutFile $uiArchive -TimeoutSec 300
        $downloadOk = $true
        $sz = [math]::Round((Get-Item $uiArchive).Length / 1MB, 1)
        Write-OK "Downloaded dist.tar.gz ($sz MB)"
    } catch {
        Write-Warn2 "Download failed: $($_.Exception.Message)"
        Write-Info "Build will proceed without embedded UI."
    }

    if ($downloadOk -and (Test-Path $uiArchive)) {
        # Verify SHA256 checksum
        try {
            Invoke-WebRequest -Uri "$hfBaseUrl/dist.tar.gz.sha256" -OutFile $uiSha256File -TimeoutSec 30
            $expectedHash = (Get-Content $uiSha256File -Raw).Trim() -replace '\s.*$', ''
            $actualHash = (Get-FileHash $uiArchive -Algorithm SHA256).Hash.ToLower()
            if ($expectedHash -and $actualHash -eq $expectedHash.ToLower()) {
                Write-OK "SHA256 verified"
            } else {
                Write-Warn2 "SHA256 mismatch, proceeding anyway"
            }
        } catch {
            Write-Warn2 "Could not download SHA256, proceeding anyway"
        }

        # Extract using tar.exe (built-in on Windows 10 1803+)
        $tarExe = Get-Command tar -CommandType Application -ErrorAction SilentlyContinue
        if ($tarExe) {
            if (Test-Path $uiDistDir) { Remove-Item $uiDistDir -Recurse -Force }
            New-Item -ItemType Directory -Path $uiDistDir -Force | Out-Null
            Write-Info "Extracting to $uiDistDir ..."
            & tar -xzf $uiArchive -C $uiDistDir 2>&1 | ForEach-Object { Write-Info $_ }
            if (Test-Path (Join-Path $uiDistDir "index.html")) {
                Write-OK "Web UI extracted to $uiDistDir"
            } else {
                Write-Warn2 "Extraction may have failed (index.html not found)"
            }
        } else {
            Write-Warn2 "tar.exe not found. Manually extract $uiArchive to $uiDistDir"
        }

        # Clean up temp files
        Remove-Item $uiArchive, $uiSha256File -ErrorAction SilentlyContinue
    }

    $ProgressPreference = $prevProgress
}

# ============================================================================
# 6. Build llama.cpp (GPU or CPU backend)
# ============================================================================
Write-Step "6/7  Build llama.cpp ($($Backend.ToUpper()) backend)"

$buildDir  = Join-Path $llamaCppDir "build"
$serverExe = Join-Path $buildDir "bin\Release\llama-server.exe"

# Check existing build
$needBuild = $true
if (Test-Path $serverExe) {
    Write-Warn2 "Existing build found: $serverExe"
    $choice = Read-Host "Rebuild? [y/N]"
    if ($choice -notmatch '^[Yy]') {
        $needBuild = $false
        Write-OK "Skipping build, using existing binary"
    }
}

if ($needBuild) {
    if (Test-Path $buildDir) {
        Write-Info "Removing stale build directory: $buildDir"
        Remove-Item -Recurse -Force $buildDir
    }
    Push-Location $llamaCppDir
    try {
        if ($Backend -eq 'gpu') {
            Write-Info "CMake configure ... (CUDA: $cudaRoot)"
            cmake -B build -S . `
                -G "Visual Studio 17 2022" `
                -A x64 `
                -DGGML_CUDA=ON `
                -DCMAKE_CUDA_ARCHITECTURES=native `
                "-DCUDAToolkit_ROOT=$cudaRoot"
        } else {
            Write-Info "CMake configure ... (CPU only)"
            cmake -B build -S . `
                -G "Visual Studio 17 2022" `
                -A x64 `
                -DGGML_CUDA=OFF
        }

        if ($LASTEXITCODE -ne 0) {
            Exit-Script "CMake configure failed (exit $LASTEXITCODE)"
        }
        Write-OK "CMake configure done"

        $cpuCount = [Math]::Min([Environment]::ProcessorCount, 16)
        Write-Info "Building ($cpuCount parallel threads) ..."
        cmake --build build --config Release --parallel $cpuCount

        if ($LASTEXITCODE -ne 0) {
            Exit-Script "Build failed (exit $LASTEXITCODE)"
        }
        Write-OK "Build complete"

        if (-not (Test-Path $serverExe)) {
            Exit-Script "Build output not found: $serverExe"
        }
    } finally {
        Pop-Location
    }
}

# ============================================================================
# 7. Launch server + auto-open browser
# ============================================================================
Write-Step "7/7  Launch XingChen4-29B"

# Check model file (supports sharded *-00001-of-*.gguf)
if (-not (Test-Path $ModelPath)) {
    Write-Warn2 "Model not found: $ModelPath"
    Write-Info "Place GGUF model at the specified path, or enter it below."
    Write-Info "Tip: use HF-Mirror (hfd tool) for 5-10x faster download"
    $ModelPath = Read-Host "Enter model file path (or Ctrl+C to exit)"
    if (-not $ModelPath -or -not (Test-Path $ModelPath)) {
        Exit-Script "Model file does not exist"
    }
}

# Sharded model info
if ($ModelPath -match '-00001-of-\d+\.gguf$') {
    $modelDir  = Split-Path $ModelPath -Parent
    $shardPattern = [System.IO.Path]::GetFileName($ModelPath) -replace '00001-of-\d+', '*'
    $shards = Get-ChildItem $modelDir -Filter $shardPattern -ErrorAction SilentlyContinue
    Write-OK "Sharded model detected, $($shards.Count) files:"
    $shards | ForEach-Object { Write-Info "$($_.Name)  ($([math]::Round($_.Length / 1GB, 2)) GB)" }
}

# Auto-detect static files directory (--path)
# Priority: build output > source tree UI dist
$resolvedStaticPath = $null

if ($StaticPath -and (Test-Path $StaticPath)) {
    $resolvedStaticPath = $StaticPath
    Write-OK "Static files (user-specified): $resolvedStaticPath"
} else {
    $candidates = @(
        (Join-Path $buildDir "bin\Release\public"),
        (Join-Path $buildDir "public"),
        (Join-Path $buildDir "bin\public"),
        (Join-Path $llamaCppDir "tools\ui\dist")
    )

    foreach ($cand in $candidates) {
        if ((Test-Path $cand) -and (Test-Path (Join-Path $cand "index.html"))) {
            $resolvedStaticPath = $cand
            break
        }
    }

    if ($resolvedStaticPath) {
        Write-OK "Static files (auto-detected): $resolvedStaticPath"
    } else {
        Write-Warn2 "Web UI static files not found, --path will use source root"
        Write-Info "Use -StaticPath to specify, or download UI assets from llama.cpp release"
        $resolvedStaticPath = $llamaCppDir
    }
}

# Build server args
$effectiveGpuLayers = if ($Backend -eq 'cpu') { 0 } else { $GpuLayers }

$serverArgs = @(
    "-m", $ModelPath,
    "--path", $resolvedStaticPath,
    "-ngl", $effectiveGpuLayers,
    "-c", $ContextSize,
    "--cache-type-k", "q8_0",
    "--cache-type-v", "q8_0",
    "--host", $HostAddr,
    "--port", $Port
)

# Launch browser after 40s delay (non-blocking, runs in hidden cmd window)
$browserUrl = "http://127.0.0.1:$Port"
Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c", "timeout /t 20 /nobreak >nul & start $browserUrl" `
    -WindowStyle Hidden

Write-OK "Starting API server: http://$($HostAddr):$Port"
Write-Info "Browser will open in 20s: $browserUrl"
Write-Info "Press Ctrl+C to stop`n"

& $serverExe @serverArgs
