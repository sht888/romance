# 启动本地网站 + Cloudflare 临时公网隧道，打印可直接发到微信的链接
# 关闭此窗口（或按 Ctrl+C）后公网链接即失效
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path (Split-Path -Parent $root) '.tools'
$cf    = Join-Path $tools 'cloudflared.exe'
$log   = Join-Path $tools 'tunnel.log'
$port  = 8000
$startedServer = $null

if (-not (Test-Path $cf)) {
    Write-Host "找不到 cloudflared.exe，请确认 $tools 目录存在" -ForegroundColor Red
    exit 1
}

# 1. 确保本地 8000 端口服务已启动
$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Host "启动本地网站服务 (端口 $port) ..."
    $startedServer = Start-Process -FilePath 'python' -ArgumentList '-m','http.server',$port `
        -WorkingDirectory $root -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
}

# 2. 启动 Cloudflare 隧道
Write-Host "正在建立公网隧道，请稍候 ..."
Remove-Item $log -ErrorAction SilentlyContinue
$tunnel = Start-Process -FilePath $cf `
    -ArgumentList 'tunnel','--url',"http://localhost:$port",'--no-autoupdate','--protocol','http2' `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
    -WindowStyle Hidden -PassThru

# 3. 从日志中提取公网域名
$url = $null
for ($i = 0; $i -lt 60 -and -not $url; $i++) {
    Start-Sleep -Milliseconds 500
    $text = ''
    foreach ($f in @($log, "$log.err")) {
        if (Test-Path $f) { $text += (Get-Content $f -Raw -ErrorAction SilentlyContinue) }
    }
    $m = [regex]::Match($text, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($m.Success) { $url = $m.Value }
}

if (-not $url) {
    Write-Host "未能获取公网地址，请检查网络后重试。" -ForegroundColor Red
    Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
    if ($startedServer) { Stop-Process -Id $startedServer.Id -Force -ErrorAction SilentlyContinue }
    exit 1
}

# 4. 打印链接
$pages = @(
    @{ Name = '生日祝福（主页面）'; Path = 'HappyBirthday/index.html' },
    @{ Name = '心形文字与鲜花爆炸'; Path = 'love1.html' },
    @{ Name = '爱心动画 2';         Path = 'love2.html' },
    @{ Name = '爱心动画 3';         Path = 'love3.html' },
    @{ Name = '爱心动画 4';         Path = 'love4.html' },
    @{ Name = '雪花爱心破碎';       Path = ([uri]::EscapeDataString('雪花爱心破碎.html')) }
)

Write-Host ''
Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host ' 以下链接已可发到微信（对方手机需联网打开）' -ForegroundColor Magenta
Write-Host '==============================================================' -ForegroundColor Magenta
foreach ($p in $pages) {
    Write-Host ('  {0}  {1}/{2}' -f $p.Name, $url, $p.Path)
}
Write-Host ''
Write-Host " 公网地址：$url" -ForegroundColor Cyan
Write-Host ' 注意：关闭本窗口后链接立即失效；重新运行本脚本会生成新地址。' -ForegroundColor Yellow
Write-Host ' 按 Ctrl+C 停止。'
Write-Host ''

try {
    Wait-Process -Id $tunnel.Id
} finally {
    Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
    if ($startedServer) { Stop-Process -Id $startedServer.Id -Force -ErrorAction SilentlyContinue }
}
