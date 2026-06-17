# Run from project root:
#   vsim -c -do sim/scripts/do_adxl345_spi.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/adxl345_spi.sv
vlog -sv sim/tb/tb_adxl345_spi.sv

vsim -c work.tb_adxl345_spi
run -all
quit -f
