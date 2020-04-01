
# Get sources

```
curl -L https://sourceforge.net/projects/zbar/files/zbar/0.10/zbar-0.10.tar.bz2 | tar -xjf -
curl -L https://sourceforge.net/projects/libjpeg-turbo/files/2.0.4/libjpeg-turbo-2.0.4.tar.gz | tar -xzf -
```

# Build wasm

## libjpeg

```
cd libjpeg-turbo-2.0.4
cmake -DCMAKE_C_COMPILER=$WASI_PREFIX/bin/clang -DCMAKE_BUILD_TYPE=Debug .
make jpeg-static
$WASI_PREFIX/bin/ranlib libjpeg.a
```

## libzbar

```
cd zbar-0.10
./configure --without-xshm --without-xv --without-imagemagick --without-gtk --without-python --without-qt --enable-shared=no --disable-pthread --disable-video CFLAGS="-g -O0"
make CC=$WASI_PREFIX/bin/clang INCLUDES=-I$PWD/../libjpeg-turbo-2.0.4/
$WASI_PREFIX/bin/ranlib zbar/.libs/libzbar.a
```

```
$WASI_PREFIX/bin/clang test_decode.c -o test_decode.wasm -I../../libjpeg-turbo-2.0.4/ -I../include ../zbar/.libs/libzbar.a ../../libjpeg-turbo-2.0.4/libjpeg.a
wasmtime test_decode.wasm 
```

# decode_jpeg.c

```
$WASI_PREFIX/bin/clang decode_jpeg.c -o decode_jpeg.wasm -Ilibjpeg-turbo-2.0.4/ -Izbar-0.10/include zbar-0.10/zbar/.libs/libzbar.a libjpeg-turbo-2.0.4/libjpeg.a -g -O0
wasmtime run -g --opt-level 0 --disable-cache --mapdir .::$PWD decode_jpeg.wasm
```
