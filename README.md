# JETI_basic_Heli_Monitor

This lua app provides the following functions:
provide an alram when the compentated battery voltage drops for more the 250ms under a adujustable cell level (default 3.65V)
provide an alram when the BEC voltage dropes for more than 600ms under a definded level -  just to eleminate spikes
provide an alarm when the RX strength or RX Quality is to low
provide an alarm when the RPM is to low, there are 3 levels supported
provide an capacity usage information (20, 40, 60, 75%)

the compentated battery voltage is: measured voltage / cell number + measured current * defined battery Ri

RPM monitor assumes 10s + change time to rampup the RPM from autorotation or motor off
There has to be a little RPM grow until the threshold (level 1..3) is reached

