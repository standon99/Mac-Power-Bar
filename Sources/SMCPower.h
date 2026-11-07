#pragma once
// Read-only live sensors. NAN means the sensor is unavailable.
double powerbar_smc_input(void);
double powerbar_smc_system(void);
void powerbar_smc_close(void);
