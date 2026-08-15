## 100 MHz Onboard System Clock (Pin E3)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_100mhz }];

## Red Reset Button (RESET)
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { rst }];

## 4 Onboard Green LEDs (LD0=H5, LD1=J5, LD2=T9, LD3=T10)
## Tilt control:
##   led_out[3] = LD3 (T10) -> Tilt FORWARD  (acc_x negative)
##   led_out[2] = LD2 (T9)  -> Tilt BACKWARD (acc_x positive)
##   led_out[1] = LD1 (J5)  -> Tilt RIGHT    (acc_y positive)
##   led_out[0] = LD0 (H5)  -> Tilt LEFT     (acc_y negative)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led_out[0] }];
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led_out[1] }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led_out[2] }];
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led_out[3] }];

## I2C Pins (Mapped to PMOD JA Pins 3 & 4)
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { i2c_scl }]; # PMOD JA Pin 3
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { i2c_sda }]; # PMOD JA Pin 4

## 1. Row Connections (PMOD JC Header) -> 1588BS Matrix Row Anodes (Active HIGH)
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[0] }]; # PMOD JC Pin 1  (Row 0 - Top)
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[1] }]; # PMOD JC Pin 2  (Row 1)
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[2] }]; # PMOD JC Pin 3  (Row 2)
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[3] }]; # PMOD JC Pin 4  (Row 3)
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[4] }]; # PMOD JC Pin 7  (Row 4)
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[5] }]; # PMOD JC Pin 8  (Row 5)
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[6] }]; # PMOD JC Pin 9  (Row 6)
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { matrix_rows[7] }]; # PMOD JC Pin 10 (Row 7 - Bottom)

## 2. Column Connections (PMOD JD Header) -> 1588BS Matrix Column Cathodes (Active LOW)
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[0] }]; # PMOD JD Pin 1  (Col 0 - Left)
set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[1] }]; # PMOD JD Pin 2  (Col 1)
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[2] }]; # PMOD JD Pin 3  (Col 2)
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[3] }]; # PMOD JD Pin 4  (Col 3)
set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[4] }]; # PMOD JD Pin 7  (Col 4)
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[5] }]; # PMOD JD Pin 8  (Col 5)
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[6] }]; # PMOD JD Pin 9  (Col 6)
set_property -dict { PACKAGE_PIN G2    IOSTANDARD LVCMOS33 } [get_ports { matrix_cols[7] }]; # PMOD JD Pin 10 (Col 7 - Right)

