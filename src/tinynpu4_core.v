// The Core Unit  -  tinynpu4_core.v
// Made and tested by Essam Elkholy and Mohamed Awad
// Github link: https://github.com/Essam-Elkholy  "GlitchPi"
//

`default_nettype none

module tinynpu4_core (
    input  wire [7:0] data_in,
    input  wire [2:0] command,
    input  wire [3:0] param_in,
    input  wire       command_valid,

    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,

    output wire [3:0] result,
    output reg        done,
    output reg        result_valid,
    output reg        overflow,
    output wire       accumulator_negative
);

    // Command definitions
    localparam CMD_NOP             = 3'b000;
    localparam CMD_CLEAR           = 3'b001;
    localparam CMD_LOAD_BIAS_LOW   = 3'b010;
    localparam CMD_LOAD_BIAS_HIGH  = 3'b011;
    localparam CMD_MAC             = 3'b100;
    localparam CMD_FINISH_RELU     = 3'b101;
    localparam CMD_FINISH_LINEAR   = 3'b110;
    localparam CMD_READ_ACC_LOW    = 3'b111;

    // State registers
    reg signed [7:0] bias_register;
    reg signed [9:0] accumulator;
    reg        [3:0] result_register;

    // Shared signals
    wire signed [3:0]  activation;
    wire signed [3:0]  weight;
    wire signed [7:0]  product;
    wire signed [9:0]  bias_init;
    wire signed [10:0] accumulator_extended;
    wire signed [10:0] product_extended;
    wire signed [10:0] mac_sum_extended;
    wire        [3:0]  relu_output;
    wire        [3:0]  linear_output;

    // Input slicing
    assign activation = data_in[3:0];
    assign weight     = data_in[7:4];

    // Sign-extend the complete 8-bit bias to the 10-bit accumulator width
    assign bias_init = {
        {2{param_in[3]}},
        param_in,
        bias_register[3:0]
    };

    // MAC adder signals
    assign accumulator_extended = {accumulator[9], accumulator};
    assign product_extended     = {{3{product[7]}}, product};
    assign mac_sum_extended     = accumulator_extended + product_extended;

    // Result outputs
    assign result               = result_register;
    assign accumulator_negative = accumulator[9];

    // Instance int4_mac
    int4_mac u_int4_mac (
        .activation (activation),
        .weight     (weight),
        .product    (product)
    );

    // Instance ReLU quantizer
    activation_quantizer u_relu_quantizer (
        .accumulator      (accumulator),
        .shift_amount     (param_in),
        .mode_relu        (1'b1),
        .quantized_output (relu_output)
    );

    // Instance Linear quantizer
    activation_quantizer u_linear_quantizer (
        .accumulator      (accumulator),
        .shift_amount     (param_in),
        .mode_relu        (1'b0),
        .quantized_output (linear_output)
    );

    // Sequential control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_register   <= 8'sd0;
            accumulator     <= 10'sd0;
            result_register <= 4'd0;
            done            <= 1'b0;
            result_valid    <= 1'b0;
            overflow        <= 1'b0;
        end else begin
            // done is a one-clock pulse
            done <= 1'b0;

            if (enable && command_valid) begin
                case (command)
                    CMD_NOP: begin
                        // Nothing changes
                    end

                    CMD_CLEAR: begin
                        bias_register   <= 8'sd0;
                        accumulator     <= 10'sd0;
                        result_register <= 4'd0;
                        result_valid    <= 1'b0;
                        overflow        <= 1'b0;
                    end

                    CMD_LOAD_BIAS_LOW: begin
                        bias_register[3:0] <= param_in;
                    end

                    CMD_LOAD_BIAS_HIGH: begin
                        bias_register[7:4] <= param_in;
                        accumulator        <= bias_init;
                        result_valid       <= 1'b0;
                        overflow           <= 1'b0;
                    end

                    CMD_MAC: begin
                        accumulator <= mac_sum_extended[9:0];

                        if (mac_sum_extended[10] != mac_sum_extended[9]) begin
                            overflow <= 1'b1;
                        end
                    end

                    CMD_FINISH_RELU: begin
                        result_register <= relu_output;
                        result_valid    <= 1'b1;
                        done            <= 1'b1;
                    end

                    CMD_FINISH_LINEAR: begin
                        result_register <= linear_output;
                        result_valid    <= 1'b1;
                        done            <= 1'b1;
                    end

                    CMD_READ_ACC_LOW: begin
                        result_register <= accumulator[3:0];
                        result_valid    <= 1'b1;
                        done            <= 1'b1;
                    end

                    default: begin
                        // Nothing changes
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire