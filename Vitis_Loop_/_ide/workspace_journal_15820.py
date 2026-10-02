# 2026-07-21T22:52:06.380508400
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.build()

platform = client.get_component(name="platform1")
domain = platform.add_domain(cpu = "ps7_cortexa9_0",os = "standalone",name = "CORE1",display_name = "CORE1",generate_dtb = False)

comp = client.get_component(name="App")
comp.build()

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

proj = client.get_sys_project(name="theremin_dual_core")

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

vitis.dispose()

