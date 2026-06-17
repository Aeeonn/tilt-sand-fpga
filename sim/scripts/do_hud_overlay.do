# Run from project root:
#   vsim -c -do sim/scripts/do_hud_overlay.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/sand/hud_overlay.sv
vlog -sv sim/tb/tb_hud_overlay.sv

vsim -c work.tb_hud_overlay
run -all
quit -f
