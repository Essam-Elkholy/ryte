module int4_mac (
    activation,
    weight,
    product
);

input signed [3:0] activation, weight;
output signed [7:0] product;

assign product = activation * weight;

endmodule