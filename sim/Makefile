# ChipTop simulation (iverilog)
#
#   make              run spi and i2c tests
#   make spi | i2c    run one test
#   make spi DUMP=1   also write build/tb_spi.vcd
#   make wave_spi     run with dump and open the VCD in gtkwave (wave_i2c likewise)
#   make clean
#
# On Windows use mingw32-make (sh must be on PATH).

IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave
DUMP     ?= 0

BUILD  := build
TESTS  := spi i2c
MODELS := models/sim_cells.v
RTL    := ../rtl/B_SPICtl.v ../rtl/B_I2CCtl.v ../rtl/ChipTop.v

# -g2012 : B_I2CCtl.v uses "#10ps"
IVFLAGS := -g2012 -I.

ifeq ($(DUMP),1)
VVPFLAGS := +dump
endif

.PHONY: all $(TESTS) $(addprefix wave_,$(TESTS)) clean

all: $(TESTS)

$(BUILD):
	mkdir -p $(BUILD)

# models first : its `timescale applies to the files after it
$(BUILD)/tb_%.vvp: tb_%.v task_%.v $(MODELS) $(RTL) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -s tb_$* -o $@ $(MODELS) $(RTL) tb_$*.v

$(TESTS): %: $(BUILD)/tb_%.vvp
	$(VVP) -n $< $(VVPFLAGS) > $(BUILD)/tb_$*.log; cat $(BUILD)/tb_$*.log; grep -q "RESULT: PASS" $(BUILD)/tb_$*.log

wave_%:
	$(MAKE) $* DUMP=1
	$(GTKWAVE) $(BUILD)/tb_$*.vcd &

clean:
	rm -rf $(BUILD)
