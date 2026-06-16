# Run from project root:
#   vsim -c -do sim/scripts/do_pll_sys.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/pll_sys.sv
vlog -sv +incdir+sim/golden sim/tb/tb_pll_sys.sv

vsim -c -L altera_mf_ver work.tb_pll_sys
run -all
quit -f
