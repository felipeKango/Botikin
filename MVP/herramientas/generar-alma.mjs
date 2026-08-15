// soul.md es la fuente de verdad del carácter del agente.
// Este script lo compila a un módulo TS para que la Edge Function lo importe
// sin leer del disco. Correr después de cada cambio en soul.md:
//   node herramientas/generar-alma.mjs
import fs from "node:fs";

const alma = fs.readFileSync("soul.md", "utf8");
const salida = `// ⚠️ GENERADO — no editar a mano.
// Fuente de verdad: soul.md · regenerar: node herramientas/generar-alma.mjs
export const ALMA = ${JSON.stringify(alma)};
`;
fs.writeFileSync("supabase/functions/_shared/alma.ts", salida);
console.log(`alma.ts generado · ${alma.length} caracteres`);
