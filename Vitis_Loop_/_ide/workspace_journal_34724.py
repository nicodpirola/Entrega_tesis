# 2026-07-21T16:26:57.465929700
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

comp = client.get_component(name="Loop_y_SD")
status = comp.clean()

status = comp.clean()

status = comp.clean()

status = comp.clean()

advanced_options = client.create_advanced_options_dict(dt_overlay="0")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../bits/design_1_wrapper.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",generate_dtb = False,advanced_options = advanced_options,compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

domain = platform.add_domain(cpu = "ps7_cortexa9_1",os = "standalone",name = "CORE1",display_name = "CORE1",generate_dtb = False,compiler = "gcc")

domain = platform.get_domain(name="CORE1")

status = domain.set_lib(lib_name="xilffs", path="X:\Xilinx\2025.1\Vitis\data\embeddedsw\lib\sw_services\xilffs_v5_4")

status = platform.build()

status = platform.build()

comp.build()

status = platform.build()

comp = client.get_component(name="App")
comp.build()

proj = client.get_sys_project(name="theremin_dual_core")

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

vitis.dispose()

vitis.dispose()

