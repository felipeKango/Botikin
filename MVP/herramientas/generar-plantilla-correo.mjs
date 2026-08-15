// La plantilla del correo vive en mail/botikin-welcome-email.html.
// Esto la compila a un módulo JS para que la función serverless la importe
// sin leer del disco (Vercel solo empaqueta lo que se importa).
//   node herramientas/generar-plantilla-correo.mjs
import fs from "node:fs";
const html = fs.readFileSync("mail/botikin-welcome-email.html", "utf8");
fs.writeFileSync("landing/api/_plantilla-correo.js",
  `// ⚠️ GENERADO — no editar a mano.\n` +
  `// Fuente: mail/botikin-welcome-email.html\n` +
  `// Regenerar: node herramientas/generar-plantilla-correo.mjs\n` +
  `export const PLANTILLA = ${JSON.stringify(html)};\n`);
console.log(`plantilla compilada · ${html.length} caracteres`);
