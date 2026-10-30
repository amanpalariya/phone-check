import { cp, mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
const root = fileURLToPath(new URL("../", import.meta.url));
const out = path.resolve(root, "../docs");
await mkdir(out, { recursive: true });
for (const name of ["index.html", "style.css", "main.js", "theme.js"])
  await cp(path.join(root, name), path.join(out, name));
await cp(path.join(root, "public"), out, { recursive: true });
await writeFile(path.join(out, ".nojekyll"), "");
console.log("Built docs/ (preserving development documentation)");
