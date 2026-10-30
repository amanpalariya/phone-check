import { cp, mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
const root = fileURLToPath(new URL("../", import.meta.url));
const out = path.join(root, "dist");
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
for (const name of ["index.html", "style.css", "main.js", "theme.js"])
  await cp(path.join(root, name), path.join(out, name));
await cp(path.join(root, "public"), out, { recursive: true });
console.log("Built website/dist");
