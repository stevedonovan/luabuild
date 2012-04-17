CFLAGS=-fPIC

linenoise.so: linenoise.o
	gcc -o $@ -shared $^ -llinenoise

clean:
	rm -f *.o *.so
