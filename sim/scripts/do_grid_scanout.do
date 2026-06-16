# Run from project root:
#   vsim -c -do sim/scripts/do_grid_scanout.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/grid_scanout.sv
vlog -sv sim/tb/tb_grid_scanout.sv

vsim -c work.tb_grid_scanout
run -all
quit -f
