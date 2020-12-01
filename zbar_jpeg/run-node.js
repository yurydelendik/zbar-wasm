const fs = require("fs");

async function init() {
  const stub_buf = fs.readFileSync("./wasi-stub.wasm");
  let memory;
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
    },
  });

  const buf = fs.readFileSync("./zbar_jpeg.wasm");
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
    const img = fs.readFileSync("./IMG_0837.jpg");

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
        if (Buffer.from(str.subarray(0, len)).toString() != "9780195019193")
          throw "Incorrect output";
      }

      i.destroy_image(d);
    }
    console.log(Date.now() - t);

    i.destroy_processor(p);
  })
  .catch(console.error);
