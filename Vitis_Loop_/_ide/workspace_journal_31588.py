# 2026-09-18T16:01:15.995048900
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

proj = client.get_sys_project(name="theremin_dual_core")

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="App")
comp.build()

status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

vitis.dispose()

