# Run from project root:
#   vsim -c -do sim/scripts/do_reset_sync.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/reset_sync.sv
vlog -sv sim/tb/tb_reset_sync.sv

vsim -c work.tb_reset_sync
run -all
quit -f
