# Run from project root:
#   vsim -c -do sim/scripts/do_debounce.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/debounce.sv
vlog -sv sim/tb/tb_debounce.sv

vsim -c work.tb_debounce
run -all
quit -f
