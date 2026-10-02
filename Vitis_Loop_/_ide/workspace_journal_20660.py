# 2026-09-19T12:40:49.579417400
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.build()

proj = client.get_sys_project(name="theremin_dual_core")

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

comp = client.get_component(name="App")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

status = platform.build()

comp = client.get_component(name="App")
comp.build()

status = platform.build()

comp.build()

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

status = platform.build()

comp.build()

status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

status = platform.build()

comp.build()

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

status = platform.build()

comp = client.get_component(name="App")
comp.build()

status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

proj.build(comp_name = ["Loop_y_SD", "App"],build_comps = False)

