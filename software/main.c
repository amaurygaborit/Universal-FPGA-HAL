#include "hal.h"

int main() {
    uint32_t state = 0;
    while (1) {
        state = !state;
        HAL_LED_Set(state);     // Abstract method
        HAL_Delay(100000);      // Blink 2 Hz
    }
    return 0;
}