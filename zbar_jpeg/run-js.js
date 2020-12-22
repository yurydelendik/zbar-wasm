async function init() {
  const stub_buf = read("./wasi-stub.wasm", "binary");
  let memory;
  let log = "";
  const stub = await WebAssembly.instantiate(stub_buf, {
    js: {
      not_impl(code) {
        console.error("NOT_IMPLEMENTED", code);
      },
      put_i32(offset, val) {
        new DataView(memory.buffer, offset, 4).setInt32(0, val, true);
      },
      set_time(offset) {
        const n = BigInt(0); // process.hrtime.bigint();
        new DataView(memory.buffer, offset, 8).setBigUint64(0, n, true);
      },
      write(ios, c, pw) {
        const d = new DataView(memory.buffer, ios, 8 * c);
        let w = 0;
        for (let i = 0; i < c; i++) {
          const p = d.getInt32(i * 8, true), len = d.getInt32(i * 8 + 4, true);
          const str = new Uint8Array(memory.buffer, p, len);
          log += String.fromCharCode.apply(null, str.subarray(0, len));
          while (log.includes('\n')) {
            const p = log.split('\n');
            log = p.pop();
            p.forEach(i => console.log(i));
          }
          w += len;
        }
        new DataView(memory.buffer, pw, 4).setInt32(0, w, true);
      },     
    },
  });

  const buf = read("./zbar_jpeg.wasm", "binary");
  const imports = {
    wasi_snapshot_preview1: stub.instance.exports,
  };
  const i = await WebAssembly.instantiate(buf, imports);
  memory = i.instance.exports.memory;
  return i.instance.exports;
}

init()
  .then((i) => {
    i._start();
    const memory = i.memory;

    const p = i.create_processor();
    const img = read("./IMG_0837.jpg", "binary");

    const t = Date.now();
    for (let a = 0; a < 50; a++) {
      const img_p = i.malloc(img.length);
      new Uint8Array(memory.buffer, img_p, img.length).set(img);
      const d = i.process_jpeg_image(p, img_p, img.length);
      i.free(img_p);

      for (let s = i.get_image_first_symbol(d); s; s = i.get_next_symbol(s)) {
        const code = i.get_symbol_data(s);
        const str = new Uint8Array(memory.buffer, code);
        let len = 0;
        while (str[len]) len++;
        if (
          String.fromCharCode.apply(null, str.subarray(0, len)) !=
          "9780195019193"
        )
          throw "Incorrect output";
      }

      i.destroy_image(d);
    }
    console.log(Date.now() - t);

    i.destroy_processor(p);
  })
  .catch(console.error);
