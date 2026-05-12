package soc_pkg;

    parameter RAM_WORDS = 512;
    parameter NUM_IO    = 2; // Pin 0: LED, Pin 1: Hardware Timer

    parameter MMIO_BASE  = RAM_WORDS * 4;
    
    parameter GPIO_ADDR      = MMIO_BASE + 32'h0;
    parameter TIMER_ADDR     = MMIO_BASE + 32'h4;
    parameter CYCLE_CNT_ADDR = MMIO_BASE + 32'h8;

endpackage