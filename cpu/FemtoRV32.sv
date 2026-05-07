/*******************************************************************/
// FemtoRV32, a minimalistic RISC-V RV32I core.
// Single-file, self-contained SystemVerilog version.
/*******************************************************************/

`ifndef NRV_RESET_ADDR
 `define NRV_RESET_ADDR 32'b0
`endif

module FemtoRV32(
   input  logic        clk,

   output logic [31:0] mem_addr,  
   output logic [31:0] mem_wdata, 
   output logic  [3:0] mem_wmask, 
   input  logic [31:0] mem_rdata, 
   output logic        mem_rstrb, 
   input  logic        mem_rbusy, 
   input  logic        mem_wbusy, 

   input  logic        reset,     
   output logic        error      
);

   parameter RESET_ADDR = `NRV_RESET_ADDR; 
   assign error = 1'b0;                          

   // --- Instruction decoding ---
   logic [31:0] instr; 

   wire [4:0] rd  = instr[11:7];
   wire [4:0] rs1 = instr[19:15];
   wire [4:0] rs2 = instr[24:20];
   
   wire [2:0] funct3 = instr[14:12];

   wire [31:0] Uimm = {    instr[31],   instr[30:12], {12{1'b0}}};
   wire [31:0] Iimm = {{21{instr[31]}}, instr[30:20]};
   wire [31:0] Simm = {{21{instr[31]}}, instr[30:25], instr[11:7]};
   wire [31:0] Bimm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
   wire [31:0] Jimm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

   logic isLoad, isALUimm, isAUIPC, isStore, isALUreg, isLUI,  isBranch, isJALR, isJAL;
   
   always_ff @(posedge clk) begin 
      isLoad    <=  (instr[6:2] == 5'b00000); 
      isALUimm  <=  (instr[6:2] == 5'b00100); 
      isAUIPC   <=  (instr[6:2] == 5'b00101); 
      isStore   <=  (instr[6:2] == 5'b01000); 
      isALUreg  <=  (instr[6:2] == 5'b01100); 
      isLUI     <=  (instr[6:2] == 5'b01101); 
      isBranch  <=  (instr[6:2] == 5'b11000); 
      isJALR    <=  (instr[6:2] == 5'b11001); 
      isJAL     <=  (instr[6:2] == 5'b11011); 
   end

   wire isALU = isALUimm | isALUreg;
   
   // --- Register file ---
   logic [31:0] rs1Data;
   logic [31:0] rs2Data;
   logic [31:0] registerFile [31:0];
   logic writeBack;       
   logic [31:0] writeBackData; 

   always_ff @(posedge clk) begin
     rs1Data <= registerFile[rs1];
     rs2Data <= registerFile[rs2];
     if (writeBack)
       if (rd != 0)
         registerFile[rd] <= writeBackData;
   end

   // --- ALU ---
   wire [31:0] aluIn1 = rs1Data;
   wire [31:0] aluIn2 = isALUreg | isBranch ? rs2Data : (instr[6:5] == 2'b01 ? Simm : Iimm);

   logic [31:0] aluOut; 
   logic [31:0] aluReg;          
   logic [4:0]  aluShamt;        

   assign aluOut = aluReg;

   wire aluBusy = |aluShamt;   
   logic aluWr;                

   wire [31:0] aluPlus = aluIn1 + aluIn2;
   wire [32:0] aluMinus = {1'b1, ~aluIn2} + {1'b0,aluIn1} + 33'b1;
   wire        LT  = (aluIn1[31] ^ aluIn2[31]) ? aluIn1[31] : aluMinus[32];
   wire        LTU = aluMinus[32];
   wire        EQ  = (aluMinus[31:0] == 0);

   always_ff @(posedge clk) begin
      if(aluWr) begin
         case(funct3) 
            3'b000: aluReg <= instr[30] & instr[5] ? aluMinus[31:0] : aluPlus;
            3'b010: aluReg <= {31'b0, LT} ;                                    
            3'b011: aluReg <= {31'b0, LTU};                                    
            3'b100: aluReg <= aluIn1 ^ aluIn2;                                 
            3'b110: aluReg <= aluIn1 | aluIn2;                                 
            3'b111: aluReg <= aluIn1 & aluIn2;                                 
            3'b001, 3'b101: begin aluReg <= aluIn1; aluShamt <= aluIn2[4:0]; end 
         endcase
      end else begin
         if (|aluShamt) begin
            aluShamt <= aluShamt - 1;
            aluReg <= funct3[2] ? {instr[30] & aluReg[31], aluReg[31:1]} : aluReg << 1 ;
         end
      end
   end

   // --- Branch Predicate ---
   logic predicate; 
   always_ff @(posedge clk) begin
      case(funct3)
        3'b000: predicate <=  EQ;   
        3'b001: predicate <= !EQ;   
        3'b100: predicate <=  LT;   
        3'b101: predicate <= !LT;   
        3'b110: predicate <=  LTU;  
        3'b111: predicate <= !LTU;  
        default: predicate <= 1'bx; 
      endcase
   end

   // --- Program Counter ---
   logic [31:0] PC;         
   
   wire [31:0] PCplus4 = PC + 4;
   wire [31:0] PCplusImm = PC + (instr[3] ? Jimm : instr[4] ? Uimm : Bimm);

   // --- WriteBack Data ---
   wire [31:0] LOAD_data; 

   assign writeBackData  =
      (isLUI               ? Uimm         : 32'b0) |  
      (isALU               ? aluOut       : 32'b0) |  
      (isAUIPC             ? PCplusImm    : 32'b0) |  
      (isJALR   | isJAL    ? PCplus4      : 32'b0) |  
      (isLoad              ? LOAD_data    : 32'b0);   

   // --- LOAD/STORE ---
   wire mem_byteAccess     =  funct3[1:0] == 2'b00;
   wire mem_halfwordAccess =  funct3[1:0] == 2'b01;

   wire LOAD_signedAccess   = !funct3[2];
   wire LOAD_sign = LOAD_signedAccess & (mem_byteAccess ? LOAD_byte[7] : LOAD_halfword[15]);

   assign LOAD_data =
         mem_byteAccess ? {{24{LOAD_sign}},     LOAD_byte} :
     mem_halfwordAccess ? {{16{LOAD_sign}}, LOAD_halfword} :
                          mem_rdata ;
   
   wire [15:0] LOAD_halfword = mem_addr[1] ? mem_rdata[31:16]    : mem_rdata[15:0];
   wire  [7:0] LOAD_byte     = mem_addr[0] ? LOAD_halfword[15:8] : LOAD_halfword[7:0];
   
   assign mem_wdata[ 7: 0] =               rs2Data[7:0];
   assign mem_wdata[15: 8] = mem_addr[0] ? rs2Data[7:0] :                               rs2Data[15: 8];
   assign mem_wdata[23:16] = mem_addr[1] ? rs2Data[7:0] :                               rs2Data[23:16];
   assign mem_wdata[31:24] = mem_addr[0] ? rs2Data[7:0] : mem_addr[1] ? rs2Data[15:8] : rs2Data[31:24];
   
   wire [3:0] STORE_wmask =
       mem_byteAccess ? (mem_addr[1] ? (mem_addr[0] ? 4'b1000 : 4'b0100) :   (mem_addr[0] ? 4'b0010 : 4'b0001) ) :
   mem_halfwordAccess ? (mem_addr[1] ?                4'b1100            :                  4'b0011            ) :
                                                      4'b1111;
                        
   // --- State Machine ---
   typedef enum logic [7:0] {
      FETCH_INSTR     = 8'b00000001,
      WAIT_INSTR      = 8'b00000010,
      FETCH_REGS      = 8'b00000100,
      EXECUTE         = 8'b00001000,
      LOAD            = 8'b00010000,
      WAIT_ALU_OR_MEM = 8'b00100000,
      STORE           = 8'b01000000,
      ALU             = 8'b10000000
   } fsm_state_t;

   fsm_state_t state;

   localparam FETCH_INSTR_bit     = 0;
   localparam WAIT_INSTR_bit      = 1;
   localparam FETCH_REGS_bit      = 2;
   localparam EXECUTE_bit         = 3;
   localparam LOAD_bit            = 4;
   localparam WAIT_ALU_OR_MEM_bit = 5;
   localparam STORE_bit           = 6;
   localparam ALU_bit             = 7;   

   assign writeBack = ~(isBranch | isStore ) & (state[EXECUTE_bit] | state[WAIT_ALU_OR_MEM_bit]);
   assign mem_rstrb = state[LOAD_bit] | state[FETCH_INSTR_bit];
   assign mem_wmask = {4{state[STORE_bit]}} & STORE_wmask; 
   assign aluWr = state[ALU_bit] & isALU;

   wire jumpToPCplusImm = isJAL | (isBranch & predicate);

   always_ff @(posedge clk) begin
      if(!reset) begin
         state      <= WAIT_ALU_OR_MEM; 
         PC         <= RESET_ADDR;
      end else begin
         unique case(1'b1)

           state[EXECUTE_bit]: begin
              PC <= isJALR          ? aluPlus   : 
                    jumpToPCplusImm ? PCplusImm : 
                    PCplus4;

              mem_addr <= isJALR | isStore | isLoad ? aluPlus   : 
                          jumpToPCplusImm           ? PCplusImm : 
                          PCplus4;

              state <= fsm_state_t'({
                 1'b0,                                        
                 isStore,                                     
                 aluBusy,                                     
                 isLoad,                                      
                 1'b0,                                        
                 1'b0,                                        
                 1'b0,                                        
                 !(isStore|isALU|isLoad) | (isALU & !aluBusy) 
              });
           end

           state[WAIT_INSTR_bit]: begin
              if(!mem_rbusy) begin 
                 instr[31:2] <= mem_rdata[31:2]; 
                 state <= FETCH_REGS;      
              end
           end

           state[WAIT_ALU_OR_MEM_bit]: begin
              if(!aluBusy & !mem_rbusy & !mem_wbusy) begin
                 mem_addr <= PC;
                 state <= FETCH_INSTR;
              end
           end

           default: begin
             state <= fsm_state_t'({
                 state[FETCH_REGS_bit],  
                 1'b0,                   
                 state[LOAD_bit] | state[STORE_bit],   
                 1'b0,                   
                 state[ALU_bit],         
                 1'b0,                   
                 state[FETCH_INSTR_bit], 
                 1'b0                    
             });
           end

         endcase
      end
   end

endmodule