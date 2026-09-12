module activation_quantizer (
    accumulator,
    shift_amount,
    mode_relu,
    quantized_output
);

input signed [9:0] accumulator;
input        [3:0] shift_amount;
input              mode_relu;
output logic [3:0] quantized_output;

logic signed [9:0] activation_value;
logic signed [9:0] shifted_value;

always_comb begin

    // Activation: ReLU or Linear
    if (mode_relu) begin
        if (accumulator < 0)
            activation_value = 10'sd0;
        else
            activation_value = accumulator;
    end
    else begin
        activation_value = accumulator;
    end

    // Arithmetic Right Shift
    shifted_value = activation_value >>> shift_amount;

    // Saturation to signed INT4
    if (shifted_value > 10'sd7)
        quantized_output = 4'sd7;

    else if (shifted_value < -10'sd8)
        quantized_output = -4'sd8;

    else
        quantized_output = shifted_value[3:0];

end

endmodule : activation_quantizer