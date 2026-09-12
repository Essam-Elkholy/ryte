<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

TinyNPU-4 is a small signed INT4 neural-network inference core designed for Tiny Tapeout. It uses one signed 4-bit multiplier and a signed 10-bit accumulator to execute multiply-accumulate operations sequentially.

Each MAC command performs:

```text
accumulator = accumulator + (activation * weight)
```

The activation and weight are signed 4-bit two's-complement values in the range `-8` to `+7`. They are packed into `ui_in` as follows:

```text
ui_in[3:0] = activation
ui_in[7:4] = weight
```

The neuron bias is a signed 8-bit value. It is loaded in two commands because the parameter input is only 4 bits wide. Loading the high bias nibble also initializes the 10-bit accumulator with the complete sign-extended bias.

After all MAC operations are complete, the accumulator is arithmetically right-shifted using the value on `uio_in[7:4]`. The result is then saturated to INT4 using one of two output modes:

- ReLU mode clamps negative values to `0` and positive values to the range `0` to `+7`.
- Linear mode clamps the result to the signed INT4 range `-8` to `+7`.

### Input pins

| Signal | Description |
|---|---|
| `ui_in[3:0]` | Signed INT4 activation |
| `ui_in[7:4]` | Signed INT4 weight |
| `uio_in[2:0]` | Command code |
| `uio_in[3]` | Command-valid strobe |
| `uio_in[7:4]` | Bias nibble or shift amount |
| `ena` | Core enable |
| `clk` | System clock |
| `rst_n` | Active-low reset |

### Output pins

| Signal | Description |
|---|---|
| `uo_out[3:0]` | Quantized INT4 result |
| `uo_out[4]` | `done`: one-clock completion pulse |
| `uo_out[5]` | Sticky signed accumulator-overflow flag |
| `uo_out[6]` | Accumulator-negative flag |
| `uo_out[7]` | `result_valid` flag |

All `uio` pins are configured as inputs. Therefore, `uio_out` and `uio_oe` are both tied to zero.

### Command table

| `uio_in[2:0]` | Command | Operation |
|---|---|---|
| `000` | `NOP` | No operation |
| `001` | `CLEAR` | Clear the bias, accumulator, result, and status flags |
| `010` | `LOAD_BIAS_LOW` | Load `uio_in[7:4]` into bias bits `[3:0]` |
| `011` | `LOAD_BIAS_HIGH` | Load bias bits `[7:4]` and initialize the accumulator |
| `100` | `MAC` | Accumulate `activation * weight` |
| `101` | `FINISH_RELU` | Shift, apply ReLU, saturate, and produce a result |
| `110` | `FINISH_LINEAR` | Shift, apply linear saturation, and produce a result |
| `111` | `READ_ACC_LOW` | Copy accumulator bits `[3:0]` to the result output for testing |

## How to test

Set `ena = 1`. To issue a command, place the command and parameter on `uio_in`, then assert `uio_in[3]` for one rising edge of `clk`.

Start every independent calculation by driving `rst_n = 0` or by issuing the `CLEAR` command.

The following example calculates:

```text
11 + (3 * 2) + (5 * 1) + (-2 * 3) = 16
ReLU(16 >>> 2) = 4
```

1. Issue `CLEAR`:

   ```text
   uio_in[2:0] = 001
   uio_in[3]   = 1 for one rising clock edge
   ```

2. Load bias `11`, which is hexadecimal `0x0B`:

   ```text
   LOAD_BIAS_LOW:  command = 010, uio_in[7:4] = B
   LOAD_BIAS_HIGH: command = 011, uio_in[7:4] = 0
   ```

3. Issue the first MAC operation, `3 * 2`:

   ```text
   ui_in          = 0x23
   command        = 100
   command_valid  = 1 for one rising clock edge
   ```

4. Issue the second MAC operation, `5 * 1`:

   ```text
   ui_in          = 0x15
   command        = 100
   command_valid  = 1 for one rising clock edge
   ```

5. Issue the third MAC operation, `-2 * 3`. Signed INT4 `-2` is `0xE`:

   ```text
   ui_in          = 0x3E
   command        = 100
   command_valid  = 1 for one rising clock edge
   ```

6. Finish using ReLU with a right shift of `2`:

   ```text
   command        = 101
   uio_in[7:4]    = 2
   command_valid  = 1 for one rising clock edge
   ```

7. Check the outputs:

   ```text
   uo_out[3:0] = 4
   uo_out[4]   = 1 for one clock
   uo_out[5]   = 0
   uo_out[6]   = 0
   uo_out[7]   = 1
   ```

For RTL simulation, compile the files in this order:

```tcl
vlog int4_mac.v
vlog activation_quantizer.v
vlog tinynpu4_core.v
vlog tt_um_tinynpu4.v
vlog tb_tinynpu4_core.v
```

Then run the core testbench:

```tcl
vsim work.tb_tinynpu4_core
run -all
```

The supplied self-checking core testbench performs 31 checks covering reset, command gating, bias loading, signed MAC operations, ReLU, linear output, saturation, status signals, and positive and negative accumulator overflow.

Expected final message:

```text
PASSED: 31
FAILED: 0
ALL TESTS PASSED
```

## External hardware

No external hardware is required. The project does not use a PMOD, external memory, display, or other peripheral.

The Tiny Tapeout demo board may optionally be used to provide the clock and input values and to observe `uo_out` using LEDs or a logic analyzer.

