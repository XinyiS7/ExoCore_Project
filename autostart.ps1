# =========================================================================
# ExoCore 自动启动脚本 (autostart.ps1)
# -------------------------------------------------------------------------
# 作用：在 Windows 登录 / 开机后确保 pgvector 容器运行。
#       幂等（多次运行无副作用）。
# 用法：配合 Windows "任务计划程序" 在登录时运行；参见 AUTOSTART_SETUP.md。
# -------------------------------------------------------------------------
# 维护说明：
#   * 若 pgvector 容器名称不是 "exocore-pg"，改下方 $PgContainer。
# =========================================================================

$ErrorActionPreference = 'Continue'

# ---- 可改参数 ----
$PgContainer = 'exocore-pg'
$DockerReadyTimeoutSec = 300   # 最多等 Docker Desktop 5 分钟
# ------------------

$LogPath = Join-Path $PSScriptRoot 'autostart.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    $line | Tee-Object -FilePath $LogPath -Append | Out-Null
    Write-Host $line
}

Write-Log "=========== ExoCore autostart begin ==========="

# ---------------------------------------------------------------
# 1. 等 Docker Desktop 就绪
# ---------------------------------------------------------------
$elapsed = 0
$dockerOk = $false
while ($elapsed -lt $DockerReadyTimeoutSec) {
    $null = & docker info --format '{{.ServerVersion}}' 2>$null
    if ($LASTEXITCODE -eq 0) { $dockerOk = $true; break }
    Start-Sleep -Seconds 5
    $elapsed += 5
    if ($elapsed % 30 -eq 0) { Write-Log "Waiting for Docker Desktop... (${elapsed}s)" }
}
if (-not $dockerOk) {
    Write-Log "Docker Desktop did not become ready within $DockerReadyTimeoutSec seconds. Exiting." 'ERROR'
    exit 1
}
Write-Log "Docker Desktop is ready."

# ---------------------------------------------------------------
# 2. 确保 pgvector 容器运行
# ---------------------------------------------------------------
$pgState = (& docker ps -a --filter "name=^/$PgContainer$" --format "{{.State}}") -join ''
switch ($pgState) {
    'running' {
        Write-Log "pgvector container '$PgContainer' already running."
    }
    '' {
        Write-Log "pgvector container '$PgContainer' NOT FOUND. First-time setup required." 'WARN'
        Write-Log "请先: docker run -d --name exocore-pg --restart unless-stopped -e POSTGRES_PASSWORD=exocore_dev -e POSTGRES_DB=exocore -p 5432:5432 -v pgdata:/var/lib/postgresql/data pgvector/pgvector:pg16" 'WARN'
    }
    default {
        Write-Log "pgvector state was '$pgState'. Starting it..."
        & docker start $PgContainer | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "pgvector started."
        } else {
            Write-Log "Failed to start pgvector." 'ERROR'
        }
    }
}

# ---------------------------------------------------------------
# 3. 健康快照（用于日志排查）
# ---------------------------------------------------------------
Write-Log "Current container status:"
(& docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}') | ForEach-Object { Write-Log $_ }

Write-Log "=========== ExoCore autostart end ==========="
