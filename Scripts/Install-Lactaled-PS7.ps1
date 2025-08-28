# Install-Lactaled-PS7.ps1
param([switch]$Uninstall)

$TaskName = "LactaledInventory"
$InstallPath = "C:\Program Files\Lactaled\InventoryService\"

function Test-PowerShell7 {
    try {
        $ps7 = Get-Command "pwsh.exe" -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Install-Service {
    Write-Host "🔍 Detectando PowerShell 7..." -ForegroundColor Cyan
    
    if (-not (Test-PowerShell7)) {
        Write-Host "❌ PowerShell 7 no está instalado" -ForegroundColor Red
        Write-Host "📥 Descarga desde: https://aka.ms/powershell-release?tag=stable" -ForegroundColor Yellow
        return
    }
    
    Write-Host "✅ PowerShell 7 detectado" -ForegroundColor Green
    
    # Crear directorio de instalación
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }
    
    # Configurar tarea programada con PowerShell 7
    $Action = New-ScheduledTaskAction -Execute "pwsh.exe" `
        -Argument "-ExecutionPolicy Bypass -File `"$InstallPath\Get-Inventario.ps1`""

    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 5)

    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest
        
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Description "Servicio de inventario Lactaled - Ejecución cada 5 minutos (PowerShell 7)" `
        -Force
        
    Write-Host "✅ Tarea programada creada con PowerShell 7" -ForegroundColor Green
    Write-Host "⏰ Se ejecutará cada 5 minutos" -ForegroundColor Cyan
}

function Uninstall-Service {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "✅ Tarea programada eliminada" -ForegroundColor Green
    }
}

# Ejecutar
if ($Uninstall) {
    Uninstall-Service
} else {
    Install-Service
}