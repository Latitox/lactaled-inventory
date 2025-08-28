# REQUIERE EJECUCIÓN COMO ADMINISTRADOR
param([switch]$Uninstall, [switch]$Silent)

$TaskName = "LactaledInventory"
$InstallPath = "C:\Program Files\Lactaled\InventoryService\"
$InventoryPath = "C:\ProgramData\Lactaled\Inventario\"
$LogPath = "C:\ProgramData\Lactaled\Logs\"

# Función para mostrar notificación de bandeja
function Show-TrayNotification {
    param([string]$Message, [string]$Title = "Lactaled Inventory")
    
    # Crear notificación temporal
    $null = [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.Visible = $true
    $notify.ShowBalloonTip(3000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Seconds 4
    $notify.Dispose()
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp [$Level] $Message"
    
    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $LogMessage | Out-File -FilePath "$LogPath\inventory_service.log" -Append -Encoding UTF8
    
    if (-not $Silent) {
        Write-Host $LogMessage
    }
}

function Install-Service {
    Write-Log "Iniciando instalación completa de Lactaled Inventory"
    
    try {
        # Crear directorios
        @($InstallPath, $InventoryPath, $LogPath) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
                Write-Log "Directorio creado: $_"
            }
        }
        
        # Descargar script principal desde GitHub
        $ScriptUrl = "https://raw.githubusercontent.com/Latitox/lactaled-inventory/main/Scripts/Get-Inventario.ps1"
        try {
            Invoke-WebRequest -Uri $ScriptUrl -OutFile "$InstallPath\Get-Inventario.ps1"
            Write-Log "Script descargado desde GitHub"
        } catch {
            Write-Log "Error descargando script: $($_.Exception.Message)" "WARNING"
            Write-Log "Usando script local si existe..."
        }
        
        # Verificar que el script existe
        if (-not (Test-Path "$InstallPath\Get-Inventario.ps1")) {
            throw "No se pudo obtener el script de inventario"
        }
        
        # Crear tarea programada
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" `
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
        
        # Registrar tarea
        Register-ScheduledTask -TaskName $TaskName `
            -Action $Action `
            -Trigger $Trigger `
            -Principal $Principal `
            -Settings $Settings `
            -Description "Servicio de inventario Lactaled - Ejecución cada 5 minutos" `
            -Force
            
        Write-Log "Tarea programada creada exitosamente"
        
        # Ejecutar inmediatamente
        Start-ScheduledTask -TaskName $TaskName
        Write-Log "Primera ejecución iniciada"
        
        # Mostrar notificación
        if (-not $Silent) {
            Show-TrayNotification "Lactaled Inventory se instaló correctamente. Se ejecutará cada 5 minutos."
        }
        
        Write-Log "Instalación completada exitosamente"
        Write-Host "`n✅ ¡INSTALACIÓN COMPLETADA!" -ForegroundColor Green
        Write-Host "📁 Inventarios: $InventoryPath" -ForegroundColor Cyan
        Write-Host "📋 Logs: $LogPath\inventory_service.log" -ForegroundColor Cyan
        Write-Host "⏰ Se ejecutará automáticamente cada 5 minutos" -ForegroundColor Cyan
        
    } catch {
        Write-Log "Error durante la instalación: $($_.Exception.Message)" "ERROR"
        if (-not $Silent) {
            Show-TrayNotification "Error en instalación: $($_.Exception.Message)" "Lactaled Error"
        }
        throw
    }
}

function Uninstall-Service {
    Write-Log "Iniciando desinstalación"
    
    try {
        # Detener y eliminar tarea programada
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Tarea programada eliminada"
        }
        
        # Mostrar notificación
        if (-not $Silent) {
            Show-TrayNotification "Lactaled Inventory se desinstaló correctamente"
        }
        
        Write-Log "Desinstalación completada exitosamente"
        Write-Host "`n✅ ¡DESINSTALACIÓN COMPLETADA!" -ForegroundColor Green
        
    } catch {
        Write-Log "Error durante la desinstalación: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Verificar administrador
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ Este script requiere permisos de administrador." -ForegroundColor Red
    Write-Host "💡 Abre PowerShell como Administrador y vuelve a ejecutar" -ForegroundColor Yellow
    exit 1
}

# Ejecutar instalación/desinstalación
try {
    if ($Uninstall) {
        Uninstall-Service
    } else {
        Install-Service
    }
} catch {
    Write-Host "❌ Error crítico: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}