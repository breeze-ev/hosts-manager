const fs = require("fs");
const path = require("path");
const { Resvg } = require("/tmp/hosts-icon-build/node_modules/@resvg/resvg-js");

const root = __dirname;
const styles = ["orbit", "aurora", "flat", "neon", "liquid", "prism"];

fs.mkdirSync(path.join(root, "previews"), { recursive: true });
fs.mkdirSync(path.join(root, "export"), { recursive: true });

for (const name of styles) {
  const svg = fs.readFileSync(path.join(root, `${name}.svg`), "utf8");

  const preview = new Resvg(svg, {
    fitTo: { mode: "width", value: 512 },
    font: { loadSystemFonts: true },
  });
  fs.writeFileSync(
    path.join(root, "previews", `${name}.png`),
    preview.render().asPng()
  );

  const full = new Resvg(svg, {
    fitTo: { mode: "width", value: 1024 },
    font: { loadSystemFonts: true },
  });
  fs.writeFileSync(
    path.join(root, "export", `${name}-1024.png`),
    full.render().asPng()
  );

  console.log("rendered", name);
}
