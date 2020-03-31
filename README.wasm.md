
# Get sources

```
curl -L https://sourceforge.net/projects/zbar/files/zbar/0.10/zbar-0.10.tar.bz2 | tar -xjf -
curl -L https://sourceforge.net/projects/libjpeg-turbo/files/2.0.4/libjpeg-turbo-2.0.4.tar.gz | tar -xzf -
```

# Build wasm

## libjpeg

```
cd libjpeg-turbo-2.0.4
cmake -DCMAKE_C_COMPILER=$WASI_PREFIX/bin/clang .
make jpeg-static
$WASI_PREFIX/bin/ranlib libjpeg.a
```

## libzbar

```
cd zbar-0.10
./configure --without-xshm --without-xv --without-imagemagick --without-gtk --without-python --without-qt --enable-shared=no --disable-pthread --disable-video
make CC=$WASI_PREFIX/bin/clang INCLUDES=-I$PWD/../libjpeg-turbo-2.0.4/
$WASI_PREFIX/bin/ranlib zbar/.libs/libzbar.a
```

```
$WASI_PREFIX/bin/clang test_decode.c -o test_decode.wasm -I../../libjpeg-turbo-2.0.4/ -I../include ../zbar/.libs/libzbar.a ../../libjpeg-turbo-2.0.4/libjpeg.a
wasmtime test_decode.wasm 
```
