module top (
    input  logic clk,
    output logic led_o
);

    // --- SÉQUENCE DE RESET ---
    // FemtoRV32 demande un reset à 0 pour redémarrer, puis à 1 pour tourner.
    logic resetn = 0;
    logic [7:0] reset_cnt = 0;
    always_ff @(posedge clk) begin
        if (reset_cnt != 8'hFF) reset_cnt <= reset_cnt + 1;
        else resetn <= 1'b1;
    end

    // --- BUS MÉMOIRE ---
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic  [3:0] mem_wmask;
    logic [31:0] mem_rdata;
    logic        mem_rstrb;

    // --- INSTANCIATION DU PROCESSEUR ---
    FemtoRV32 cpu (
        .clk       (clk),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wmask (mem_wmask),
        .mem_rdata (mem_rdata),
        .mem_rstrb (mem_rstrb),
        .mem_rbusy (1'b0), // BRAM répond en 1 cycle, donc jamais occupé "longtemps"
        .mem_wbusy (1'b0), 
        .reset     (resetn),
        .error     ()
    );

    // --- MÉMOIRE UNIFIÉE (RAM 2 Ko) & ENTRÉES/SORTIES ---
    // 512 mots de 32 bits = 2048 octets (Utilise les BRAM du FPGA)
    logic [31:0] ram [511:0];
    
    initial begin
        $readmemh("build/blinky_ram.txt", ram);
    end

    // Décodage d'adresse : Si le bit 22 est à 1 (ex: 0x00400000), c'est une I/O
    wire is_io = mem_addr[22];

    always_ff @(posedge clk) begin
        // --- LECTURE SYNCHRONE (1 cycle de latence) ---
        mem_rdata <= ram[mem_addr[10:2]];

        // --- ÉCRITURE EN RAM (Avec gestion des masques d'octets) ---
        if (!is_io) begin
            if (mem_wmask[0]) ram[mem_addr[10:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wmask[1]) ram[mem_addr[10:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wmask[2]) ram[mem_addr[10:2]][23:16] <= mem_wdata[23:16];
            if (mem_wmask[3]) ram[mem_addr[10:2]][31:24] <= mem_wdata[31:24];
        end

        // --- ÉCRITURE VERS LA LED ---
        if (is_io && mem_wmask != 0) begin
            // Sur l'iCESugar Nano, la LED s'allume avec un état BAS (0).
            // Si le code C envoie '1', on inverse pour allumer la LED physiquement.
            led_o <= ~mem_wdata[0];
        end
    end

endmodule