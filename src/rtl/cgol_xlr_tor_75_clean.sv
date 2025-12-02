
import xbox_def_pkg::*;

//-----------------------------------------------------------------------

module cgol_xlr_tor_75_clean (

  // DO NOT TOUCH INTERFACE

  input        clk,
  input        rst_n,  
 
  // Command Status Register Interface
  input        [XBOX_NUM_REGS-1:0][31:0] host_regs,               // regs accelerator write data, reflecting logicisters content as most recently written by SW over APB
  input  logic [XBOX_NUM_REGS-1:0]       host_regs_valid_pulse,   // logic written by host (APB) (one per register)   
  output logic [XBOX_NUM_REGS-1:0][31:0] host_regs_data_out,      // regs accelerator write data,  this is what SW will read when accessing the register  
                                                                  // provided that the register specific host_regs_valid_out is asserted
  output logic [XBOX_NUM_REGS-1:0]       host_regs_valid_out,     // logic accelerator (one per register)   
  input  logic [XBOX_NUM_REGS-1:0]       host_regs_read_pulse,    // Indicate register actual read by host to allow clear on read if desired.

  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write 
 );
 
//================================================================================================================================== 

  // Max possible dimenssions avtual confifured dimenssions might be less - Note that this is for TORUS (Non-Wrapped has MAX 256)

  localparam MAX_HEIGHT = 64;  // MAX Height of cgol grid (max number of rows)
  localparam MAX_WIDTH  = 64;  // Max number cells in a cgol grid row , must be an integer multiple of 8
  localparam MAX_WIDTH_BYTES = MAX_WIDTH / 8;
 
//================================================================================================================================== 
 
 // TEMPORARILY DRIVING ALL MODULE OUTPUTS TO 0  
 // TO AVOID UNKNOWN VALUES 'X' PROPAGATION INTO THE SYSTEM  
 // REMOVE THIS SECTION PRIOR TO ACCELERATOR IMPLEMENTATION


  /*always_comb begin  
    host_regs_valid_out = 0; // Default
    host_regs_valid_out           = 0;
    mem_intf_write.mem_size_bytes = 0;   
    mem_intf_read.mem_size_bytes  = 0;
    mem_intf_write.mem_data       = 0;
    mem_intf_write.mem_start_addr = 0;   
    mem_intf_read.mem_start_addr  = 0;  
    mem_intf_read.mem_req         = 0;
    mem_intf_write.mem_req        = 0;   
  end*/
   
//================================================================================================================================== 
 
  /**********************************************************************/
  /*                            DECLARATIONS                            */
  /**********************************************************************/

  logic [15:0] grid_xmem_base_addr; // For the base address.
  logic [31:0] grid_width;          // Number of columns in grid , provided by SW
  logic [31:0] bytes_per_grid_row;  // Needed to calculate size of memory access
  logic        start;               // Triggered by SW
  logic        done;                // Used to inform SW operation is done.
  logic clear_done_on_read;         // Indicates by SW completed read of register allocated to "done"

  logic [15:0] crnt_rd_addr;        // Current Read Address from grid
  logic [15:0] crnt_wr_addr;        // Current write address to grid

  logic [1:0][MAX_WIDTH-1:0] double_row_hold_buf;   // Holding Buffer for Rows 0 and 1
  logic [2:0][MAX_WIDTH-1:0] triple_row_buf;        //  Rolling Buffer for the data rows window
  logic [MAX_WIDTH-1:0] updated_row;                // Calculated new row to be updated in grid
  logic [MAX_WIDTH-1:0] updated_row_ps;					    // Holds the Pre-Sampled result

  
  logic [$clog2(MAX_HEIGHT):0] grid_wr_row_idx;  // Current grid write index - 6 bits wide
  logic [$clog2(MAX_HEIGHT):0] grid_rd_row_idx;  // Current grid read index - 6 bits wide
  logic [$clog2(MAX_HEIGHT):0] grid_height;      // Grid Height, provided by SW - 7 bits wide

  logic is_fake_write;    // Indicator for first fake write
  logic is_last;       // Indicate we are at the last row
  logic next_is_last;  // Indicate next row will be last (required for border treatment)

  logic [31:0] last_addr_pre_trunc; // Used for computing last_addr before truncation
  logic [15:0] last_addr;           // Used for Indicating the last read address

  // Holds triple_buf row index (0,1,2)
  logic [1:0] triple_buf_prev_row_idx;   // index of previous row within the triple row buffer
  logic [1:0] triple_buf_crnt_row_idx;   // index of current row within the triple row buffer
  logic [1:0] triple_buf_next_row_idx;   // index of next row within the triple row buffer


// Debug assistance cloned signals not really needed 
  // triple_row_buf indirect clone used for easy debugging, 
  //logic [MAX_WIDTH-1:0] prev_row_buf ;
  //logic [MAX_WIDTH-1:0] crnt_row_buf ;
  //logic [MAX_WIDTH-1:0] next_row_buf ; 
 
  // clone by assignment (don't worry, will be optimized out in synthesis)
  //assign prev_row_buf = triple_row_buf[triple_buf_prev_row_idx];
  //assign crnt_row_buf = triple_row_buf[triple_buf_crnt_row_idx];
  //assign next_row_buf = triple_row_buf[triple_buf_next_row_idx];
// End of debug assistance

   
// SW-HW Register allocation indexes must be compliant with the relative used address in the accelerator code, this is NOT automated. 
  enum {
     GRID_BASE_ADDR_REG_IDX,  // Index of the register holding the base address
     GRID_WIDTH_REG_IDX,      // Index of the register holding the grid width
     GRID_HEIGHT_REG_IDX,     // Index of the register holding the grid height
     START_REG_IDX,           // Index of the register indicating START
     DONE_REG_IDX             // Index of the register indicating DONE
  } regs_idx;

//==================================================================================================================================

  /**********************************************************************/
  /*                         HOST REGS INTERFACE                        */
  /**********************************************************************/

  logic [XBOX_NUM_REGS-1:0][31:0] host_regs_data_out_ps; // pre-sampled
  always_comb begin // Update comb logic
     host_regs_data_out_ps = host_regs_data_out ; // default the pre sample regs out
     if (done) host_regs_data_out_ps[DONE_REG_IDX][0] = 1'b1;  // Update the done allocated register     
     else if (host_regs_read_pulse[DONE_REG_IDX]) host_regs_data_out_ps[DONE_REG_IDX][0] = '0;  // clear upon SW reading         
  end 
  
  // Sample host regs output
  always @(posedge clk, negedge rst_n) begin
     if(~rst_n) host_regs_data_out <= '0;
     else host_regs_data_out <= host_regs_data_out_ps;        
  end
  
  // Update output host registers
  always_comb begin
   host_regs_valid_out = '0; // Default
   host_regs_valid_out[DONE_REG_IDX] = host_regs_data_out[DONE_REG_IDX][0];
  end

  // For convenience clone by assign the host regs values

  assign grid_xmem_base_addr = host_regs[GRID_BASE_ADDR_REG_IDX][15:0];
  assign grid_width          = host_regs[GRID_WIDTH_REG_IDX] ;  // assumed to be an integer and not bigger than MAX_WIDTH and a multiply of 8
  assign bytes_per_grid_row  = grid_width >> 3; // Dividing by 8
  assign grid_height         = host_regs[GRID_HEIGHT_REG_IDX][6:0]; // grid_heigh is 7 bits wide, (64)(bin) = 7'b1000_000;
  assign start               = host_regs[START_REG_IDX] && host_regs_valid_pulse[START_REG_IDX];
  assign clear_done_on_read  = host_regs_read_pulse[DONE_REG_IDX];

  assign last_addr_pre_trunc = grid_height * bytes_per_grid_row; // Calculation of last_addr for FSM control
  assign last_addr           = last_addr_pre_trunc[15:0]; // Truncated to match "last_addr"'s bit-width

//==================================================================================================================================

  /**********************************************************************/
  /*                             Opt. Tricks                            */
  /**********************************************************************/

  // MASKS for CGOL RULES

  localparam SURVIVE_MASK  = 9'b0_0000_1100; // 3 or 2 neigbors alive
  localparam REBIRTH_MASK  = 9'b0_0000_1000; // 3 neighbors alive

  //localparam CGOL_MASK = 18'b00_0000_0000_1110_0000;

//==================================================================================================================================

  /**********************************************************************/
  /*                           STATE MACHINE                            */
  /**********************************************************************/

  /*--------------------------*/
  /*        Definitions       */
  /*--------------------------*/

  typedef enum logic [6:0] { // 1-Hot Encoding for Performance (Sacrificing some Area 3 -> 7 DFFS)

    IDLE      = 7'b0000001,
    DBL_LOAD  = 7'b0000010,
    LST_LOAD  = 7'b0000100,
    WRITE     = 7'b0001000,
    READ      = 7'b0010000,
    LAST      = 7'b0100000,
    DONE      = 7'b1000000

  } state_machine;

  state_machine next_state, state;

  typedef enum int {

    IDLE_IDX      = 0,
    DBL_LOAD_IDX  = 1,
    LST_LOAD_IDX  = 2,
    WRITE_IDX     = 3,
    READ_IDX      = 4,
    LAST_IDX      = 5,
    DONE_IDX      = 6

  } state_index;

  /*--------------------------*/
  /*       Combinatorial      */
  /*--------------------------*/

  always_comb begin
  
    // Defaults 

    next_state = state;
    mem_intf_write.mem_size_bytes = bytes_per_grid_row[5:0];   
    mem_intf_read.mem_size_bytes  = bytes_per_grid_row[5:0];
    mem_intf_write.mem_data       = updated_row;
    mem_intf_write.mem_start_addr = crnt_wr_addr;   
    mem_intf_read.mem_start_addr  = crnt_rd_addr;  
    mem_intf_read.mem_req = '0;
    mem_intf_write.mem_req = '0;

    done = 1'b0;
      
    case (state) // State Machine case
    
      IDLE: begin

        if (start) begin
          next_state = DBL_LOAD;
          mem_intf_read.mem_req = 1'b1;
        end

      end      
      
      DBL_LOAD: begin // Used for Reading First 2 Rows into triple_row_buf & storing into double_row_hold_buf     

        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 1'b1; // Using the flag to safely gate both rd & wr req's 
          next_state = state_machine'(DBL_LOAD << grid_rd_row_idx); // enum trick to avoid using a MUX and an adder
        end

      end

      LST_LOAD: begin // Used for Reading 3rd Row into triple_row_buf.

        if (mem_intf_read.mem_valid) begin
          mem_intf_write.mem_req = 1'b1; // Assert mem_req for a fake write to align the FSM Pipeline
          mem_intf_read.mem_req = 1'b0; // De-Assert read request
          next_state = WRITE;
        end

      end

      WRITE: begin

        if (mem_intf_write.mem_ack) begin

          mem_intf_write.mem_req = 1'b0;

          if (crnt_rd_addr == last_addr) begin
            mem_intf_read.mem_req = 1'b0;
            next_state = LAST;
          end else begin
            mem_intf_read.mem_req = 1'b1;
            next_state = READ;
          end

        end
      end

      READ: begin

        if (mem_intf_read.mem_valid) begin

          mem_intf_write.mem_req = 1'b1;
          mem_intf_read.mem_req = 1'b0;

          //if (next_is_last) done = 1'b1; // Raise done signal properly timed with SW's polling

          next_state = WRITE;
          
        end
        
      end
      
      LAST: begin

        mem_intf_write.mem_req = 1'b1;
        
        if (is_last)  next_state = DONE;
        else          next_state = WRITE;

        //done = 1'b1; // Hold done

      end 
      
      DONE: begin

        done = 1'b1;

        if (clear_done_on_read) next_state = IDLE;

      end 

      default: next_state = IDLE; // Safety First

    endcase
   
  end // always

  // last logic comb assignment.
  assign next_is_last = ((grid_wr_row_idx + 2) == grid_height);
  assign is_last      = (grid_height == 7'b0) ? 1'b0 : ((grid_wr_row_idx + 1) == grid_height); // Safe Guard

  /*----------------------------*/
  /*         Sequentials        */
  /*----------------------------*/

  always @(posedge clk or negedge rst_n) begin // FSM State Seq.

    if (!rst_n) state <= IDLE;
    else        state <= next_state;

  end

  always @(posedge clk or negedge rst_n) begin
  
    if (!rst_n) begin

      is_fake_write             <= '0;
      crnt_rd_addr              <= '0;
      crnt_wr_addr              <= '0;
      double_row_hold_buf       <= '0;
      triple_row_buf            <= '0;
      updated_row               <= '0;
      grid_wr_row_idx           <= '0;
      grid_rd_row_idx           <= '0;

      triple_buf_prev_row_idx   <= '0;
      triple_buf_crnt_row_idx   <= '0;
      triple_buf_next_row_idx   <= '0;
     
    end else begin 
    
      if (start) begin

        crnt_rd_addr            <= bytes_per_grid_row[15:0]; // 1st Read request already made for base_addr - Increment by byte amount
        crnt_wr_addr            <= bytes_per_grid_row[15:0]; // We start by processing Row[1] - We fake write into Row[1]

        triple_row_buf          <= '0;
        updated_row             <= '0;

        grid_wr_row_idx         <= '0;
        grid_rd_row_idx         <= '0; // Set to '0 on purpose, used for 3 first LOADs.

        triple_buf_prev_row_idx <= 2'h0;
        triple_buf_crnt_row_idx <= 2'h1;
        triple_buf_next_row_idx <= 2'h2;

      end else begin

        if (state[DBL_LOAD_IDX] && mem_intf_read.mem_valid) begin // Added the initial storing mechanism of Row(0) & Row(1)
          
          triple_row_buf[grid_rd_row_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0];
          double_row_hold_buf[grid_rd_row_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0]; // Store Rows 0.1 for last computation
          
          grid_rd_row_idx <= grid_rd_row_idx + 6'h1; // grid_rd_row_idx 0 -> 1 -> 2
          crnt_rd_addr <= crnt_rd_addr + bytes_per_grid_row[15:0];

        end else if (state[LST_LOAD_IDX] && mem_intf_read.mem_valid) begin // 3rd Read of Row[2]

          triple_row_buf[grid_rd_row_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0];
          
          grid_rd_row_idx <= grid_rd_row_idx + 6'h1; // grid_rd_row_idx 2 -> 3

          is_fake_write <= 1'b1; // Needed for making sure grid_wr_row_idx doesn't incr. during the fake write

        end else if (state[READ_IDX] && mem_intf_read.mem_valid) begin
        
          triple_row_buf[triple_buf_next_row_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0];
          grid_rd_row_idx <= grid_rd_row_idx + 6'h1;

          crnt_wr_addr <= crnt_wr_addr + bytes_per_grid_row[15:0]; // Swapped wr addr into read - synchronized with wr_req

        end else if (state[LAST_IDX]) begin // Load the stored rows, Row[N-1] is stored in Prev Row !

          if (is_last) crnt_wr_addr <= grid_xmem_base_addr;
          else if (next_is_last) begin
            crnt_wr_addr <= grid_xmem_base_addr; // Last Write Into Row(0) !
            triple_row_buf[triple_buf_next_row_idx] <= double_row_hold_buf[1]; // Next Row is Row(1) used for calculating Row[0]
          end else begin
            crnt_wr_addr <= crnt_wr_addr + bytes_per_grid_row[15:0]; // First time it'll incrt from 28 -> 30, it's correct 100%
            triple_row_buf[triple_buf_next_row_idx] <= double_row_hold_buf[0]; // For computing Row(N-1), next_row is Row[0]
          end

        end
             
        if (mem_intf_write.mem_ack) begin

            if (is_last) updated_row <= '0; // Perform Calculation
            else updated_row <= updated_row_ps; // Perform Calculation

            if (crnt_rd_addr != last_addr) crnt_rd_addr <= crnt_rd_addr + bytes_per_grid_row[15:0]; // Swap the rd addr into write - synchronized with rd_req

            if (is_fake_write) begin 
              grid_wr_row_idx <= 6'd0;
              is_fake_write   <= 1'b0; // de-assert after 1st is_fake_write
            end else grid_wr_row_idx <= grid_wr_row_idx + 6'd1;

            // roll triple_buf row indexes
            triple_buf_prev_row_idx <= triple_buf_crnt_row_idx;
            triple_buf_crnt_row_idx <= triple_buf_next_row_idx;
            triple_buf_next_row_idx <= triple_buf_prev_row_idx;
        end

        if (state[DONE_IDX]) begin // Pipeline Flusher

          double_row_hold_buf     <= '0;
          triple_row_buf          <= '0;
          crnt_wr_addr            <= '0;
          crnt_rd_addr            <= '0;
          triple_buf_prev_row_idx <= '0;
          triple_buf_crnt_row_idx <= '0;
          triple_buf_next_row_idx <= '0;

        end

      end  // start else

    end // !rst_n else

  end

//==================================================================================================================================

  /**********************************************************************/
  /*                        TORUS CGOL PROCESSING                       */
  /**********************************************************************/

  // tree adder implementation to calculate updated row to be written back ro grid - less depth

  logic [1:0] sum_col [0:MAX_WIDTH-1]; // a 2-bit 1-D array for the 1st stage of vertical sum

  always_comb begin // Stage 1 - Vertical Sum across columns
    for (int i = 0; i < MAX_WIDTH; i++) begin
      if (i < grid_width) begin
        sum_col[i] = triple_row_buf[0][i] + triple_row_buf[1][i] + triple_row_buf[2][i];
      end else begin
        sum_col[i] = 2'b00; // bit masking
      end
    end
  end

  always_comb begin // Stage 2 - Reusing Pre-Calculated Sums for each cell
    for (int i = 0; i < MAX_WIDTH; i++) begin
      
      logic [3:0] sum_neighs; // Local Variable for summing relevant cols (Initialized to 0)
      
      if (i < grid_width) begin
        logic i_cell;
        i_cell = triple_row_buf[triple_buf_crnt_row_idx][i]; // Cell i in Current Row

        if (i == 1'b0) sum_neighs = sum_col[grid_width-1] + sum_col[i] + sum_col[i+1];
        else if (i == grid_width - 1 || (i == MAX_WIDTH - 1)) sum_neighs = sum_col[i-1] + sum_col[i] + sum_col[0];
        else sum_neighs = sum_col[i-1] + sum_col[i] + sum_col[i+1];

        sum_neighs -= i_cell; // Remove the current cell state
        
        //updated_row_ps[i] = CGOL_MASK[{sum_neighs, i_cell}];

        updated_row_ps[i] = i_cell ? SURVIVE_MASK[sum_neighs] : REBIRTH_MASK[sum_neighs];

      end else begin

        updated_row_ps[i] = 1'b0; // Masking
        sum_neighs        = 4'd0; // Default value for sum_neighs

      end
    end
  end

endmodule