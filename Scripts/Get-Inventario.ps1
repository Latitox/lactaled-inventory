# Configuración inicial
$rutaInventario = "C:\ProgramData\Lactaled\Inventario\"
$nombreArchivo = "inventario_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$rutaCompleta = Join-Path -Path $rutaInventario -ChildPath $nombreArchivo
$logFile = Join-Path -Path $rutaInventario -ChildPath "inventario_log.txt"

# Crear directorio si no existe
if (-not (Test-Path $rutaInventario)) {
    New-Item -ItemType Directory -Path $rutaInventario -Force | Out-Null
}

# Función de logging
function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

try {
    Write-Log "Iniciando proceso de inventario"
    
    # 1. Información básica del equipo
    $serialNumber = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber ?? "No disponible"
    $modelo = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model ?? "No disponible"
    $sistemaOperativo = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption ?? "No disponible"
    $fabricante = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer ?? "No disponible"
    $dominio = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain ?? "No disponible"

    # 2. BIOS (Versión)
    $biosVersion = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SMBIOSBIOSVersion ?? "No disponible"

    # 3. Hardware (RAM, CPU, Discos, Tarjeta de video)
    $systemInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $memoriaGB = if ($systemInfo.TotalPhysicalMemory) { 
        [math]::Round($systemInfo.TotalPhysicalMemory / 1GB, 2) 
    } else { 
        "No disponible" 
    }

    $procesador = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name ?? "No disponible"
    $discos = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Select-Object Model, Size, DeviceID

    # Tarjeta de video
    $gpuInfo = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | 
               Where-Object { $_.Name -notmatch 'Microsoft Basic Display' } |
               Select-Object Name, @{Name="RAM_MB";Expression={if($_.AdapterRAM -gt 0){[math]::Round($_.AdapterRAM/1MB,2)}else{"No disponible"}}}

    # 4. Slots de RAM (Total y disponibles)
    $ramSlots = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1
    $ramModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $totalSlots = if ($ramSlots) { $ramSlots.MemoryDevices } else { "No disponible" }
    $slotsUsados = if ($ramModules) { $ramModules.Count } else { "No disponible" }

    # 5. Red (MACs principales: Ethernet, Wi-Fi, Bluetooth)
    $macAddresses = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | 
        Where-Object { $_.MACAddress -ne $null -and $_.Description -match 'Ethernet|Wi-Fi|Wireless|Bluetooth' } |
        Select-Object -First 3 | 
        ForEach-Object { "[$($_.Description)] MAC: $($_.MACAddress)" }

    # 6. Fecha del último inicio de sesión del usuario actual
    $userLastLogin = "No disponible"
    try {
        $userEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            ID = 4624
            Data = $env:USERNAME
        } -MaxEvents 1 -ErrorAction Stop
        
        if ($userEvents) {
            $userLastLogin = $userEvents[0].TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        }
    } catch {
        try {
            # Método alternativo para sistemas más antiguos
            $userProfile = Get-CimInstance Win32_UserProfile -ErrorAction Stop | 
                Where-Object { $_.LocalPath -like "*$($env:USERNAME)" } |
                Select-Object -First 1
            if ($userProfile -and $userProfile.LastUseTime) {
                $userLastLogin = $userProfile.LastUseTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        } catch {
            Write-Log "No se pudo obtener fecha de último inicio de sesión: $($_.Exception.Message)"
        }
    }

    # Generar contenido del archivo TXT
    $contenido = @"
=== INVENTARIO LACTALED ===
Última sincronización: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Equipo: $($env:COMPUTERNAME)
Usuario: $($env:USERNAME)
Dominio: $dominio
Último inicio de sesión del usuario: $userLastLogin

--- Información General ---
Fabricante: $fabricante
Modelo: $modelo
Número de serie: $serialNumber
Sistema operativo: $sistemaOperativo

--- BIOS ---
Versión: $biosVersion

--- Hardware ---
Procesador: $procesador
RAM total (GB): $memoriaGB
Slots de RAM: $slotsUsados / $totalSlots (usados/total)

Tarjeta de video:
$($gpuInfo | Format-Table -AutoSize | Out-String)

--- Discos ---
$($discos | Format-Table -AutoSize | Out-String)

--- Red (MACs principales) ---
$($macAddresses -join "`n")

--- Software instalado (Top 20) ---
$((Get-CimInstance Win32_Product -ErrorAction SilentlyContinue | Select-Object -First 20 Name, Version | Format-Table -AutoSize | Out-String).Trim())
"@

    # Guardar en archivo TXT
    $contenido | Out-File -FilePath $rutaCompleta -Encoding UTF8 -Force
    Write-Log "Inventario guardado en: $rutaCompleta"

    # Limpiar archivos antiguos (más de 7 días)
    Get-ChildItem -Path $rutaInventario -Filter "inventario_*.txt" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
        Remove-Item -Force -ErrorAction SilentlyContinue

} catch {
    Write-Log "Error durante la ejecución: $($_.Exception.Message)"
}