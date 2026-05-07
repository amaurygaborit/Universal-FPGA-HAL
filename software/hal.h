#ifndef HAL_H
#define HAL_H

#include <stdint.h>

// --- CARTE MÉMOIRE ---
#define ADDR_LEDS  ((volatile uint32_t *) 0x00400000)

// --- FONCTIONS DU HAL ---
static inline void HAL_LED_Set(uint32_t value) {
    *ADDR_LEDS = value;
}

static inline void HAL_Delay(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++) {
        __asm__("nop");
    }
}

#endif