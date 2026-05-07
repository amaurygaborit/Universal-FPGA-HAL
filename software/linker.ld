ENTRY(_start)

SECTIONS {
    /* Adress processor boot */
    . = 0x00000000;

    .text : {
        *(.init)    /* start.S */
        *(.text*)   /* main.c */
        *(.rodata*) /* Constants */
    }
}