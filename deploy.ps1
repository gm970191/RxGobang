# =============================================================================
# deploy.ps1 - Windows 一键发布到 Ubuntu / 宝塔
# =============================================================================
# 请用 PowerShell 7（pwsh），不要用系统自带的 Windows PowerShell 5.1。
# 7.x 默认按 UTF-8 解析脚本，不需要 UTF-8 BOM。
#
# 在项目根目录执行：
#   pwsh -File .\deploy.ps1
#
# 常用参数：
#   -DryRun         只打包暂存，不上传
#   -SetupKey       把本机 SSH 公钥装到服务器，以后免密
#   -SkipRestart    只传文件，不重启进程
#
# 配置写在 deploy.env（不要提交）。默认发布到：
#   root@47.97.245.103:/www/wwwroot/RxGobang8003   端口 8003
# =============================================================================

#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SetupKey,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Write-Info {
    param([string]$Message)
    Write-Host ('[info] ' + $Message)
}

function Raise-DeployError {
    param([string]$Message)
    throw ('[error] ' + $Message)
}

function Get-CleanText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return $Text.Replace("`r", "").Replace("`n", "").Trim()
}

function Quote-BashSingle {
    param([string]$Value)
    $clean = Get-CleanText $Value
    return ("'" + $clean.Replace("'", "'\''") + "'")
}

function Read-DeployEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Get-Content -Path $Path -Encoding utf8NoBOM | ForEach-Object {
        $line = Get-CleanText $_
        if (-not $line -or $line.StartsWith("#") -or ($line -notmatch "=")) { return }
        $key, $val = $line.Split("=", 2)
        $key = Get-CleanText $key
        $val = (Get-CleanText $val).Trim("'").Trim('"')
        Set-Item -Path "Env:$key" -Value $val
    }
}

Read-DeployEnv (Join-Path $Root "deploy.env")

$HostName = Get-CleanText $(if ($env:DEPLOY_HOST) { $env:DEPLOY_HOST } else { "47.97.245.103" })
$UserName = Get-CleanText $(if ($env:DEPLOY_USER) { $env:DEPLOY_USER } else { "root" })
$RemotePath = Get-CleanText $(if ($env:DEPLOY_PATH) { $env:DEPLOY_PATH } else { "/www/wwwroot/RxGobang8003" })
$SshPort = Get-CleanText $(if ($env:DEPLOY_SSH_PORT) { $env:DEPLOY_SSH_PORT } else { "22" })
$AppPort = Get-CleanText $(if ($env:APP_PORT) { $env:APP_PORT } else { "8003" })
$Password = Get-CleanText $(if ($env:DEPLOY_PASS) { $env:DEPLOY_PASS } else { "" })
$Remote = "${UserName}@${HostName}"
$SiteUrl = "https://${HostName}:${AppPort}/"

Write-Info ("target  {0}:{1}" -f $Remote, $SshPort)
Write-Info ("path    {0}" -f $RemotePath)
Write-Info ("url     {0}" -f $SiteUrl)

foreach ($cmd in @("ssh", "scp", "tar")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Raise-DeployError ("找不到命令 {0}。请在 Windows 可选功能里启用 OpenSSH 客户端。" -f $cmd)
    }
}

$script:AskPassFile = $null
$script:UsePassword = $false
$stage = $null
$tarball = $null

function Clear-AskPass {
    if ($script:AskPassFile -and (Test-Path $script:AskPassFile)) {
        Remove-Item -Force $script:AskPassFile -ErrorAction SilentlyContinue
    }
    Remove-Item Env:SSH_ASKPASS -ErrorAction SilentlyContinue
    Remove-Item Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
}

function Enable-PasswordAuth {
    if (-not $Password) {
        Raise-DeployError "密钥登录失败，且 deploy.env 里没有 DEPLOY_PASS"
    }
    $ask = Join-Path $env:TEMP ("rxgobang-askpass-{0}.cmd" -f [guid]::NewGuid().ToString("n"))
    $esc = $Password.Replace("%", "%%")
    Set-Content -Path $ask -Value "@echo off`r`necho $esc" -Encoding ASCII -NoNewline
    $script:AskPassFile = $ask
    $env:SSH_ASKPASS = $ask
    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY = "localhost:0"
    $script:UsePassword = $true
}

function Get-SshArgs {
    $opts = @(
        "-p", $SshPort,
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ServerAliveInterval=30",
        "-o", "ConnectTimeout=12"
    )
    if ($script:UsePassword) {
        $opts += @(
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1"
        )
    }
    return $opts
}

function Invoke-Remote {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteCommand,
        [switch]$IgnoreFailure
    )
    $cmd = Get-CleanText $RemoteCommand
    $sshArgs = (Get-SshArgs) + @("-o", "RequestTTY=no", $Remote, "--", $cmd)
    if ($IgnoreFailure) {
        & ssh @sshArgs 1>$null 2>$null
    } else {
        & ssh @sshArgs
    }
    if (-not $IgnoreFailure -and $LASTEXITCODE -ne 0) {
        Raise-DeployError ("远程命令失败 (exit {0}): {1}" -f $LASTEXITCODE, $cmd)
    }
    return $LASTEXITCODE
}

function Test-SshKeyLogin {
    $probe = @(
        "-p", $SshPort,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8",
        "-o", "StrictHostKeyChecking=accept-new",
        $Remote, "true"
    )
    & ssh @probe 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

try {
    if (-not $DryRun) {
        if (Test-SshKeyLogin) {
            Write-Info "SSH 密钥登录成功"
        } else {
            Enable-PasswordAuth
            Write-Info "使用密码登录（建议随后执行 -SetupKey 改为免密）"
        }
    }

    if ($SetupKey) {
        $sshDir = Join-Path $env:USERPROFILE ".ssh"
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir | Out-Null
        }
        $key = Join-Path $sshDir "id_ed25519"
        $pub = "$key.pub"
        if (-not (Test-Path $pub)) {
            Write-Info ("生成本机 SSH 密钥: {0}" -f $key)
            & ssh-keygen -t ed25519 -N "" -f $key
            if ($LASTEXITCODE -ne 0) { Raise-DeployError "ssh-keygen 失败" }
        }
        $pubText = Get-CleanText (Get-Content -Raw $pub)
        Write-Info ("安装公钥到 {0}:~/.ssh/authorized_keys" -f $Remote)
        $install = ('mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF {0} ~/.ssh/authorized_keys || echo {0} >> ~/.ssh/authorized_keys' -f (Quote-BashSingle $pubText))
        Invoke-Remote $install
        Write-Info "完成。之后可把 deploy.env 里的 DEPLOY_PASS 删掉。"
        return
    }

    $index = Join-Path $Root "index.html"
    $servePy = Join-Path $Root "serve.py"
    if (-not (Test-Path $index)) {
        Raise-DeployError "找不到 index.html"
    }
    if (-not (Test-Path $servePy)) {
        Raise-DeployError "找不到 serve.py"
    }

    $stage = Join-Path $env:TEMP ("rxgobang-stage-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item (Join-Path $Root "index.html") (Join-Path $stage "index.html")
    Copy-Item (Join-Path $Root "start.sh") (Join-Path $stage "start.sh")
    Copy-Item (Join-Path $Root "serve.py") (Join-Path $stage "serve.py")
    $service = Join-Path $Root "rxgobang.service"
    if (Test-Path $service) {
        Copy-Item $service (Join-Path $stage "rxgobang.service")
    }
    Copy-Item -Recurse -Force (Join-Path $Root "css") (Join-Path $stage "css")
    Copy-Item -Recurse -Force (Join-Path $Root "js") (Join-Path $stage "js")
    Remove-Item -Force (Join-Path $stage "js/pwa.js") -ErrorAction SilentlyContinue
    $iconDir = Join-Path $stage "icons"
    New-Item -ItemType Directory -Path $iconDir | Out-Null
    Get-ChildItem (Join-Path $Root "icons") -File -Filter "*.png" | Where-Object {
        $_.Name -ne "icon-source.png"
    } | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $iconDir $_.Name)
    }

    Write-Info "将上传: start.sh, serve.py, index.html, css/, js/, icons/"
    Write-Info "不会上传: deploy.env, .git, logs, certs"

    if ($DryRun) {
        Write-Host ('[dry-run] 暂存目录: ' + $stage)
        Get-ChildItem $stage -Recurse -File | ForEach-Object {
            Write-Host ("  " + $_.FullName.Substring($stage.Length))
        }
        Write-Host '[dry-run] 未连接服务器，退出'
        return
    }

    $tarball = Join-Path $env:TEMP ("rxgobang-deploy-" + [guid]::NewGuid().ToString("n") + ".tgz")
    Write-Info "打包暂存目录 ..."
    & tar -czf $tarball -C $stage .
    if ($LASTEXITCODE -ne 0) { Raise-DeployError "tar 打包失败" }

    $remoteTar = "/tmp/rxgobang-deploy.tgz"
    Write-Info "上传压缩包 ..."
    $scpArgs = @(
        "-P", $SshPort,
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=12"
    )
    if ($script:UsePassword) {
        $scpArgs += @(
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1"
        )
    }
    $scpArgs += @($tarball, "${Remote}:${remoteTar}")
    & scp @scpArgs
    if ($LASTEXITCODE -ne 0) { Raise-DeployError "scp 上传失败" }

    Write-Info "远程解压（不覆盖 logs / pid）..."
    $extract = @(
        ("mkdir -p {0}" -f (Quote-BashSingle $RemotePath))
        ("tar -xzf {0} -C {1}" -f (Quote-BashSingle $remoteTar), (Quote-BashSingle $RemotePath))
        ("rm -f {0}" -f (Quote-BashSingle $remoteTar))
        ('sed -i ''s/\r$//'' {0} {1}' -f (Quote-BashSingle "$RemotePath/start.sh"), (Quote-BashSingle "$RemotePath/serve.py"))
        ("chmod +x {0} {1}" -f (Quote-BashSingle "$RemotePath/start.sh"), (Quote-BashSingle "$RemotePath/serve.py"))
        ("rm -f {0} {1} {2}" -f (Quote-BashSingle "$RemotePath/sw.js"), (Quote-BashSingle "$RemotePath/manifest.json"), (Quote-BashSingle "$RemotePath/js/pwa.js"))
    ) -join " && "
    Invoke-Remote $extract

    if ($SkipRestart) {
        Write-Info ("已跳过重启。文件已上传到 {0}" -f $RemotePath)
        return
    }

    Write-Info "检查远程 Python / curl ..."
    $ensurePy = 'command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || (export DEBIAN_FRONTEND=noninteractive; apt-get update -y && apt-get install -y python3 curl)'
    Invoke-Remote $ensurePy

    Write-Info "重启服务 ..."
    $startSh = Quote-BashSingle "$RemotePath/start.sh"
    $restart = ('bash {0} --stop >/dev/null 2>&1 || true; if [ -f {1} ] && [ -f {2} ]; then CERT_IP={3} bash {0} --daemon; else CERT_IP={3} bash {0} --issue-le; fi' -f $startSh, (Quote-BashSingle "$RemotePath/certs/server.crt"), (Quote-BashSingle "$RemotePath/certs/server.key"), (Quote-BashSingle $HostName))
    Invoke-Remote $restart

    Write-Info ("检查防火墙是否放行 {0} 和 443 ..." -f $AppPort)
    $openFw = ('(command -v ufw >/dev/null 2>&1 && ufw allow {0}/tcp && ufw allow 443/tcp) || (command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --permanent --add-port={0}/tcp && firewall-cmd --permanent --add-port=443/tcp && firewall-cmd --reload) || true' -f $AppPort)
    Invoke-Remote $openFw

    Write-Info "等待进程起来 ..."
    $healthPy = "import ssl,urllib.request; ctx=ssl._create_unverified_context(); urllib.request.urlopen('https://127.0.0.1:${AppPort}/', context=ctx, timeout=3).read(32)"
    $healthCmd = ('python3 -c {0}' -f (Quote-BashSingle $healthPy))
    $healthy = $false
    for ($i = 0; $i -lt 10; $i++) {
        $code = Invoke-Remote -RemoteCommand $healthCmd -IgnoreFailure
        if ($code -eq 0) {
            $healthy = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $healthy) {
        Write-Host '[error] 健康检查失败。最近日志：'
        try {
            Invoke-Remote ('tail -n 40 {0} 2>/dev/null || echo no-log' -f (Quote-BashSingle "$RemotePath/logs/rxgobang.log"))
        } catch {}
        Raise-DeployError ("部署后网站没有响应 {0}" -f $SiteUrl)
    }

    Write-Host ('[done] 部署完成  ' + $SiteUrl)
    try { Invoke-Remote ('bash {0} --status' -f (Quote-BashSingle "$RemotePath/start.sh")) } catch {}
}
finally {
    Clear-AskPass
    if ($stage -and (Test-Path $stage)) {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }
    if ($tarball -and (Test-Path $tarball)) {
        Remove-Item -Force $tarball -ErrorAction SilentlyContinue
    }
}
