# Run from project root:
#   vsim -c -do sim/scripts/do_margolus_engine.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/lfsr.sv rtl/sand/block_rule_fall.sv rtl/sand/block_rule_settle.sv rtl/sand/block_rule.sv rtl/sand/margolus_engine.sv
vlog -sv sim/tb/tb_margolus_engine.sv

vsim -c work.tb_margolus_engine
run -all
quit -f
