# 2026-08-24T15:06:14.779998
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

proj = client.get_sys_project(name="theremin_dual_core")

proj.build(comp_name = ["App", "Loop_y_SD"],build_comps = False)

vitis.dispose()

