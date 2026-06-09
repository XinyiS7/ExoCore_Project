# =========================================================================
# ExoCore 混合本地启动脚本 (hybrid_start.ps1)
# -------------------------------------------------------------------------
# pgvector (Docker) + Django 本地
#
# 用法：
#   启动:  .\hybrid_start.ps1
#   自启:  .\hybrid_start.ps1 -AutoStart
#   关停:  .\hybrid_start.ps1 -Stop
# =========================================================================
param(
    [switch]$AutoStart,       # 自启模式：无交互，启动前等 Docker 就绪
    [switch]$Stop,            # 关停模式：停止 Django + nginx 容器
    [int]$DjangoPort = 8000
)

$ErrorActionPreference = 'Continue'

# ---- 关停模式 ----
if ($Stop) {
    Write-Host "========== ExoCore stop begin =========="

    # Stop Django (kill whatever is listening on $DjangoPort)
    $pidOnPort = (Get-NetTCPConnection -LocalPort $DjangoPort -ErrorAction SilentlyContinue).OwningProcess
    if ($pidOnPort) {
        Stop-Process -Id $pidOnPort -Force
        Write-Host "Django (PID $pidOnPort) 已停止"
    } else {
        Write-Host "Django (端口 ${DjangoPort}) 未在运行"
    }

    # Stop nginx container
    $nginxRunning = & docker ps --filter "name=^/$NginxContainer$" --format "{{.Names}}" 2>$null
    if ($nginxRunning) {
        & docker stop $NginxContainer 2>$null | Out-Null
        Write-Host "nginx 容器已停止"
    } else {
        Write-Host "nginx 容器未在运行"
    }

    Write-Host "========== ExoCore stop end =========="
    exit 0
}

# ---- 路径配置 ----
$ProjectRoot = 'D:\Alicia\ExoCore_Project'
$ExoCoreDir       = Join-Path $ProjectRoot 'ExoCore'
$ExoCoreDesktopDir = Join-Path $ProjectRoot 'ExoCore-Desktop'
$LogPath          = Join-Path $ProjectRoot 'hybrid_start.log'

$PgContainer    = 'exocore-pg'
$NginxContainer = 'exocore-nginx'
$CertDir         = Join-Path $ProjectRoot 'mkcertpem'

# ---- 辅助函数 ----
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    $line | Tee-Object -FilePath $LogPath -Append | Out-Null
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

# ---- Conda 环境探测 ----
function Find-CondaPython {
    $pythonExe = $null

    # 1) 如果已经在 conda 环境里，直接用 python.exe
    $inConda = $env:CONDA_PREFIX -ne $null
    if ($inConda) {
        $candidate = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
        if ($candidate) {
            Write-Log "检测到已激活的 conda 环境: $env:CONDA_PREFIX"
            return $candidate
        }
    }

    # 2) 尝试 conda run
    $condaExe = (Get-Command conda.exe -ErrorAction SilentlyContinue).Source
    if (-not $condaExe) {
        $condaExe = (Get-Command conda -ErrorAction SilentlyContinue).Source
    }
    if ($condaExe) {
        Write-Log "使用 conda run -n exocore_project"
        return "conda:$condaExe"
    }

    # 3) 尝试已知路径
    $knownPaths = @(
        'E:\Conda\envs\exocore_project\python.exe',
        'C:\Users\Alicia\miniconda3\envs\exocore_project\python.exe',
        'C:\Users\Alicia\anaconda3\envs\exocore_project\python.exe'
    )
    foreach ($p in $knownPaths) {
        if (Test-Path $p) { return $p }
    }

    Write-Log "找不到 conda 环境 'exocore_project' 的 python.exe" 'ERROR'
    return $null
}

# ---- 启动 Django ----
function Start-Django {
    param([string]$PythonProvider)

    # 检查端口是否已被占用
    $portInUse = netstat -ano 2>$null | Select-String ":$DjangoPort\s" | Select-String "LISTENING"
    if ($portInUse) {
        Write-Log "端口 ${DjangoPort} 已被占用，跳过 Django 启动" 'WARN'
        return $true
    }

    Write-Log "启动 Django 开发服务器 (127.0.0.1:${DjangoPort})..."

    $managePy = Join-Path $ExoCoreDir 'manage.py'
    $DjangoLog = Join-Path $ProjectRoot 'django_server.log'

    # Delete old log so we start fresh each run.
    Remove-Item $DjangoLog -Force -ErrorAction SilentlyContinue

    # Start-Process forbids redirecting stdout+stderr to the same file, so we
    # use cmd /c which handles "> file 2>&1" natively.  These paths have no
    # spaces → no nested quoting needed, no escaping nightmares.

    if ($PythonProvider -and $PythonProvider.StartsWith('conda:')) {
        $condaExe = $PythonProvider.Substring(6)
        $cmdArgs = "/c $condaExe run -n exocore_project python.exe -u manage.py runserver 127.0.0.1:${DjangoPort} > $DjangoLog 2>&1"
        $proc = Start-Process -FilePath cmd.exe `
            -ArgumentList $cmdArgs `
            -WorkingDirectory $ExoCoreDir `
            -WindowStyle Hidden `
            -PassThru
    } else {
        $cmdArgs = "/c $PythonProvider -u manage.py runserver 127.0.0.1:${DjangoPort} > $DjangoLog 2>&1"
        $proc = Start-Process -FilePath cmd.exe `
            -ArgumentList $cmdArgs `
            -WorkingDirectory $ExoCoreDir `
            -WindowStyle Hidden `
            -PassThru
    }

    Start-Sleep -Seconds 3

    if ($proc.HasExited -and $proc.ExitCode -ne 0) {
        Write-Log "Django 启动失败，退出码: $($proc.ExitCode)" 'ERROR'
        if (Test-Path $DjangoLog) {
            Write-Log "--- django_server.log ---" 'WARN'
            Get-Content $DjangoLog | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }
        }
        return $false
    }

    Write-Log "Django 已启动 (PID $($proc.Id))"
    Write-Log "Django 日志: $DjangoLog"

    return $true
}

# =========================================================================
# 主流程
# =========================================================================
Write-Log "========== ExoCore hybrid start begin =========="

# ---------------------------------------------------------------
# 0. 自启模式：等 Docker Desktop 就绪
# ---------------------------------------------------------------
if ($AutoStart) {
    $timeout = 300
    $elapsed = 0
    $dockerOk = $false
    while ($elapsed -lt $timeout) {
        $null = & docker info --format '{{.ServerVersion}}' 2>$null
        if ($LASTEXITCODE -eq 0) { $dockerOk = $true; break }
        Start-Sleep -Seconds 5
        $elapsed += 5
        if ($elapsed % 30 -eq 0) { Write-Log "等待 Docker Desktop... (${elapsed}s)" }
    }
    if (-not $dockerOk) {
        Write-Log "Docker Desktop ${timeout}s 未就绪" 'ERROR'
        exit 1
    }
    Write-Log "Docker Desktop 就绪"
}

# ---------------------------------------------------------------
# 1. 确保 pgvector 容器运行
# ---------------------------------------------------------------
$pgState = (& docker ps -a --filter "name=^/$PgContainer$" --format "{{.State}}") -join ''
switch ($pgState) {
    'running' {
        Write-Log "pgvector 已在运行"
    }
    '' {
        Write-Log "pgvector 容器不存在！请先创建: docker run -d --name exocore-pg --restart unless-stopped -e POSTGRES_PASSWORD=exocore_dev -e POSTGRES_DB=exocore -p 5432:5432 -v pgdata:/var/lib/postgresql/data pgvector/pgvector:pg16" 'ERROR'
        exit 1
    }
    default {
        Write-Log "pgvector 状态: $pgState，正在启动..."
        & docker start $PgContainer | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "pgvector 启动失败" 'ERROR'
            exit 1
        }
        Write-Log "pgvector 已启动"
    }
}

# ---------------------------------------------------------------
# 2. 探测 Python 并启动 Django
# ---------------------------------------------------------------
$pythonProvider = Find-CondaPython
if (-not $pythonProvider) { exit 1 }

if (-not $AutoStart) {
    $choice = Read-Host "是否启动 Django 后端? [Y/n]"
    if ($choice -eq 'n' -or $choice -eq 'N') {
        Write-Log "跳过 Django 启动（用户选择）"
        Write-Log "========== hybrid start end =========="
        exit 0
    }
}

$djangoOk = Start-Django -PythonProvider $pythonProvider
if (-not $djangoOk) {
    Write-Log "Django 启动失败" 'WARN'
}

# ---------------------------------------------------------------
# 3. 前端构建检查
# ---------------------------------------------------------------
$chatDist = Join-Path $ExoCoreDesktopDir 'packages\chat-core\dist'
if (-not (Test-Path $chatDist)) {
    Write-Log "前端未构建 (chat-core/dist 不存在)" 'WARN'
    if (-not $AutoStart) {
        $buildChoice = Read-Host "是否构建前端? [Y/n]"
        if ($buildChoice -ne 'n' -and $buildChoice -ne 'N') {
            Write-Log "构建前端 (pnpm build)..."
            Push-Location $ExoCoreDesktopDir
            & pnpm build 2>&1 | ForEach-Object { Write-Log $_ }
            Pop-Location
        }
    }
} else {
    Write-Log "前端已构建 (chat-core/dist)"
}

# ---------------------------------------------------------------
# 4. 确保 nginx 容器运行
# ---------------------------------------------------------------
$nginxImage = 'exocore-nginx'
$nginxState = (& docker ps -a --filter "name=^/$NginxContainer$" --format "{{.State}}") -join ''

# Check if image exists (docker images -q returns $null when not found)
$imageCheck = & docker images -q $nginxImage 2>$null
$imageExists = $imageCheck -and $imageCheck.Length -gt 0

if (-not $imageExists) {
    Write-Log "构建 nginx 镜像..."
    Push-Location (Join-Path $ProjectRoot 'nginx')
    & docker build -t $nginxImage . 2>&1 | ForEach-Object { Write-Log $_ }
    Pop-Location
}

switch ($nginxState) {
    'running' {
        Write-Log "nginx 容器已在运行"
    }
    '' {
        Write-Log "nginx 容器不存在，正在创建..."
        & docker run -d --name $NginxContainer `
            --restart unless-stopped `
            -p 8080:80 -p 8443:443 `
            -v "${chatDist}:/usr/share/nginx/html/chat" `
            -v "$(Join-Path $ExoCoreDesktopDir 'packages\chronicle\dist'):/usr/share/nginx/html/chronicle" `
            -v "$(Join-Path $ExoCoreDesktopDir 'packages\council\dist'):/usr/share/nginx/html/council" `
            -v "${CertDir}:/etc/nginx/certs:ro" `
            $nginxImage 2>&1 | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "nginx 容器已创建"
        } else {
            Write-Log "nginx 容器创建失败" 'ERROR'
        }
    }
    default {
        Write-Log "nginx 状态: $nginxState，正在启动..."
        & docker start $NginxContainer | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "nginx 已启动"
        } else {
            Write-Log "nginx 启动失败" 'ERROR'
        }
    }
}

# ---------------------------------------------------------------

# 5. 健康快照

# ---------------------------------------------------------------
Write-Log "当前容器状态:"
(& docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}') | ForEach-Object { Write-Log $_ }

Write-Log "后端:  http://127.0.0.1:${DjangoPort}"
Write-Log ""
Write-Log "前端 (3 个独立 PWA，单端口 + 目录路由):"
Write-Log "  Chat:      http://localhost:8080/chat/      https://localhost:8443/chat/"
Write-Log "  Chronicle: http://localhost:8080/chronicle/  https://localhost:8443/chronicle/"
Write-Log "  Council:   http://localhost:8080/council/    https://localhost:8443/council/"
Write-Log "  (PWA 身份由 manifest id + scope 区分，同一端口可分别安装)"
Write-Log ""
# Detect LAN + Tailscale IPs for mobile access hints
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceAlias -notlike "*Tailscale*" -and $_.PrefixOrigin -ne "WellKnown" -and $_.IPAddress -ne "127.0.0.1"} | Select-Object -First 1).IPAddress
$tailscaleIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Tailscale" -ErrorAction SilentlyContinue).IPAddress
if ($lanIp) {
    Write-Log "局域网 (${lanIp}):"
    Write-Log "  Chat:      https://${lanIp}:8443/chat/"
    Write-Log "  Chronicle: https://${lanIp}:8443/chronicle/"
    Write-Log "  Council:   https://${lanIp}:8443/council/"
}
if ($tailscaleIp) {
    Write-Log "Tailscale (${tailscaleIp}):"
    Write-Log "  Chat:      https://${tailscaleIp}:8443/chat/"
    Write-Log "  Chronicle: https://${tailscaleIp}:8443/chronicle/"
    Write-Log "  Council:   https://${tailscaleIp}:8443/council/"
}
Write-Log ""
Write-Log "修改前端代码后运行:  cd ExoCore-Desktop && pnpm build"
Write-Log "nginx 自动读取新文件，无需重启。"
Write-Log "========== hybrid start end =========="
