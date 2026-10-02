# 2026-04-12T20:54:07.525844700
import vitis

client = vitis.create_client()
client.set_workspace(path="workspace")

platform = client.create_platform_component(name = "platform_for_emu",hw_design = "$COMPONENT_LOCATION/../../HW_emu.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",generate_dtb = True)

vitis.dispose()

