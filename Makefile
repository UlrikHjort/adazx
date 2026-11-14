# AdaZX build helpers
all:
	mkdir -p bin obj
	gprbuild -P emu.gpr -j0
	ln -sf adazx bin/adazx-forge

tests: all
	mkdir -p obj/tests
	gprbuild -q -P tests/tests.gpr
	sh tests/run_tests.sh

# ZEXALL: every Z80 instruction with all flags (about a minute)
zexall: all
	mkdir -p obj/tests
	gprbuild -q -P tests/tests.gpr
	bin/zex_test tests/z80/zexall.com

clean:
	gprclean -q -P emu.gpr
	rm -rf obj bin

.PHONY: all tests zexall clean
