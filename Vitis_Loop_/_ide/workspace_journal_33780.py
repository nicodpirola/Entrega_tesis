# 2026-07-21T19:57:53.482729600
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="App")
comp.build()

status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

proj = client.get_sys_project(name="theremin_dual_core")

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../bits/design_1_wrapper2.xsa")

status = platform.build()

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

advanced_options = client.create_advanced_options_dict(dt_overlay="0")

platform = client.create_platform_component(name = "platform1",hw_design = "$COMPONENT_LOCATION/../../bits/design_1_wrapper2.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",generate_dtb = False,advanced_options = advanced_options,compiler = "gcc")

platform = client.get_component(name="platform1")
domain = platform.add_domain(cpu = "ps7_cortexa9_0",os = "standalone",name = "CORE1",display_name = "CORE1",generate_dtb = False)

status = platform.delete_domain(name="CORE1")

domain = platform.add_domain(cpu = "ps7_cortexa9_1",os = "standalone",name = "CORE1",display_name = "CORE1",generate_dtb = False,compiler = "gcc")

domain = platform.get_domain(name="CORE1")

status = domain.set_lib(lib_name="xilffs", path="X:\Xilinx\2025.1\Vitis\data\embeddedsw\lib\sw_services\xilffs_v5_4")

proj = client.get_sys_project(name="theremin_dual_core")

proj = proj.update_platform(platform="$COMPONENT_LOCATION/../platform1/export/platform1/platform1.xpfm")

proj = proj.update_platform(platform="$COMPONENT_LOCATION/../platform1/export/platform1/platform1.xpfm")

vitis.dispose()

