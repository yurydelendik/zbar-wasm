async function init() {
  const buf = read("./test.wasm", "binary");
  const i = await WebAssembly.instantiate(buf);
  memory = i.instance.exports.memory;
  return i.instance.exports;
}

init()
  .then((i) => {
    i._initialize();

    const t = Date.now();
    for (let a = 0; a < 500; a++) {
      i.test();
    }
    const d = Date.now() - t;
    console.log(d);
  })
  .catch(console.error);
