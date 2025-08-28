# Configuración inicial
$rutaInventario = "C:\ProgramData\Lactaled\Inventario\"
$nombreArchivo = "inventario_$($env:COMPUTERNAME).txt"
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
    $biosInfo = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $serialNumber = if ($biosInfo -and $biosInfo.SerialNumber) { $biosInfo.SerialNumber } else { "No disponible" }
    
    $systemInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $modelo = if ($systemInfo -and $systemInfo.Model) { $systemInfo.Model } else { "No disponible" }
    $fabricante = if ($systemInfo -and $systemInfo.Manufacturer) { $systemInfo.Manufacturer } else { "No disponible" }
    $dominio = if ($systemInfo -and $systemInfo.Domain) { $systemInfo.Domain } else { "No disponible" }
    
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $sistemaOperativo = if ($osInfo -and $osInfo.Caption) { $osInfo.Caption } else { "No disponible" }

    # 2. BIOS (Versión)
    $biosVersion = if ($biosInfo -and $biosInfo.SMBIOSBIOSVersion) { $biosInfo.SMBIOSBIOSVersion } else { "No disponible" }

    # 3. Hardware (RAM, CPU, Discos, Tarjeta de video)
    $memoriaGB = if ($systemInfo -and $systemInfo.TotalPhysicalMemory) { 
        [math]::Round($systemInfo.TotalPhysicalMemory / 1GB, 2) 
    } else { 
        "No disponible" 
    }

    $procesadorInfo = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $procesador = if ($procesadorInfo -and $procesadorInfo.Name) { $procesadorInfo.Name } else { "No disponible" }
    
    $discos = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Select-Object Model, Size, DeviceID

    # Tarjeta de video
    $gpuInfo = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | 
               Where-Object { $_.Name -notmatch 'Microsoft Basic Display' } |
               Select-Object Name, @{Name="RAM_MB";Expression={if($_.AdapterRAM -gt 0){[math]::Round($_.AdapterRAM/1MB,2)}else{"No disponible"}}}

    # 4. Slots de RAM (Total y disponibles)
    $ramSlots = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1
    $ramModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $totalSlots = if ($ramSlots -and $ramSlots.MemoryDevices) { $ramSlots.MemoryDevices } else { "No disponible" }
    $slotsUsados = if ($ramModules) { $ramModules.Count } else { "No disponible" }

    # 5. Red (MACs principales: Ethernet, Wi-Fi, Bluetooth)
    $macAddresses = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | 
        Where-Object { $_.MACAddress -ne $null -and $_.Description -match 'Ethernet|Wi-Fi|Wireless|Bluetooth' } |
        Select-Object -First 3 | 
        ForEach-Object { "[$($_.Description)] MAC: $($_.MACAddress)" }

    # 6. Información de usuario - Versión simple y confiable
    $currentUser = "No disponible"
    $userLastLogin = "No disponible"

    try {
        # Método 1: Usuario activo de WMI (funciona cuando se ejecuta como SYSTEM)
        $activeUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($activeUser) {
            $currentUser = $activeUser
        } else {
            # Método 2: Usuario de la sesión de consola
            $consoleUser = query session 2>$null | Where-Object { $_ -match '>console\s+Active' }
            if ($consoleUser -and $consoleUser -match '(\w+\\\w+)\s+') {
                $currentUser = $matches[1]
            } else {
                # Método 3: Usuario del sistema
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name + " (Sistema)"
            }
        }
        
        # Obtener último inicio de sesión
        try {
            # Método registry
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
            $lastUser = Get-ItemProperty -Path $regPath -Name "LastLoggedOnUser" -ErrorAction SilentlyContinue
            if ($lastUser -and $lastUser.LastLoggedOnUser) {
                $userLastLogin = $lastUser.LastLoggedOnUser
            }
        } catch {
            Write-Log "No se pudo obtener último usuario desde registry: $($_.Exception.Message)" "WARNING"
        }
        
    } catch {
        $currentUser = "Error obteniendo usuario"
        Write-Log "Error obteniendo información de usuario: $($_.Exception.Message)" "ERROR"
    }

    # Generar contenido del archivo TXT
    $contenido = @"
=== INVENTARIO LACTALED ===
Última sincronización: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Equipo: $($env:COMPUTERNAME)
Usuario activo: $currentUser
Dominio: $dominio
Último inicio de sesión: $userLastLogin

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

    # Guardar en archivo TXT (sobrescribe el existente)
    $contenido | Out-File -FilePath $rutaCompleta -Encoding UTF8 -Force
    Write-Log "Inventario guardado en: $rutaCompleta"

} catch {
    $errorMsg = "Error durante la ejecución: $($_.Exception.Message)"
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $errorMsg" | Out-File -FilePath $logFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        Write-Host $errorMsg
    }
}