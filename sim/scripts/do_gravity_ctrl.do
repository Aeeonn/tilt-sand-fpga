# Run from project root:
#   vsim -c -do sim/scripts/do_gravity_ctrl.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/gravity_ctrl.sv
vlog -sv sim/tb/tb_gravity_ctrl.sv

vsim -c work.tb_gravity_ctrl
run -all
quit -f
