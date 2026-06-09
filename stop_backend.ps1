# =========================================================================
# ExoCore 后端停止脚本 (stop_backend.ps1)
# -------------------------------------------------------------------------
# 作用：安全停止在后台隐藏运行的 Django 服务 (默认端口 8000)
# =========================================================================

$DjangoPort = 8000
Write-Host "正在寻找占用端口 ${DjangoPort} 的后台进程..."

$connection = Get-NetTCPConnection -LocalPort $DjangoPort -State Listening -ErrorAction SilentlyContinue

if ($connection) {
    $pidToKill = $connection.OwningProcess
    $proc = Get-Process -Id $pidToKill -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "找到进程: $($proc.Name) (PID: $pidToKill)。正在强行终止..." -ForegroundColor Yellow
        Stop-Process -Id $pidToKill -Force
        Write-Host "Django 后端已安全停止。" -ForegroundColor Green
    } else {
        Write-Host "未找到关联的活动进程。" -ForegroundColor Red
    }
} else {
    Write-Host "端口 ${DjangoPort} 未被占用，Django 后端可能已经处于关闭状态。" -ForegroundColor Green
}
EOF
chmod +x ExoCore_Project/stop_backend.ps1
