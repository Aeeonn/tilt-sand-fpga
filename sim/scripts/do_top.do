# Run from project root:
#   vsim -c -do sim/scripts/do_top.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/reset_sync.sv rtl/platform/pll_sys.sv rtl/platform/vga_timing.sv \
        rtl/platform/hex_driver.sv rtl/platform/debounce.sv \
        rtl/platform/uart_rx.sv rtl/platform/uart_tx.sv \
        rtl/platform/uart_monitor.sv rtl/platform/palette.sv \
        rtl/platform/adxl345_spi.sv rtl/platform/gravity_ctrl.sv \
        rtl/sand/bram_tdp.sv rtl/sand/grid_mem.sv rtl/sand/grid_scanout.sv \
        rtl/sand/lfsr.sv rtl/sand/block_rule.sv rtl/sand/margolus_engine.sv \
        rtl/sand/brush.sv rtl/sand/particle_count.sv rtl/top.sv
vlog -sv +incdir+sim/golden sim/tb/tb_top.sv

# altpll simulation model lives in altera_mf_ver
vsim -c -L altera_mf_ver work.tb_top
run -all
quit -f
