// ai-engine — el corazón de IA de Botikin.
// Flujo de TODA acción de IA:
//   1. Autenticar usuario (JWT)
//   2. Portero de tokens: verificar saldo y descontar (consume_tokens)
//      → sin tokens: 402 con invitación a upgrade, NO se llama a Claude
//   3. Llamar a Claude (opus texto / sonnet visión)
//   4. Registrar consumo (lo hace el RPC) y devolver saldo actualizado
// Si Claude falla después de descontar, se reembolsa.

import { error, handleOptions, json } from "../_shared/http.ts";
import { adminClient, userFromRequest } from "../_shared/supabase.ts";
import {
  chargeCost,
  consumeTokens,
  refundTokens,
  TokenAction,
} from "../_shared/tokens.ts";
import {
  analyzeImage,
  analyzeText,
  extractJSON,
} from "../_shared/anthropic.ts";

interface AIBody {
  action:
    | "analyze_prescription"
    | "analyze_cabinet"
    | "generate_whatsapp"
    | "assistant_chat";
  prescription_id?: string;
  contexto?: string; // para generate_whatsapp y assistant_chat
  mensaje?: string;  // para assistant_chat
}

interface PrescriptionAnalysis {
  medico: string;
  fecha_receta: string;
  medicamentos: Array<{
    nombre: string;
    dosis: string;
    posologia: string;
    indicaciones: string;
  }>;
}

const ACTION_MAP: Record<AIBody["action"], TokenAction> = {
  analyze_prescription: "prescription_analysis",
  analyze_cabinet: "cabinet_analysis",
  generate_whatsapp: "whatsapp_message",
  assistant_chat: "assistant_chat",
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return error("method_not_allowed", "Usa POST", 405);

  const user = await userFromRequest(req);
  if (!user) return error("unauthorized", "Sesión inválida o expirada", 401);

  let body: AIBody;
  try {
    body = await req.json();
  } catch {
    return error("bad_request", "Body JSON inválido");
  }

  const tokenAction = ACTION_MAP[body.action];
  if (!tokenAction) return error("bad_request", "action desconocida");

  const admin = adminClient();
  const cost = chargeCost(tokenAction);

  // ── El portero: sin tokens no hay IA ─────────────────────────
  const gate = await consumeTokens(admin, user.id, tokenAction, cost);
  if (gate instanceof Response) return gate;

  try {
    switch (body.action) {
      case "analyze_prescription": {
        if (!body.prescription_id) {
          throw new ValidationError("prescription_id es obligatorio");
        }
        const { data: rx } = await admin
          .from("prescriptions")
          .select("id, foto_path, user_id")
          .eq("id", body.prescription_id)
          .eq("user_id", user.id)
          .single();
        if (!rx) throw new ValidationError("Receta no encontrada");

        // Descargar la foto desde Storage (bucket privado)
        const { data: file, error: dlErr } = await admin.storage
          .from("prescriptions")
          .download(rx.foto_path);
        if (dlErr || !file) throw new Error("No se pudo leer la foto de la receta");
        const bytes = new Uint8Array(await file.arrayBuffer());
        let binary = "";
        for (let i = 0; i < bytes.length; i += 0x8000) {
          binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
        }
        const base64 = btoa(binary);
        const mediaType = rx.foto_path.endsWith(".png") ? "image/png" : "image/jpeg";

        const result = await analyzeImage(
          "Eres un asistente farmacéutico chileno experto en leer recetas médicas manuscritas e impresas. Respondes SOLO con JSON válido.",
          `Lee esta receta médica y extrae la información en este formato JSON exacto:
{
  "medico": "nombre del médico",
  "fecha_receta": "fecha en formato YYYY-MM-DD (si no aparece, usa null)",
  "medicamentos": [
    {
      "nombre": "nombre comercial o genérico",
      "dosis": "ej: 500mg",
      "posologia": "ej: 1 comprimido cada 8 horas por 7 días",
      "indicaciones": "ej: tomar con comida"
    }
  ]
}
Si algo no se puede leer, usa cadena vacía. No inventes medicamentos.`,
          base64,
          mediaType,
        );

        const analysis = extractJSON<PrescriptionAnalysis>(result.text);

        await admin
          .from("prescriptions")
          .update({ analysis })
          .eq("id", rx.id);

        // Cruce contra el botiquín: ¿ya lo tienes o hay que comprarlo?
        const { data: meds } = await admin
          .from("medicines")
          .select("nombre")
          .eq("user_id", user.id);
        const owned = (meds ?? []).map((m) => normalize(m.nombre));
        const medicamentos = (analysis.medicamentos ?? []).map((m) => ({
          ...m,
          ya_lo_tienes: owned.some((o) =>
            o.includes(normalize(m.nombre)) || normalize(m.nombre).includes(o)
          ),
        }));

        return json({
          resultado: { ...analysis, medicamentos },
          tokens_consumidos: cost,
          tokens_restantes: gate.tokensRestantes,
        });
      }

      case "analyze_cabinet": {
        const { data: meds } = await admin
          .from("medicines")
          .select("nombre, dosis, unidades, fecha_vencimiento")
          .eq("user_id", user.id)
          .order("fecha_vencimiento");
        if (!meds || meds.length === 0) {
          throw new ValidationError("Tu botiquín está vacío: agrega remedios primero");
        }

        const hoy = new Date().toISOString().slice(0, 10);
        const result = await analyzeText(
          "Eres un asistente farmacéutico chileno. Analizas botiquines familiares y priorizas alertas de vencimiento. Hablas en español de Chile, cercano y claro. Respondes SOLO con JSON válido.",
          `Hoy es ${hoy}. Este es el botiquín:
${JSON.stringify(meds, null, 2)}

Devuelve JSON con este formato:
{
  "alertas": [
    { "medicamento": "nombre", "prioridad": "alta|media|baja",
      "mensaje": "ej: tu Paracetamol vence en 5 días, úsalo pronto" }
  ],
  "resumen": "una frase con el estado general del botiquín"
}
Ordena las alertas por prioridad. Los vencidos siempre son prioridad alta.`,
        );

        const analysis = extractJSON<Record<string, unknown>>(result.text);
        return json({
          resultado: analysis,
          tokens_consumidos: cost,
          tokens_restantes: gate.tokensRestantes,
        });
      }

      case "generate_whatsapp": {
        if (!body.contexto) {
          throw new ValidationError("contexto es obligatorio");
        }
        const result = await analyzeText(
          "Redactas recordatorios de salud por WhatsApp en español de Chile. Naturales, cálidos y breves (máximo 2 frases), jamás robóticos. Ejemplo del tono: 'Hola mamá, recuerda tomar el Omeprazol 20mg en ayunas esta mañana. ¡Buen día!'. Respondes SOLO con el texto del mensaje, sin comillas.",
          `Redacta un mensaje de WhatsApp para este contexto: ${body.contexto}`,
          512,
        );
        return json({
          resultado: { texto: result.text.trim() },
          tokens_consumidos: cost,
          tokens_restantes: gate.tokensRestantes,
        });
      }

      case "assistant_chat": {
        if (!body.mensaje) {
          throw new ValidationError("mensaje es obligatorio");
        }
        const { data: meds } = await admin
          .from("medicines")
          .select("nombre, dosis, unidades, fecha_vencimiento")
          .eq("user_id", user.id);

        const result = await analyzeText(
          `Eres el asistente de salud de Botikin, en español de Chile. Ayudas con dudas sobre el botiquín familiar del usuario. NO das diagnósticos ni reemplazas al médico; ante síntomas serios recomiendas consultar. Botiquín actual del usuario: ${
            JSON.stringify(meds ?? [])
          }`,
          body.mensaje,
          1024,
        );
        return json({
          resultado: { respuesta: result.text.trim() },
          tokens_consumidos: cost,
          tokens_restantes: gate.tokensRestantes,
        });
      }
    }
  } catch (e) {
    // Claude o la validación fallaron después de descontar: reembolso.
    await refundTokens(admin, user.id, tokenAction, cost);
    if (e instanceof ValidationError) {
      return error("bad_request", e.message, 422);
    }
    console.error("ai-engine error:", e);
    return error(
      "ai_failed",
      "El análisis falló y no se descontaron tokens. Intenta de nuevo.",
      502,
    );
  }

  return error("bad_request", "action desconocida");
});

class ValidationError extends Error {}

function normalize(s: string): string {
  return s.toLowerCase()
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ").trim();
}
