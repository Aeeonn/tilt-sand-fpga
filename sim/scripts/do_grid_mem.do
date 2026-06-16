# Run from project root:
#   vsim -c -do sim/scripts/do_grid_mem.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/bram_tdp.sv rtl/sand/grid_mem.sv
vlog -sv sim/tb/tb_grid_mem.sv

# altsyncram (bram_tdp) simulation model lives in altera_mf_ver
vsim -c -L altera_mf_ver work.tb_grid_mem
run -all
quit -f
