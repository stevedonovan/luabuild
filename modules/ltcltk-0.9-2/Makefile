LUA_INC_DIR=-I/usr/local/include
TCL_INC_DIR=-I/usr/include/tk -I/usr/include
LUA_LIB_DIR=-L/usr/local/lib
TCL_LIB_DIR=-L/usr/include
TCL_LIB=tcl8.5

INC_DIRS=${LUA_INC_DIR} ${TCL_INC_DIR}
LIB_DIRS=${LUA_LIB_DIR} ${TCL_LIB_DIR}

INSTALL_ROOT=/usr/local
SO_INST_ROOT=${INSTALL_ROOT}/lib/lua/5.1
LUA_INST_ROOT=${INSTALL_ROOT}/share/lua/5.1

all:	ltcl.so

ltcl.o: ltcl.c
	gcc -O2 ${INC_DIRS} -c $< -o $@

ltcl.so: ltcl.o
	gcc -shared -fPIC -o $@ ${LIB_DIRS} $< -l${TCL_LIB}

install: all ltk.lua
	cp ltcl.so ${SO_INST_ROOT}
	cp ltk.lua ${LUA_INST_ROOT}

clean:
	find . -name "*~" -exec rm {} \;
	rm -f *.o *.so *.func *.ps core
	for dir in . doc samples; \
	do \
		rm -f $dir/.DS_Store; \
		rm -f $dir/._*; \
	done

