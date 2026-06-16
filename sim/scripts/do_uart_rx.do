# Run from project root:
#   vsim -c -do sim/scripts/do_uart_rx.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/uart_rx.sv
vlog -sv sim/tb/tb_uart_rx.sv

vsim -c work.tb_uart_rx
run -all
quit -f
