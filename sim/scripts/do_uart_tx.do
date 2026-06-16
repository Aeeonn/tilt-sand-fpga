# Run from project root:
#   vsim -c -do sim/scripts/do_uart_tx.do
onerror {quit -f}

if {![file exists sim/work]} {
    vlib sim/work
}
vmap work sim/work

vlog -sv rtl/platform/uart_tx.sv
vlog -sv sim/tb/tb_uart_tx.sv

vsim -c work.tb_uart_tx
run -all
quit -f
