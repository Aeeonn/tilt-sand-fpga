# Run from project root:
#   vsim -c -do sim/scripts/do_block_rule.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/block_rule.sv
vlog -sv sim/tb/tb_block_rule.sv

vsim -c work.tb_block_rule
run -all
quit -f
