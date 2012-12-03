LIBDIRS= -y . -y src -y unisims

INCDIRS= +incdir+"."  +incdir+"src" +incdir+"unisims"

TEST_OPTIONS = 

MODELS = models

NCRTL_PARAMETERS = \
	+define+nobanner \
	+ncaccess+rwc \
	+libext+.v+.ismvmd+.vh \
	+librescan \
	+no_pulse_msg \
	+define+nosyncchecks \
	$(INCDIRS) $(LIBDIRS) \
	$(RTL_LIBRARIES) \
	$(TEST_OPTIONS) \
	+define+SIM \
	tb.v \
	+define+RD_SSCOMMAND

all: ncrtl

%.s: %.c
	cc65 -Os $+

%.o: %.s
	ca65 --listing -I /usr/local/lib/cc65/asminc $+

ncrtl:  
	ncverilog $(NCRTL_PARAMETERS)  

clean:
	rm -rf INCA_libs hst_err.log hst_err.log hst_res.log\
	ncverilog.key ncverilog.log results.dsn results.trn
