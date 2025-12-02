
import xbox_def_pkg::*;

//-----------------------------------------------------------------------

module cgol_xlr_tor (

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

  /**********************************************************************/
  /*                              THE MASK                              */
  /**********************************************************************/

  //~~~~~~~~| THE CGOL MASKS |~~~~~~~~~//

  localparam M_CGOL = 20'b0000_0000_0010_1100_0000; // Mega Mask

  //localparam M_CGOL = 18'b00_0000_0000_1110_0000; // The Semi-Mega Mask

//==================================================================================================================================
 
  /**********************************************************************/
  /*                            DECLARATIONS                            */
  /**********************************************************************/

  logic [15:0] grid_xmem_base_addr; // For the base address.
  logic [31:0] grid_width;          // Number of columns in grid , provided by SW
  logic [31:0] bytes_per_grid_row;  // Needed to calculate size of memory access
  logic        start;               // Triggered by SW
  logic        done;                // Used to inform SW operation is done.
  logic [31:0] _num_itr_;           // Number of iterations, provided by SW
  logic        clear_done_on_read;  // Indicates by SW completed read of register allocated to "done"

  logic [15:0] crnt_rd_addr;        // Current Read Address from grid
  logic [15:0] crnt_wr_addr;        // Current write address to grid

  logic [1:0][MAX_WIDTH-1:0] double_row_hold_buf;   // Holding Buffer for Rows 0 and 1
  logic [2:0][MAX_WIDTH-1:0] triple_row_buf;        //  Rolling Buffer for the data rows window
  logic      [MAX_WIDTH-1:0] updated_row;           // Calculated new row to be updated in grid
  logic      [MAX_WIDTH-1:0] updated_row_ps;			  // Holds the Pre-Sampled result

  
  logic [$clog2(MAX_HEIGHT):0] grid_wr_row_idx;  // Current grid write index - 6 bits wide
  logic [$clog2(MAX_HEIGHT):0] grid_rd_row_idx;  // Current grid read index - 6 bits wide
  logic [$clog2(MAX_HEIGHT):0] grid_height;      // Grid Height, provided by SW - 7 bits wide

  logic is_fake_n;            // Indicator for first fake write
  logic next_is_last_row;     // Indicate next row will be last (required for border treatment)
  logic is_last_row;          // Indicate we are at the last row
  logic is_last_itr;          // Indicate we are at the last itr
  logic start_next_itr;       // Indicator for resetting the relevant signals for next iteration

  logic dbl_load_idx;     // Index for first 2 reads.

  // Holds triple_buf row index (0,1,2)
  logic [1:0] triple_buf_prev_row_idx;   // index of previous row within the triple row buffer
  logic [1:0] triple_buf_crnt_row_idx;   // index of current row within the triple row buffer
  logic [1:0] triple_buf_next_row_idx;   // index of next row within the triple row buffer

  //~~~~~~~~| CLK CYCLE PERFORMANCE |~~~~~~~~~//


  //logic [MAX_HEIGHT-1:0]       is_zero_row_rd;   // Used for checking if the row we're about to read is 0.
  //logic [MAX_HEIGHT-1:0]       row_is_zero_wr;   // Used for tracking the zero rows written. Will be used for the iteration afterwards.
  //logic                        skip_next_row;    // Indicator for skipping next row

  logic [31:0]                 num_itr_counter;  // Counter for number of iterations, used for sending done signal when = _num_itr_

  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//

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
     GRID_BASE_ADDR_REG_IDX,    // Index of the register holding the base address
     GRID_WIDTH_REG_IDX,        // Index of the register holding the grid width
     GRID_HEIGHT_REG_IDX,       // Index of the register holding the grid height
     START_REG_IDX,             // Index of the register indicating START
     DONE_REG_IDX,              // Index of the register indicating DONE
     NUM_ITR_REG_IDX            // Index of the register holding the number of iterations
  } regs_idx;

//==================================================================================================================================

  /**********************************************************************/
  /*                         HOST REGS INTERFACE                        */
  /**********************************************************************/

  logic [XBOX_NUM_REGS-1:0][31:0] host_regs_data_out_ps; // pre-sampled

  always_comb begin // Update comb logic                                                  // default the pre sample regs out
                                                 host_regs_data_out_ps                  = host_regs_data_out;
    if      (done                              ) host_regs_data_out_ps[DONE_REG_IDX][0] = 1'b1;  // Update the done allocated register     
    else if (host_regs_read_pulse[DONE_REG_IDX]) host_regs_data_out_ps[DONE_REG_IDX][0] = '0;  // clear upon SW reading         
  end 

  // Sample host regs output
  always @(posedge clk, negedge rst_n) begin
    if(~rst_n) host_regs_data_out <= '0;
    else       host_regs_data_out <= host_regs_data_out_ps;  
  end

  // Update output host registers
  always_comb begin
    host_regs_valid_out               = '0; // Default
    host_regs_valid_out[DONE_REG_IDX] = host_regs_data_out[DONE_REG_IDX][0];
  end

  // For convenience clone by assign the host regs values

  assign start               = host_regs            [START_REG_IDX          ] && 
                               host_regs_valid_pulse[START_REG_IDX          ]       ;
  assign grid_xmem_base_addr = host_regs            [GRID_BASE_ADDR_REG_IDX ][15:0] ;
  assign grid_width          = host_regs            [GRID_WIDTH_REG_IDX     ]       ;  // assumed to be an integer and not bigger than MAX_WIDTH and a multiply of 8
  assign grid_height         = host_regs            [GRID_HEIGHT_REG_IDX    ][6:0]  ;  // grid_heigh is 7 bits wide, (64)(bin) = 7'b1000_000;
  assign _num_itr_           = host_regs            [NUM_ITR_REG_IDX        ]       ;
  assign clear_done_on_read  = host_regs_read_pulse [DONE_REG_IDX           ]       ;

  assign bytes_per_grid_row  = grid_width >> 3; // Dividing by 8

//==================================================================================================================================

  /**********************************************************************/
  /*                           STATE MACHINE                            */
  /**********************************************************************/

  /*--------------------------*/
  /*        Definitions       */
  /*--------------------------*/

  typedef enum logic [6:0] { // 1-Hot Coding for Performance (Sacrificing some Area 3 -> 7 DFFS)

    IDLE      = 7'b0000001,
    DBL_LOAD  = 7'b0000010,
    LST_LOAD  = 7'b0000100,
    WRITE     = 7'b0001000,
    READ      = 7'b0010000,
    LAST      = 7'b0100000,
    DONE      = 7'b1000000

  } state_machine;

  state_machine next_state, state;

  //~~~~~~~~| STATE MASKS |~~~~~~~~~//

  typedef enum int {

    IDLE_IDX      = 0,
    DBL_LOAD_IDX  = 1,
    LST_LOAD_IDX  = 2,
    WRITE_IDX     = 3,
    READ_IDX      = 4,
    LAST_IDX      = 5,
    DONE_IDX      = 6

  } state_index;

  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//


  /*--------------------------*/
  /*       Combinatorial      */
  /*--------------------------*/

  always_comb begin

    // Defaults 

    next_state                    = state;
    mem_intf_write.mem_size_bytes = bytes_per_grid_row[5:0];
    mem_intf_read.mem_size_bytes  = bytes_per_grid_row[5:0];
    mem_intf_write.mem_data       = updated_row;
    mem_intf_write.mem_start_addr = crnt_wr_addr;
    mem_intf_read.mem_start_addr  = crnt_rd_addr;
    mem_intf_read.mem_req         = '0;
    mem_intf_write.mem_req        = '0;
    done                          = 1'b0;

    case (state) // State Machine case
    
      IDLE: begin

        if (start) begin
          mem_intf_read.mem_req = 1'b1;
          next_state            = DBL_LOAD;
        end

      end
      
      DBL_LOAD: begin // Used for Reading First 2 Rows into triple_row_buf & storing into double_row_hold_buf     

        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 1'b1; // Using the flag to safely gate both rd & wr req's
          next_state = state_machine'(DBL_LOAD << dbl_load_idx); // enum trick to avoid using a MUX. DBL_LOAD + 1'b1 = LST_LOAD
        end

      end

      LST_LOAD: begin // Used for Reading 3rd Row into triple_row_buf.

        if (mem_intf_read.mem_valid) begin
          mem_intf_write.mem_req  = 1'b1; // Assert mem_req for a fake write to align the FSM Pipeline
          mem_intf_read.mem_req   = 1'b0; // De-Assert read request
          next_state              = WRITE;
        end

      end

      WRITE: begin

        if (mem_intf_write.mem_ack) begin
          mem_intf_write.mem_req  = 1'b0;

          if (grid_rd_row_idx[6:4] == grid_height[6:4]) begin // Check for last 3 MSB bits - 16 / 32 / 48 / 64
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
          mem_intf_write.mem_req  = 1'b1;
          mem_intf_read.mem_req   = 1'b0;
          next_state              = WRITE;
        end
      end
      
      LAST: begin
        mem_intf_write.mem_req        = 1'b1;
        if (is_last_row)  next_state  = DONE; // Moving to DONE where we determine whether it's the last itr or not
        else              next_state  = WRITE;
      end 
      
      DONE: begin
        if (is_last_itr) begin
          done = 1'b1;
          if (clear_done_on_read)
            next_state            = IDLE;
            
        end else begin // Start Next Iteration
            mem_intf_read.mem_req = 1'b1;
            next_state            = DBL_LOAD; 
        end
      end

      default: next_state = IDLE;

    endcase
  
  end

  // last logic comb assignment.
  assign next_is_last_row     = (grid_wr_row_idx + 2 == grid_height);
  assign is_last_row          = (grid_wr_row_idx + 1 == grid_height);

  assign is_last_itr          = ((|_num_itr_) & (num_itr_counter == _num_itr_)); // Safe-Guarding + Bit-Wise OR instead of MUX & Comparator

  /*----------------------------*/
  /*         Sequentials        */
  /*----------------------------*/

  //~~~~~~~~~~~~~~~~~~~~~~~~~| FSM - ITR Counter |~~~~~~~~~~~~~~~~~~~~~~~~~~~//

  always @(posedge clk or negedge rst_n) begin // Incrementing the counter in the 1st time we're in LAST, and evaluating next_state in the 2nd time
    if (!rst_n) num_itr_counter <= '0;
    else if (state[LAST_IDX] && next_is_last_row) num_itr_counter <= num_itr_counter + 1'b1;
  end

  //~~~~~~~~~~~~~~~~~~~~~~~~~~| FSM - State Seq |~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else        state <= next_state;
  end

  //~~~~~~~~~~~~~~~~~~~~~~| FSM - Windows-Be-Sliding |~~~~~~~~~~~~~~~~~~~~~~~//

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin
      
      dbl_load_idx              <= '0;
      double_row_hold_buf       <= '0;
      triple_row_buf            <= '0;

      start_next_itr            <= '0;
     
    end else if (start || start_next_itr) begin
        
      dbl_load_idx              <= '0;
      double_row_hold_buf       <= '0;
      triple_row_buf            <= '0;
      
      start_next_itr            <= '0;

    end else begin

      if (state[DBL_LOAD_IDX]) begin // dbl_load_idx is used as decoupling the critical path that may be affected by indexing triple_row_buf with signals used in other places
        triple_row_buf     [dbl_load_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0];
        double_row_hold_buf[dbl_load_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0]; // Store Rows 0.1 for last computation
        dbl_load_idx <= !dbl_load_idx; // Swap dbl_load_idx from 0 -> 1 and back to 0.
      end else if (state[LST_LOAD_IDX]) // 3rd Read of Row[2]
        triple_row_buf[2] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0]; // Direct 2 for a single and clear state, removing grid_rd_row_idx should alleviate the high fanout

      else if (state[READ_IDX])
        triple_row_buf[triple_buf_next_row_idx] <= mem_intf_read.mem_data[MAX_WIDTH_BYTES-1:0];

      else if (state[LAST_IDX]) begin // Load the stored rows, Row[N-1] is stored in Prev Row !
        if (is_last_row)
          start_next_itr <= 1'b1; // Asserting the flag for next iteration
        else if (next_is_last_row) // Next Row is Row(1) used for calculating Row[0]
          triple_row_buf[triple_buf_next_row_idx] <= double_row_hold_buf[1];
        else              // For computing Row(N-1), next_row is Row[0]
          triple_row_buf[triple_buf_next_row_idx] <= double_row_hold_buf[0];
      end 
    end
  end

  //~~~~~~~~~~~~~~~~~~~~~~| FSM - READ Addr & Counter |~~~~~~~~~~~~~~~~~~~~~~~//

  wire        next_is_last_rd = (grid_rd_row_idx + 1 == grid_height);
  wire [15:0] next_rd_addr    = (next_is_last_rd) ? grid_xmem_base_addr : crnt_rd_addr + bytes_per_grid_row[15:0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crnt_rd_addr            <= '0;
      grid_rd_row_idx         <= '0;
    end else begin // None of these signal are mutually exclusing - Independent if statements for each.
      if (start || start_next_itr)
        grid_rd_row_idx       <= '0; // Set to '0 on purpose, used for 3 first LOADs.

      if (mem_intf_read.mem_valid)
        grid_rd_row_idx       <= grid_rd_row_idx + 7'h1;

      if (mem_intf_read.mem_req)
        crnt_rd_addr          <= next_rd_addr;
    end
  end

  //~~~~~~~~~~~~~~~~~~~~~~| FSM - WRITE Addr & Counter |~~~~~~~~~~~~~~~~~~~~~~~//

  wire [15:0] next_wr_addr = (is_last_row || next_is_last_row) ? grid_xmem_base_addr : (crnt_wr_addr + bytes_per_grid_row[15:0]);
  // Consider removing the ternary if it can be done - TODO
  //wire row_is_zero_wr_ps   = is_fake_n ? (~(|updated_row_ps[MAX_WIDTH_BYTES-1:0])) : '0; // Bit-Wise OR Followed by NOT

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crnt_wr_addr                      <= '0;
      grid_wr_row_idx                   <= '0;
      is_fake_n                         <= '0;

      updated_row                       <= '0;

      triple_buf_prev_row_idx           <= '0;
      triple_buf_crnt_row_idx           <= '0;
      triple_buf_next_row_idx           <= '0;

      //row_is_zero_wr                    <= '0;
    end else if (start || start_next_itr) begin
      grid_wr_row_idx                   <= '0;
      is_fake_n                         <= '0;

      updated_row                       <= '0;

      triple_buf_prev_row_idx           <= 2'b00;
      triple_buf_crnt_row_idx           <= 2'b01;
      triple_buf_next_row_idx           <= 2'b10;
    end else begin
      if (mem_intf_write.mem_req) begin
        crnt_wr_addr                    <= next_wr_addr;
        //row_is_zero_wr[grid_wr_row_idx] <= row_is_zero_wr_ps;
      end

      else if (mem_intf_write.mem_ack) begin // !state[DBL_LOAD_IDX] used to make sure last mem_ack is ignored.
        grid_wr_row_idx                 <= grid_wr_row_idx + is_fake_n;
        is_fake_n                       <= 1'b1;

        updated_row                     <= updated_row_ps;

        triple_buf_prev_row_idx         <= triple_buf_crnt_row_idx; // roll triple_buf row indexes
        triple_buf_crnt_row_idx         <= triple_buf_next_row_idx;
        triple_buf_next_row_idx         <= triple_buf_prev_row_idx;
      end
    end
  end

//==================================================================================================================================

  /**********************************************************************/
  /*                        TORUS CGOL PROCESSING                       */
  /**********************************************************************/

  // tree adder implementation to calculate updated row to be written back ro grid - less depth

  wire [6:0] grid_width_opt = grid_width[6:0]; // By-Passing the annoying synthesis warning of the dummy_wrapper

  logic [1:0] sum_col [0:MAX_WIDTH-1]; // a 2-bit 1-D array for the 1st stage of vertical sum

  always_comb begin // Stage 1 - Vertical Sum across columns
    for (int i = 0; i < MAX_WIDTH; i++) begin
      if (i < grid_width_opt) begin
        sum_col[i] = triple_row_buf[0][i] + triple_row_buf[1][i] + triple_row_buf[2][i];
      end else begin
        sum_col[i] = 2'b00; // bit masking
      end
    end
  end

  always_comb begin // Stage 2 - Reusing Pre-Calculated Sums for each cell
    for (int i = 0; i < MAX_WIDTH; i++) begin
      
      logic [3:0] sum_neighs; // Local Variable for summing relevant cols (Initialized to 0)

      if (i < grid_width_opt) begin
        logic i_cell;
        i_cell = triple_row_buf[triple_buf_crnt_row_idx][i]; // Cell i in Current Row

        if (i == 1'b0) sum_neighs = sum_col[grid_width_opt-1] + sum_col[i] + sum_col[i+1];
        else if (i == grid_width_opt - 1 || (i == MAX_WIDTH - 1)) sum_neighs = sum_col[i-1] + sum_col[i] + sum_col[0];
        else sum_neighs = sum_col[i-1] + sum_col[i] + sum_col[i+1];

        updated_row_ps[i] = M_CGOL[{sum_neighs, i_cell}];

      end else begin

        updated_row_ps[i] = 1'b0; // Masking
        sum_neighs        = 4'd0; // Default value for sum_neighs

      end
    end
  end

endmodule