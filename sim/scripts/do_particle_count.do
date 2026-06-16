# Run from project root:
#   vsim -c -do sim/scripts/do_particle_count.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/particle_count.sv
vlog -sv sim/tb/tb_particle_count.sv

vsim -c work.tb_particle_count
run -all
quit -f
