#===================================================================
# basys3_vga.xdc — Pin Constraints for STELLAR VANGUARD
#===================================================================
# Target: Digilent Basys3 (XC7A35T-1CPG236C)
# VERIFY against official Digilent Basys-3-Master.xdc before use!
#   https://github.com/Digilent/digilent-xdc
#===================================================================

#———————————————————————————————————————————————————————————————————
# Clock — 100MHz on-board oscillator
#———————————————————————————————————————————————————————————————————
set_property PACKAGE_PIN W5 [get_ports CLK100MHZ]
set_property IOSTANDARD LVCMOS33 [get_ports CLK100MHZ]
create_clock -period 10.000 -name clk100 [get_ports CLK100MHZ]

#———————————————————————————————————————————————————————————————————
# Push Buttons (active-high when pressed)
#———————————————————————————————————————————————————————————————————
set_property PACKAGE_PIN T18 [get_ports btnU]
set_property PACKAGE_PIN U17 [get_ports btnD]
set_property PACKAGE_PIN W18 [get_ports btnL]
set_property PACKAGE_PIN T17 [get_ports btnR]
set_property PACKAGE_PIN U18 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports {btnU btnD btnL btnR btnC}]

#———————————————————————————————————————————————————————————————————
# VGA Output (12-bit: R[3:0], G[3:0], B[3:0], HS, VS)
# Basys3 uses resistor-ladder DAC
#———————————————————————————————————————————————————————————————————
set_property PACKAGE_PIN G19 [get_ports {VGA_R[0]}]
set_property PACKAGE_PIN H19 [get_ports {VGA_R[1]}]
set_property PACKAGE_PIN J19 [get_ports {VGA_R[2]}]
set_property PACKAGE_PIN N19 [get_ports {VGA_R[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {VGA_R[*]}]

set_property PACKAGE_PIN J17 [get_ports {VGA_G[0]}]
set_property PACKAGE_PIN H17 [get_ports {VGA_G[1]}]
set_property PACKAGE_PIN G17 [get_ports {VGA_G[2]}]
set_property PACKAGE_PIN D17 [get_ports {VGA_G[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {VGA_G[*]}]

set_property PACKAGE_PIN N18 [get_ports {VGA_B[0]}]
set_property PACKAGE_PIN L18 [get_ports {VGA_B[1]}]
set_property PACKAGE_PIN K18 [get_ports {VGA_B[2]}]
set_property PACKAGE_PIN J18 [get_ports {VGA_B[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {VGA_B[*]}]

set_property PACKAGE_PIN P19 [get_ports VGA_HS]
set_property PACKAGE_PIN R19 [get_ports VGA_VS]
set_property IOSTANDARD LVCMOS33 [get_ports {VGA_HS VGA_VS}]

#———————————————————————————————————————————————————————————————————
# 7-Segment Display (common anode, active-low)
#———————————————————————————————————————————————————————————————————
set_property PACKAGE_PIN U2 [get_ports {an[0]}]
set_property PACKAGE_PIN U4 [get_ports {an[1]}]
set_property PACKAGE_PIN V4 [get_ports {an[2]}]
set_property PACKAGE_PIN W4 [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

set_property PACKAGE_PIN W7 [get_ports {seg[0]}]
set_property PACKAGE_PIN W6 [get_ports {seg[1]}]
set_property PACKAGE_PIN U8 [get_ports {seg[2]}]
set_property PACKAGE_PIN V8 [get_ports {seg[3]}]
set_property PACKAGE_PIN U5 [get_ports {seg[4]}]
set_property PACKAGE_PIN V5 [get_ports {seg[5]}]
set_property PACKAGE_PIN U7 [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

#———————————————————————————————————————————————————————————————————
# Status LEDs
#———————————————————————————————————————————————————————————————————
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

#———————————————————————————————————————————————————————————————————
# Slide Switches — sw[0] = manual reset (active high = reset)
#———————————————————————————————————————————————————————————————————
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]

#———————————————————————————————————————————————————————————————————
# Timing constraints
#———————————————————————————————————————————————————————————————————
set_input_delay -clock clk100 -min 1.0 [get_ports {btnU btnD btnL btnR btnC sw[0]}]
set_input_delay -clock clk100 -max 4.0 [get_ports {btnU btnD btnL btnR btnC sw[0]}]
set_output_delay -clock clk100 -min 1.0 [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_output_delay -clock clk100 -max 4.0 [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]

# 整个设计除时钟分频器外都用 tick (25MHz 使能) 驱动
# 每 4 个 100MHz 时钟周期才采一次数据，所以给 4 个周期(40ns)来稳定组合逻辑
# 这解决了 game_engine 巨量组合逻辑的时序问题
set_multicycle_path -setup 4 -from [get_clocks clk100] -to [get_clocks clk100]
set_multicycle_path -hold  3 -from [get_clocks clk100] -to [get_clocks clk100]
