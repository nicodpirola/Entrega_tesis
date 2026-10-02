# 2026-09-10T16:51:46.663688500
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="App")
comp.build()

vitis.dispose()

