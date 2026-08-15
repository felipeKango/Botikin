// Prueba real: ¿Claude lee la caja y, sobre todo, ADMITE lo que no puede leer?
//
//   set -a && . ../.env && set +a
//   node leer-envase.mjs ../CajaParacetamol.webp
import fs from "node:fs";
import path from "node:path";

const KEY = process.env.ANTHROPIC_API_KEY;
const ruta = process.argv[2];
const bytes = fs.readFileSync(ruta);
const MIME = { ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
               ".png": "image/png", ".gif": "image/gif" }[path.extname(ruta).toLowerCase()];
if (!MIME) { console.error("Formato no soportado:", ruta); process.exit(1); }

const ESQUEMA = {
  type: "object",
  additionalProperties: false,
  required: ["principio_activo", "concentracion", "forma", "cantidad", "unidad",
             "marca", "fecha_vencimiento", "lote", "dudas"],
  properties: {
    principio_activo:  { type: ["string", "null"] },
    concentracion:     { type: ["string", "null"] },
    forma:             { type: ["string", "null"] },
    cantidad:          { type: ["number", "null"] },
    unidad:            { type: ["string", "null"] },
    marca:             { type: ["string", "null"] },
    laboratorio:       { type: ["string", "null"] },
    fecha_vencimiento: { type: ["string", "null"], description: "AAAA-MM o AAAA-MM-DD. null si no se lee." },
    lote:              { type: ["string", "null"] },
    dudas: {
      type: "array",
      description: "Un campo por cada dato que NO se pudo leer, con dónde buscarlo en el envase.",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["campo", "pregunta"],
        properties: {
          campo:    { type: "string" },
          pregunta: { type: "string", description: "Cómo preguntárselo al usuario, en español de Chile." },
        },
      },
    },
  },
};

const SISTEMA = `Lees fotos de cajas de medicamentos chilenos y extraes lo que está IMPRESO.

La regla que no se rompe: **lo que no está en la imagen, no se inventa.**
Si un dato no se ve —porque está en otra cara de la caja, salió cortado, hay
reflejo, o el relieve no se distingue— deja el campo en null y agrega una
entrada en "dudas" diciéndole al usuario dónde mirarlo.

- principio_activo: el compuesto, no la marca. "PARACETAMOL", no "Panadol".
- concentracion: como está impresa. "500 mg", "100 mg/mL".
- forma: comprimido, jarabe, solución oral, aerosol, sobre, cápsula...
- cantidad + unidad: "16 Comprimidos" → cantidad 16, unidad "comprimido".
- marca: el nombre comercial si lo hay. Un genérico sin marca de fantasía
  puede no tener: entonces null, y NO es una duda (no falta nada).
- fecha_vencimiento: casi nunca está en la cara principal. Suele ir impresa
  o en relieve en una solapa lateral. Si no la ves, es null + duda.

Escribe las preguntas como se las dirías a alguien en la cocina de su casa,
corto y diciéndole dónde mirar.`;

const r = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: { "x-api-key": KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
  body: JSON.stringify({
    model: "claude-opus-5",
    max_tokens: 4000,
    system: SISTEMA,
    output_config: { format: { type: "json_schema", schema: ESQUEMA }, effort: "high" },
    messages: [{
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: MIME, data: bytes.toString("base64") } },
        { type: "text", text: "Lee esta caja." },
      ],
    }],
  }),
});

const d = await r.json();
if (d.error) { console.error("❌", d.error.type, d.error.message); process.exit(1); }
if (d.stop_reason === "refusal") { console.error("❌ refusal:", d.stop_details); process.exit(1); }

const out = JSON.parse(d.content.find((b) => b.type === "text").text);
console.log(JSON.stringify(out, null, 2));
console.log("\n--- tokens:", d.usage.input_tokens, "in /", d.usage.output_tokens, "out");
