# Run from project root:
#   vsim -c -do sim/scripts/do_uart_loopback.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/uart_tx.sv
vlog -sv rtl/platform/uart_rx.sv
vlog -sv sim/tb/tb_uart_loopback.sv

vsim -c work.tb_uart_loopback
run -all
quit -f
