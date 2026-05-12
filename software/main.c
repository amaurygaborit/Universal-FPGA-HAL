#include "hal.h"

// Instantiate the global clock variable
uint32_t SystemCoreClock = 0;

int main() {
    // The iCESugar Nano is 12 MHz
    HAL_Init(12000000);

    // Hardware Timer based on the clock
    HAL_Timer_SetToggleTime_ms(250);

    uint32_t state = 0;
    
    while (1) {
        state = !state;
        
        // LED toggle
        HAL_GPIO_SetBit(0, state);
        
        // Software delay based on the clock
        HAL_Delay_ms(1000);
    }
    
    return 0;
}