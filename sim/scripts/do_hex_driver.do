# Run from project root:
#   vsim -c -do sim/scripts/do_hex_driver.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/hex_driver.sv
vlog -sv sim/tb/tb_hex_driver.sv

vsim -c work.tb_hex_driver
run -all
quit -f
