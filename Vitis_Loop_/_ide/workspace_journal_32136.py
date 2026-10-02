# 2026-07-21T16:09:41.424007300
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.build()

status = platform.build()

comp = client.get_component(name="Loop_y_SD")
comp.build()

client.delete_component(name="platform")

client.delete_component(name="platform")

vitis.dispose()

