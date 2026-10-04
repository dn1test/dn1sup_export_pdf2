# PowerShell Helper: Обновление DN1SUP Export PDF 2 из dev-папки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Запуск обновления DN1SUP Export PDF 2 из: $ScriptDir" -ForegroundColor Cyan

& ruby "$ScriptDir\update_from_dev.rb"
