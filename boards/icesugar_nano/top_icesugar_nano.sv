import soc_pkg::*;

module top (
    input  logic clk,
    output logic [NUM_IO-1:0] io_pins
);

    // Power-on reset sequence
    logic resetn = 0;
    logic [7:0] reset_cnt = 0;
    
    always_ff @(posedge clk) begin
        if (reset_cnt != 8'hFF) reset_cnt <= reset_cnt + 1;
        else resetn <= 1'b1;
    end

    // CPU memory bus signals
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic  [3:0] mem_wmask;
    logic [31:0] mem_rdata;
    logic        mem_rstrb;

    // Processor instantiation
    FemtoRV32 cpu (
        .clk       (clk),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wmask (mem_wmask),
        .mem_rdata (mem_rdata),
        .mem_rstrb (mem_rstrb),
        .mem_rbusy (1'b0),
        .mem_wbusy (1'b0), 
        .reset     (resetn)
    );

    // Dynamic address width calculation based on package parameter
    localparam RAM_ADDR_W = $clog2(RAM_WORDS);
    wire [RAM_ADDR_W-1:0] ram_word_addr = mem_addr[RAM_ADDR_W+1:2];

    // Block RAM declaration
    logic [31:0] ram [RAM_WORDS-1:0];
    
    initial begin
        $readmemh("build/blinky_ram.txt", ram);
    end

    // Address decoding using package parameters
    wire is_gpio      = (mem_addr == GPIO_ADDR);
    wire is_timer     = (mem_addr == TIMER_ADDR);
    wire is_cycle_cnt = (mem_addr == CYCLE_CNT_ADDR);

    // Hardware registers
    logic [NUM_IO-1:0] gpio_reg         = 0;
    logic [31:0]       cycle_cnt        = 0;
    logic [31:0]       timer_max_cycles = 0;
    logic [31:0]       timer_cnt        = 0;
    logic              timer_out        = 0;

    // Data routing signals for BRAM inference
    logic [31:0] ram_rdata;
    logic [31:0] mmio_rdata;
    logic        read_is_io;

    always_ff @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;

        // Unconditional BRAM read
        ram_rdata <= ram[ram_word_addr];
        
        // Store address region for output multiplexer
        read_is_io <= (mem_addr >= MMIO_BASE);

        // Read MMIO registers with zero-padding
        if (is_gpio) mmio_rdata <= { {(32-NUM_IO){1'b0}}, gpio_reg };
        else if (is_cycle_cnt) mmio_rdata <= cycle_cnt;
        else mmio_rdata <= 0;

        // Write operations
        if (mem_wmask != 0) begin
            if (mem_addr < MMIO_BASE) begin
                // RAM writes
                if (mem_wmask[0]) ram[ram_word_addr][7:0]   <= mem_wdata[7:0];
                if (mem_wmask[1]) ram[ram_word_addr][15:8]  <= mem_wdata[15:8];
                if (mem_wmask[2]) ram[ram_word_addr][23:16] <= mem_wdata[23:16];
                if (mem_wmask[3]) ram[ram_word_addr][31:24] <= mem_wdata[31:24];
            end else begin
                // MMIO writes
                if (is_gpio)  gpio_reg         <= mem_wdata[NUM_IO-1:0]; 
                if (is_timer) timer_max_cycles <= mem_wdata[31:0];
            end
        end

        // Hardware timer logic
        if (timer_max_cycles > 0) begin
            if (timer_cnt >= timer_max_cycles - 1) begin
                timer_cnt <= 0;
                timer_out <= ~timer_out;
            end else begin
                timer_cnt <= timer_cnt + 1;
            end
        end
    end

    // Final CPU data multiplexer
    assign mem_rdata = read_is_io ? mmio_rdata : ram_rdata;

    // Physical pin assignments
    assign io_pins[0] = ~gpio_reg[0];
    assign io_pins[1] = timer_out;

endmodule