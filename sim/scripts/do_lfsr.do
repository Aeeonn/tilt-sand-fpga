# Run from project root:
#   vsim -c -do sim/scripts/do_lfsr.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/lfsr.sv
vlog -sv sim/tb/tb_lfsr.sv

vsim -c work.tb_lfsr
run -all
quit -f
