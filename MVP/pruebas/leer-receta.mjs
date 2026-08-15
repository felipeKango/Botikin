// Prueba real: ¿Claude lee la receta de Bruno y saca la pauta completa?
import fs from "node:fs";

const KEY = process.env.ANTHROPIC_API_KEY;
const pdf = fs.readFileSync(process.argv[2]).toString("base64");

const ESQUEMA = {
  type: "object",
  additionalProperties: false,
  required: ["paciente", "medico", "fecha_atencion", "medicamentos"],
  properties: {
    paciente: { type: "string" },
    edad_texto: { type: "string" },
    medico: { type: "string" },
    centro: { type: "string" },
    fecha_atencion: { type: "string" },
    medicamentos: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["principio_activo", "concentracion", "forma", "dosis_cantidad",
                   "dosis_unidad", "duracion_tipo", "fecha_inicio"],
        properties: {
          principio_activo: { type: "string" },
          concentracion: { type: "string" },
          forma: { type: "string" },
          marca_recomendada: { type: "string" },
          dosis_cantidad: { type: "number" },
          dosis_unidad: { type: "string" },
          cada_horas: { type: ["number", "null"] },
          duracion_tipo: { type: "string", enum: ["dias", "permanencia", "sos"] },
          duracion_dias: { type: ["number", "null"] },
          fecha_inicio: { type: "string" },
          observaciones: { type: "string" },
        },
      },
    },
  },
};

const SISTEMA = `Lees recetas médicas chilenas y extraes la pauta EXACTA que escribió el médico.

Reglas que no se rompen:
- Lee TODAS las páginas. Las observaciones de un medicamento pueden continuar en la siguiente.
- "por Permanencia" = tratamiento crónico: duracion_tipo "permanencia", duracion_dias null.
- "por N Días" = duracion_tipo "dias", duracion_dias N.
- "SOS" = a demanda: duracion_tipo "sos", cada_horas null (aunque el papel diga "cada 6 horas",
  un SOS no tiene horario fijo).
- El título de cada ítem trae principio activo + concentración + forma farmacéutica. Sepáralos.
- "Recomendado:" es la marca comercial sugerida, NO el principio activo.
- Si un dato no está en el documento, deja el campo vacío. NUNCA inventes una dosis.`;

const r = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: {
    "x-api-key": KEY,
    "anthropic-version": "2023-06-01",
    "content-type": "application/json",
  },
  body: JSON.stringify({
    model: "claude-opus-5",
    max_tokens: 16000,
    system: SISTEMA,
    output_config: { format: { type: "json_schema", schema: ESQUEMA }, effort: "high" },
    messages: [{
      role: "user",
      content: [
        { type: "document", source: { type: "base64", media_type: "application/pdf", data: pdf } },
        { type: "text", text: "Extrae la receta completa." },
      ],
    }],
  }),
});

const d = await r.json();
if (d.error) { console.error("❌", d.error.type, d.error.message); process.exit(1); }
if (d.stop_reason === "refusal") { console.error("❌ refusal:", d.stop_details); process.exit(1); }

const texto = d.content.find((b) => b.type === "text").text;
console.log(JSON.stringify(JSON.parse(texto), null, 2));
console.log("\n--- tokens:", d.usage.input_tokens, "in /", d.usage.output_tokens, "out");
