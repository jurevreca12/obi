module fifo_lop #(
    parameter type  DTYPE = logic,  // Type of value the FIFO will hold
    parameter int   DEPTH = 8       // Amount of values the FIFO can hold has to be a power of 2 number
) (
    input   logic   clk_i,
    input   logic   rstn_i,

    input   logic   wr_en_i,        // Write enable signal
    input   logic   rd_en_i,        // Read enable signal
    input   DTYPE   w_data_i,       // Write data

    output  DTYPE   r_data_o,       // Read data
    output  logic   full_o,         // FIFO full
    output  logic   empty_o         // FIFO empty
);

reg [$clog2(DEPTH)-1:0] wr_ptr;     // FIFO write pointer
reg [$clog2(DEPTH)-1:0] rd_ptr;     // FIFO read pointer

reg [$bits(DTYPE)-1:0]  fifo_storage [DEPTH];   // FIFO storage

reg rd_last;    // FIFO Read was last operation

assign  full_o  = (rd_ptr == wr_ptr) && !rd_last;   // Determine FIFO full status
assign  empty_o = (rd_ptr == wr_ptr) && rd_last;    // Determine FIFO empty status

assign  r_data_o    = fifo_storage [rd_ptr];    // Assign read data to FIFO output

// FIFO write
always_ff @(posedge clk_i) begin
    if (~rstn_i) begin
        wr_ptr <= '0;
    end else begin
        // Only write if (wr_en & !full_0)
        if (wr_en_i && !full_o) begin
            fifo_storage[wr_ptr] <= w_data_i;   // Write the data to wr_ptr location
            wr_ptr <= wr_ptr + 1'b1;            // Increment wr_ptr after write
        end
    end
end

// FIFO read
always_ff @(posedge clk_i ) begin
    if (~rstn_i) begin
        rd_ptr <= '0;
    end else begin
        // Only read if (rd_en_i & !empty_o)
        if (rd_en_i && !empty_o) begin
            rd_ptr <= rd_ptr + 1'b1;    // Increment rd_ptr after read
        end
    end
end

// FIFO last operation tracking
// Used to determine whether the FIFO is empty or full
always_ff @(posedge clk_i) begin
    if (~rstn_i) begin
        rd_last <= 1'b1;
    end else begin
        if (rd_en_i && !empty_o) begin
            rd_last <= 1'b1;    // Last operation was FIFO read
        end else if (wr_en_i && !full_o) begin
            rd_last <= '0;      // Last operation was FIFO write
        end
    end
end

endmodule
