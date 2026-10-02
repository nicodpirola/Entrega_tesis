$base = $PSScriptRoot

$vivado_bit    = Join-Path $base "Passthrough_v1\Passthrough_v1.runs\impl_1\design_1_wrapper.bit"
$vitis_sys_dir = Join-Path $base "Vitis_Loop_\theremin_dual_core\_ide\bitstream"
$vitis_sys_bit = Join-Path $vitis_sys_dir "design_1_wrapper.bit"
$vitis_app_dir = Join-Path $base "Vitis_Loop_\App\_ide\bitstream"
$vitis_app_bit = Join-Path $vitis_app_dir "design_1_wrapper.bit"
$vitis_plat_dir= Join-Path $base "Vitis_Loop_\platform\hw"
$vitis_plat_bit= Join-Path $vitis_plat_dir "design_1_wrapper1.bit"

Write-Host " INYECTANDO BITSTREAM (BYPASS DE VITIS UI) "

if (Test-Path $vivado_bit) {
    Write-Host "[+] Archivo .bit de Vivado encontrado."
    
    # Inyectar en el System Project original (theremin_dual_core)
    if (Test-Path $vitis_sys_dir) {
        Copy-Item -Path $vivado_bit -Destination $vitis_sys_bit -Force
        Write-Host "[OK] Bitstream inyectado en System Project (theremin_dual_core)."
    }

    # Inyectar en el nuevo proyecto de la Aplicacion (App) para que JTAG lo use
    if (Test-Path $vitis_app_dir) {
        Copy-Item -Path $vivado_bit -Destination $vitis_app_bit -Force
        Write-Host "[OK] Bitstream inyectado en Proyecto App (usado por JTAG)."
    } else {
        Write-Host "[!] No se encontro la carpeta oculta del proyecto App."
    }

    # Inyectar en la Plataforma
    if (Test-Path $vitis_plat_dir) {
        Copy-Item -Path $vivado_bit -Destination $vitis_plat_bit -Force
        Write-Host "[OK] Bitstream inyectado en la Plataforma maestra."
    }

    Write-Host " ACTUALIZACION COMPLETADA"

} else {
    Write-Host "[ERROR]"
}
