# 1 "X:/Tesis/Vitis_Loop_/platform/ps7_cortexa9_1/CORE1/bsp/lop-config.dts"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "X:/Tesis/Vitis_Loop_/platform/ps7_cortexa9_1/CORE1/bsp/lop-config.dts"

/dts-v1/;
/ {
        compatible = "system-device-tree-v1,lop";
        lops {
                lop_0 {
                        compatible = "system-device-tree-v1,lop,load";
                        load = "assists/baremetal_validate_comp_xlnx.py";
                };

                lop_1 {
                    compatible = "system-device-tree-v1,lop,assist-v1";
                    node = "/";
                    outdir = "X:/Tesis/Vitis_Loop_/platform/ps7_cortexa9_1/CORE1/bsp";
                    id = "module,baremetal_validate_comp_xlnx";
                    options = "ps7_cortexa9_1 X:/Xilinx/2025.1/Vitis/data/embeddedsw/lib/sw_services/xilffs_v5_4/src X:/Tesis/Vitis_Loop_/_ide/.wsdata/.repo.yaml";
                };

        };
    };
