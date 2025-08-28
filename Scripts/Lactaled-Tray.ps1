# Lactaled-Tray.ps1 - Icono en bandeja del sistema
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Text = "Lactaled Inventory Service"
$trayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\Windows\System32\cmd.exe") # Temporal

# Menú contextual
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add("Abrir carpeta de inventarios", $null, {
    Invoke-Item "C:\ProgramData\Lactaled\Inventario\"
})
$menu.Items.Add("Ver logs", $null, {
    Invoke-Item "C:\ProgramData\Lactaled\Logs\inventory_service.log"
})
$menu.Items.Add("Salir", $null, {
    $trayIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$trayIcon.ContextMenuStrip = $menu
$trayIcon.Visible = $true

# Mantener la aplicación abierta
[System.Windows.Forms.Application]::Run()