#!/bin/bash

SEED=$(( $(date +%s%N) % 2147483647 ))

TOP_MODULE="tb_ising_32x8x4"
SNAPSHOT="sim_tb_ising_32x8x4"

echo "Using SEED=$SEED"
echo "Top module: $TOP_MODULE"
echo "Snapshot  : $SNAPSHOT"

# Compile Verilog source files
xvlog \
    flex_spin_top.v \
    spin_operator.v \
    four_spin_registers.v \
    tb_ising_32x8x4.v

# Elaborate the top-level testbench
xelab "$TOP_MODULE" \
    -debug wave \
    -s "$SNAPSHOT"

# Run simulation
xsim "$SNAPSHOT" \
    -gui \
    -wdb simulate_xsim_tb_ising_32x8x4.wdb \
    -testplusarg SEED=$SEED
