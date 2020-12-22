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
          while (log.includes("\n")) {
            const p = log.split("\n");
            log = p.pop();
            p.forEach((i) => console.log(i));
          }
          w += len;
        }
        new DataView(memory.buffer, pw, 4).setInt32(0, w, true);
      },
    },
  });

  const buf = read("./test.wasm", "binary");
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

    const t = Date.now();
    for (let a = 0; a < 500; a++) {
      i.test();
    }
    const d = Date.now() - t;
    console.log(d);
  })
  .catch(console.error);
