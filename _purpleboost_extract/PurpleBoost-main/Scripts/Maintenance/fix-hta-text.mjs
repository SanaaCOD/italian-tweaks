import fs from "fs";
import path from "path";

const p = process.argv[2] || path.resolve("Unreal.hta");
let t = fs.readFileSync(p, "utf8");

t = t.replace(/\uFFFD\s*\u0019/g, "\u2192");
t = t.replace(/\uFFFD/g, "");
t = t.replace(/\u0019/g, "");

const entityMap = [
  ["P&#233;riph&#233;rique", "Périphériques"],
  ["p&#233;riph&#233;rique", "périphérique"],
  ["p&#233;riph&#233;riques", "périphériques"],
  ["R&#233;", "Ré"],
  ["r&#233;", "ré"],
  ["d&#233;", "dé"],
  ["am&#233;", "amé"],
  ["&#238;", "î"],
  ["&#232;", "è"],
  ["&#233;", "é"],
  ["&#39;", "'"],
];
for (const [a, b] of entityMap) t = t.split(a).join(b);

fs.writeFileSync(p, t, "utf8");
console.log("FFFD:", (t.match(/\uFFFD/g) || []).length);
console.log("&# entities:", (t.match(/&#\d+;/g) || []).length);
