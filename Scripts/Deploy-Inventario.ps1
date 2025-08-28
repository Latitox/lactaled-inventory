param(
    [switch]$Uninstall,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"

# Configuración
$TaskName = "LactaledInventory"
$InstallPath = "C:\Program Files\Lactaled\InventoryService\"
$LogPath = "C:\ProgramData\Lactaled\Logs\"

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
    Write-Log "Iniciando instalación del servicio de inventario"
    
    try {
        # Crear directorio de instalación
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            Write-Log "Directorio de instalación creado: $InstallPath"
        }
        
        # Copiar script principal
        Copy-Item -Path ".\Get-Inventario.ps1" -Destination $InstallPath -Force
        Write-Log "Script copiado a $InstallPath"
        
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
        
        Write-Log "Instalación completada exitosamente"
        
    } catch {
        Write-Log "Error durante la instalación: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Uninstall-Service {
    Write-Log "Iniciando desinstalación del servicio de inventario"
    
    try {
        # Detener y eliminar tarea programada
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Tarea programada eliminada"
        }
        
        # Eliminar archivos (opcional, comentar si se quieren conservar datos)
        if (Test-Path $InstallPath) {
            # Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Archivos de aplicación removidos"
        }
        
        Write-Log "Desinstalación completada exitosamente"
        
    } catch {
        Write-Log "Error durante la desinstalación: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Ejecutar instalación/desinstalación
try {
    if ($Uninstall) {
        Uninstall-Service
    } else {
        Install-Service
    }
} catch {
    Write-Log "Error crítico: $($_.Exception.Message)" "ERROR"
    exit 1
}