#Requires -Version 5.1
<#
.SYNOPSIS
    Air780EPM 短信 -> Windows 系统通知（原生 toast，零依赖）
.DESCRIPTION
    轮询服务端 api.php?action=latest，新到的短信用 Windows Action Center 弹通知。
    不开浏览器、后台常驻即可收到短信/来电/通知。纯 Windows 自带能力，无需下载任何东西。
.PARAMETER Url
    接口地址（默认 https://moon9.top/sms/api.php?action=latest&n=50&order=asc）
.PARAMETER Interval
    轮询间隔（秒，默认 10）
.PARAMETER NoSkipHistory
    首跑也弹历史（默认跳过已有，只弹新到的）
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File win_notify.ps1
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File win_notify.ps1   # 静默后台
#>
param(
    [string]$Url = "https://moon9.top/sms/api.php?action=latest&n=50&order=asc",
    [int]$Interval = 10,
    [switch]$NoSkipHistory
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$Base = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Base) { $Base = $PWD }
$SeenFile = Join-Path $Base "sms_seen.json"
$LogFile  = Join-Path $Base "sms_notify.log"

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

function Load-Seen {
    if (Test-Path $SeenFile) {
        try { return [Collections.Generic.HashSet[string]](
            [string[]](Get-Content $SeenFile -Raw -Encoding UTF8 | ConvertFrom-Json)) } catch {}
    }
    return [Collections.Generic.HashSet[string]]::new()
}

function Save-Seen($seen) {
    try { $seen | ConvertTo-Json -Compress | Set-Content -Path $SeenFile -Encoding UTF8 } catch { Log "seen 保存失败: $_" }
}

function Hash-Item($it) {
    $raw = "$($it.time)|$($it.from)|$($it.content)"
    $b = [System.Text.Encoding]::UTF8.GetBytes($raw)
    return [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($b)).Replace("-", "")
}

# ---- 原生 toast 支持（加载 WinRT 类型，首次运行注册 AppId）----
$ToastReady = $false
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
    $appId = "SmsNotify"
    $key = "HKCU:\Software\Classes\AppUserModelId\$appId"
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name "DisplayName" -Value "短信通知" -Force | Out-Null
    }
    $ToastReady = $true
} catch {
    Log "toast 初始化失败（将用弹窗兜底）: $_"
}

function Show-Toast($title, $body) {
    if ($ToastReady) {
        try {
            $t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
            $x = $t.GetElementsByTagName("text")
            $x.Item(0).AppendChild($t.CreateTextNode($title)) | Out-Null
            $x.Item(1).AppendChild($t.CreateTextNode($body)) | Out-Null
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($t)
            return
        } catch {
            Log "toast 失败，弹窗兜底: $_"
        }
    }
    # 兜底：无 WinRT 时用 MessageBox（仍算系统通知）
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($body, $title, "OK", "Information") | Out-Null
    } catch {}
}

$Label = @{ sms = "短信"; call = "来电"; msg = "通知" }

$seen = Load-Seen
$skip = (-not $NoSkipHistory) -and ($seen.Count -eq 0)
if ($skip) { Log "首跑：跳过历史，仅弹新到短信" }
Log "启动，轮询: $Url 间隔 ${Interval}s"

$first = $true
while ($true) {
    try {
        $data = Invoke-RestMethod -Uri $Url -TimeoutSec 15 -Headers @{ "User-Agent" = "SmsWinNotify/1.0" }
        $items = if ($data -and $data.items) { $data.items } else { @() }
    } catch {
        Log "拉取失败: $_"
        Start-Sleep -Seconds $Interval
        continue
    }

    $toToast = @()
    foreach ($it in $items) {
        $h = Hash-Item $it
        if ($seen.Contains($h)) { continue }
        $seen.Add($h) | Out-Null
        if ($first -and $skip) { continue }   # 首跑仅标记历史，不弹
        $toToast += $it
    }
    $first = $false

    foreach ($it in $toToast) {
        $lbl = if ($Label.ContainsKey($it.type)) { $Label[$it.type] } else { "短信" }
        $title = "$lbl · $($it.from)"
        $body = "$($it.content)"
        if ($it.time) { $body = "$body`n$($it.time)" }
        Show-Toast $title $body
        Log "弹通知: $title"
    }

    Save-Seen $seen
    Start-Sleep -Seconds $Interval
}
