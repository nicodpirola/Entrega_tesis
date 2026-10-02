# 2026-07-22T20:30:26.335077600
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis_Loop_")

platform = client.get_component(name="platform")
status = platform.build()

vitis.dispose()

