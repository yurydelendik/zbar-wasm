ZBAR_INCLUDES = \
  ../zbar-0.10/include

ZBAR_LIBS = \
  ../zbar-0.10/zbar/.libs/libzbar.a \
  ../libjpeg-turbo-2.0.4/build/libjpeg.a

CC = $(WASI_PREFIX)/bin/clang
RANLIB = $(WASI_PREFIX)/bin/ranlib
WAT2WASM = $(WABT)/wat2wasm
SIMD_FLAGS = -DWITH_SIMD=1

build: wasi-stub.wasm zbar_jpeg.wasm

wasi-stub.wasm: wasi-stub.wat
	$(WAT2WASM) -o wasi-stub.wasm wasi-stub.wat

zbar_jpeg.wasm: zbar_jpeg.c $(ZBAR_LIBS)
	$(CC) zbar_jpeg.c -o zbar_jpeg.wasm \
		$(addprefix -I, $(ZBAR_INCLUDES)) $(ZBAR_LIBS) \
		-nostartfiles -fvisibility=hidden \
		-Wl,--export=malloc,--export=free

test.wasm: ../libjpeg-turbo-2.0.4/build/libjpeg.a test.c
	$(CC) test.c -O2 -o test.wasm \
	-I$(PWD)/../libjpeg-turbo-2.0.4 \
	../libjpeg-turbo-2.0.4/build/libjpeg.a \
	-nostartfiles -fvisibility=hidden -Wl,--entry=_initialize

test-no-simd.wasm: ../libjpeg-turbo-2.0.4/build/libjpeg.a test.c
	$(CC) test.c -O2 -DDISABLE_SIMD -o test-no-simd.wasm \
	-I$(PWD)/../libjpeg-turbo-2.0.4 \
	../libjpeg-turbo-2.0.4/build/libjpeg.a \
	-nostartfiles -fvisibility=hidden -Wl,--entry=_initialize

../zbar-0.10/zbar/.libs/libzbar.a:../libjpeg-turbo-2.0.4/build/libjpeg.a
	cd ../zbar-0.10; ./configure --without-xshm --without-xv --without-imagemagick --without-gtk --without-python --without-qt --enable-shared=no --disable-pthread --disable-video
	make -C ../zbar-0.10 CC=$(CC) INCLUDES="-I$(PWD)/../libjpeg-turbo-2.0.4 -I$(PWD)/../libjpeg-turbo-2.0.4/build"
	$(RANLIB) ../zbar-0.10/zbar/.libs/libzbar.a

../libjpeg-turbo-2.0.4/build/libjpeg.a:
	mkdir -p ../libjpeg-turbo-2.0.4/build
	cd ../libjpeg-turbo-2.0.4/build; cmake -DCMAKE_C_COMPILER=$(CC) ${SIMD_FLAGS} -S .. -B .
	make -C ../libjpeg-turbo-2.0.4/build jpeg-static
	$(RANLIB) ../libjpeg-turbo-2.0.4/build/libjpeg.a

clean:
	make -C ../zbar-0.10/ clean
	rm -rf ../libjpeg-turbo-2.0.4/build
#	-rm zbar_jpeg.wasm wasi-stub.wasm test.wasm
