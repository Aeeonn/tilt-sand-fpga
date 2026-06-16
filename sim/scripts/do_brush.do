# Run from project root:
#   vsim -c -do sim/scripts/do_brush.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/brush.sv
vlog -sv sim/tb/tb_brush.sv

vsim -c work.tb_brush
run -all
quit -f
