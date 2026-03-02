vlib work
vlog -f src_files.list +cover
vsim -voptargs=+acc work.testbench -classdebug -uvmcontrol=all -cover
coverage save testbench.ucdb -onexit -du aligner

# ─────────────────────────────────────────────────────────────────────────────
# Waveform setup
# ─────────────────────────────────────────────────────────────────────────────
add wave -divider "CLOCK & RESET"
add wave -label "clk"     testbench/clk
add wave -label "reset_n" testbench/apb_if/preset_n

add wave -divider "APB - Configuration Interface"
add wave -label "psel"    testbench/apb_if/psel
add wave -label "penable" testbench/apb_if/penable
add wave -label "pwrite"  testbench/apb_if/pwrite
add wave -label "paddr"   -hex testbench/apb_if/paddr
add wave -label "pwdata"  -hex testbench/apb_if/pwdata
add wave -label "prdata"  -hex testbench/apb_if/prdata
add wave -label "pready"  testbench/apb_if/pready
add wave -label "pslverr" testbench/apb_if/pslverr

add wave -divider "CTRL Register"
add wave -label "ctrl_size"      testbench/dut/core/regs/ctrl_size
add wave -label "ctrl_offset"    testbench/dut/core/regs/ctrl_offset
add wave -label "ctrl_clr"       testbench/dut/core/regs/ctrl_clr
add wave -label "ctrl_wr_strobe" testbench/dut/core/regs/ctrl_wr_strobe

add wave -divider "MD RX - Unaligned Input"
add wave -label "rx_valid"  testbench/md_rx_if/valid
add wave -label "rx_ready"  testbench/md_rx_if/ready
add wave -label "rx_err"    testbench/md_rx_if/err
add wave -label "rx_data"   -hex testbench/md_rx_if/data
add wave -label "rx_offset" testbench/md_rx_if/offset
add wave -label "rx_size"   testbench/md_rx_if/size

add wave -divider "RX FIFO"
add wave -label "rx_push"  testbench/algn_if/rx_fifo_push
add wave -label "rx_pop"   testbench/algn_if/rx_fifo_pop
add wave -label "rx_lvl"   testbench/dut/core/rx_fifo_2_regs_fifo_lvl
add wave -label "rx_full"  testbench/dut/core/rx_fifo_2_regs_fifo_full
add wave -label "rx_empty" testbench/dut/core/rx_fifo_2_regs_fifo_empty

add wave -divider "Alignment Engine (ctrl.sv)"
add wave -label "pop_valid"            testbench/dut/core/rx_fifo_2_ctrl_pop_valid
add wave -label "pop_ready"            testbench/dut/core/rx_fifo_2_ctrl_pop_ready
add wave -label "pop_data"             -hex testbench/dut/core/rx_fifo_2_ctrl_pop_data
add wave -label "push_valid"           testbench/dut/core/ctrl_2_tx_fifo_push_valid
add wave -label "push_ready"           testbench/dut/core/ctrl_2_tx_fifo_push_ready
add wave -label "push_data"            -hex testbench/dut/core/ctrl_2_tx_fifo_push_data
add wave -label "aligned_bytes_proc"   testbench/dut/core/ctrl/aligned_bytes_processed
add wave -label "unaligned_bytes_proc" testbench/dut/core/ctrl/unaligned_bytes_processed
add wave -label "unaligned_size"       testbench/dut/core/ctrl/unaligned_size
add wave -label "unaligned_data"       -hex testbench/dut/core/ctrl/unaligned_data

add wave -divider "TX FIFO"
add wave -label "tx_push"  testbench/algn_if/tx_fifo_push
add wave -label "tx_pop"   testbench/algn_if/tx_fifo_pop
add wave -label "tx_lvl"   testbench/dut/core/tx_fifo_2_regs_fifo_lvl
add wave -label "tx_full"  testbench/dut/core/tx_fifo_2_regs_fifo_full
add wave -label "tx_empty" testbench/dut/core/tx_fifo_2_regs_fifo_empty

add wave -divider "MD TX - Aligned Output"
add wave -label "tx_valid"  testbench/md_tx_if/valid
add wave -label "tx_ready"  testbench/md_tx_if/ready
add wave -label "tx_err"    testbench/md_tx_if/err
add wave -label "tx_data"   -hex testbench/md_tx_if/data
add wave -label "tx_offset" testbench/md_tx_if/offset
add wave -label "tx_size"   testbench/md_tx_if/size

add wave -divider "IRQ"
add wave -label "irq" testbench/algn_if/irq

wave zoom full
run -all
