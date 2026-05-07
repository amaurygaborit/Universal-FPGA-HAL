.section .init
.global _start

_start:
    # 2 Ko of RAM
    li sp, 2048

    call main

infinite_loop:
    j infinite_loop