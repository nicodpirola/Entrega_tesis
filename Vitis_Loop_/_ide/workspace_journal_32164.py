# 2026-08-01T13:36:19.949552900
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../bits/design_1_wrapper3.xsa")

status = platform.build()

status = platform.build()

comp = client.get_component(name="App")
comp.build()

client.delete_component(name="platform1")

status = platform.build()

comp.build()

status = platform.build()

comp.build()

vitis.dispose()

