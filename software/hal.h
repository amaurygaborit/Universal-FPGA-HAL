#ifndef HAL_H
#define HAL_H

#include <stdint.h>

#define RAM_WORDS    512    // Need to be the same as soc_pgk.sv
#define MMIO_BASE    (RAM_WORDS * 4)

#define ADDR_GPIO      ((volatile uint32_t *) (MMIO_BASE + 0x0))
#define ADDR_TIMER     ((volatile uint32_t *) (MMIO_BASE + 0x4))
#define ADDR_CYCLE_CNT ((volatile uint32_t *) (MMIO_BASE + 0x8))

// Global variable storing the external clock frequency
extern uint32_t SystemCoreClock;

// Initialize the HAL with the provided external clock frequency
static inline void HAL_Init(uint32_t ext_clk_hz) {
    SystemCoreClock = ext_clk_hz;
}

// GPIO Control
static inline void HAL_GPIO_SetBit(uint32_t bit_index, uint32_t state) {
    if (state) {
        *ADDR_GPIO |= (1 << bit_index); 
    } else {
        *ADDR_GPIO &= ~(1 << bit_index); 
    }
}

// Hardware Timer Control based on SystemCoreClock
static inline void HAL_Timer_SetToggleTime_ms(uint32_t ms) {
    uint32_t cycles = (SystemCoreClock / 1000) * ms;
    *ADDR_TIMER = cycles; 
}

// Cycle Counter Read
static inline uint32_t HAL_GetCycleCount(void) {
    return *ADDR_CYCLE_CNT;
}

// Precise software delay based on SystemCoreClock
static inline void HAL_Delay_ms(uint32_t ms) {
    uint32_t cycles_to_wait = (SystemCoreClock / 1000) * ms;
    uint32_t start_time = HAL_GetCycleCount();
    
    while ((HAL_GetCycleCount() - start_time) < cycles_to_wait) {
        __asm__("nop"); 
    }
}

#endif