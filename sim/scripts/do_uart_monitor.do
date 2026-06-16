# Run from project root:
#   vsim -c -do sim/scripts/do_uart_monitor.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/uart_monitor.sv
vlog -sv sim/tb/tb_uart_monitor.sv

vsim -c work.tb_uart_monitor
run -all
quit -f
