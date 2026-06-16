# Run from project root:
#   vsim -c -do sim/scripts/do_vga_timing.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/vga_timing.sv
vlog -sv +incdir+sim/golden sim/tb/tb_vga_timing.sv

vsim -c work.tb_vga_timing
run -all
quit -f
