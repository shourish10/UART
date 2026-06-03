vlog testbench.sv +acc
vsim tb_uart_top
add wave -r *
run -all
