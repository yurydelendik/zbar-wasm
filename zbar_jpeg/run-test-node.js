// node --experimental-wasm-simd --wasm-simd-post-mvp run-test-node.js
const fs = require("fs");

async function init() {
  const buf = fs.readFileSync("./test.wasm");
  const i = await WebAssembly.instantiate(buf);
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
