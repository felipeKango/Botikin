// El bucle del agente: Claude + herramientas contra la base.
// El carácter vive en soul.md (compilado a alma.ts). Acá vive la mecánica.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ALMA } from "./alma.ts";

const MODELO = "claude-opus-5";
const ANTHROPIC = "https://api.anthropic.com/v1/messages";

// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las inyecta Supabase sola en el
// runtime de las Edge Functions: no se configuran como secretos.
export const admin = (): SupabaseClient =>
  createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

// ── Las herramientas ────────────────────────────────────────
// El agente no escribe en la base por su cuenta: solo a través de esto,
// y cada una valida antes de guardar.

export const HERRAMIENTAS = [
  {
    name: "registrar_integrante",
    description:
      "Da de alta a una persona de la casa. Úsala apenas sepas nombre, sexo y " +
      "fecha de nacimiento. La edad NO se guarda: se calcula sola contra hoy, " +
      "así que la fecha es obligatoria — si el usuario dio la edad, pídele la fecha.",
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["nombre", "sexo", "fecha_nacimiento"],
      properties: {
        nombre: { type: "string", description: "Como lo llaman en la casa" },
        sexo: { type: "string", enum: ["femenino", "masculino", "otro", "no_dice"] },
        fecha_nacimiento: { type: "string", description: "AAAA-MM-DD" },
        es_titular: { type: "boolean", description: "true solo para quien escribe" },
      },
    },
  },
  {
    name: "registrar_medicamento",
    description:
      "Guarda una caja en el botiquín. ANTES de guardar busca duplicados por " +
      "principio activo + concentración + forma, y te los devuelve en 'duplicados' " +
      "para que se los digas al usuario. Si no leíste el vencimiento, mándalo null " +
      "y pregúntaselo por texto — nunca pidas otra foto ni inventes la fecha.",
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["principio_activo", "concentracion", "forma", "cantidad", "unidad"],
      properties: {
        principio_activo: { type: "string", description: "El compuesto, no la marca" },
        concentracion: { type: "string", description: '"500 mg", "100 mg/mL"' },
        forma: { type: "string", description: "comprimido, jarabe, solución oral, aerosol…" },
        cantidad: { type: "number" },
        unidad: { type: "string", description: "comprimido, mL, dosis, sobre" },
        marca: { type: "string" },
        fecha_vencimiento: { type: ["string", "null"], description: "AAAA-MM-DD, null si no se leyó" },
        lote: { type: ["string", "null"] },
        de_quien: { type: ["string", "null"], description: "Nombre del integrante, o null si es de la casa" },
      },
    },
  },
  {
    name: "descartar_medicamento",
    description: "Saca una caja del botiquín cuando el usuario dice que la botó o se acabó.",
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["medicamento_id", "motivo"],
      properties: {
        medicamento_id: { type: "string" },
        motivo: { type: "string", enum: ["descartado", "agotado"] },
      },
    },
  },
  {
    name: "crear_tratamiento",
    description:
      "Registra una pauta que prescribió un médico. Respeta los tres tipos de " +
      "duración: 'dias' lleva duracion_dias y cada_horas; 'permanencia' lleva " +
      "cada_horas y no termina; 'sos' NO lleva horario (cada_horas null) aunque " +
      "la receta diga cada cuántas horas.",
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["de_quien", "principio_activo", "concentracion", "forma",
                 "dosis_cantidad", "dosis_unidad", "duracion_tipo", "fecha_inicio"],
      properties: {
        de_quien: { type: "string", description: "Nombre del integrante" },
        principio_activo: { type: "string" },
        concentracion: { type: "string" },
        forma: { type: "string" },
        dosis_cantidad: { type: "number" },
        dosis_unidad: { type: "string" },
        cada_horas: { type: ["number", "null"] },
        duracion_tipo: { type: "string", enum: ["dias", "permanencia", "sos"] },
        duracion_dias: { type: ["number", "null"] },
        fecha_inicio: { type: "string", description: "AAAA-MM-DD" },
        observaciones: { type: "string" },
      },
    },
  },
];

// ── Ejecutores ──────────────────────────────────────────────

/** Resuelve o crea el producto. Marca resuelto=false: sin catálogo del ISP
 *  todavía, el producto NO participa de la deduplicación automática de la
 *  base — pero sí devolvemos las coincidencias para que el agente avise. */
async function resolverProducto(
  db: SupabaseClient,
  p: { principio_activo: string; concentracion: string; forma: string; marca?: string },
) {
  const clave = {
    principio_activo: p.principio_activo.trim().toLowerCase(),
    concentracion: p.concentracion.trim().toLowerCase(),
    forma_farmaceutica: p.forma.trim().toLowerCase(),
  };
  const { data: existente } = await db.from("productos").select("id, nombres_comerciales")
    .match(clave).maybeSingle();
  if (existente) {
    if (p.marca && !existente.nombres_comerciales?.includes(p.marca)) {
      await db.from("productos")
        .update({ nombres_comerciales: [...(existente.nombres_comerciales ?? []), p.marca] })
        .eq("id", existente.id);
    }
    return existente.id as string;
  }
  const { data: nuevo, error } = await db.from("productos")
    .insert({ ...clave, nombres_comerciales: p.marca ? [p.marca] : [] })
    .select("id").single();
  if (error) throw new Error(`producto: ${error.message}`);
  return nuevo.id as string;
}

async function integrantePorNombre(db: SupabaseClient, hogar: string, nombre?: string | null) {
  if (!nombre) return null;
  const { data } = await db.from("integrantes").select("id, nombre")
    .eq("hogar_id", hogar).eq("activo", true);
  const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
  return data?.find((i) => norm(i.nombre) === norm(nombre))?.id ?? null;
}

export async function ejecutar(
  db: SupabaseClient,
  hogar: string,
  nombre: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  switch (nombre) {
    case "registrar_integrante": {
      const { data, error } = await db.from("integrantes").insert({
        hogar_id: hogar,
        nombre: args.nombre,
        sexo: args.sexo,
        fecha_nacimiento: args.fecha_nacimiento,
        es_titular: args.es_titular ?? false,
      }).select("id, nombre, fecha_nacimiento").single();
      if (error) return { error: error.message };
      await db.from("hogares").update({ onboarding: "listo" }).eq("id", hogar);
      return { guardado: data };
    }

    case "registrar_medicamento": {
      const producto = await resolverProducto(db, args as never);

      // El cruce que define el producto: ¿esta casa ya tiene lo mismo?
      const { data: duplicados } = await db.from("medicamentos")
        .select("id, marca_comprada, cantidad, unidad, fecha_vencimiento, integrantes(nombre)")
        .eq("hogar_id", hogar).eq("producto_id", producto).eq("estado", "vigente");

      const { data: guardado, error } = await db.from("medicamentos").insert({
        hogar_id: hogar,
        producto_id: producto,
        integrante_id: await integrantePorNombre(db, hogar, args.de_quien as string),
        marca_comprada: args.marca ?? "",
        cantidad: args.cantidad,
        unidad: args.unidad,
        fecha_vencimiento: args.fecha_vencimiento ?? null,
        lote: args.lote ?? null,
        origen: "foto",
      }).select("id, cantidad, unidad, fecha_vencimiento").single();
      if (error) return { error: error.message };

      return {
        guardado,
        duplicados: (duplicados ?? []).map((d) => ({
          id: d.id,
          marca: d.marca_comprada,
          cantidad: d.cantidad,
          unidad: d.unidad,
          vence: d.fecha_vencimiento,
          de_quien: (d.integrantes as { nombre: string } | null)?.nombre ?? "la casa",
        })),
        falta_vencimiento: !args.fecha_vencimiento,
      };
    }

    case "descartar_medicamento": {
      const { error } = await db.from("medicamentos").update({
        estado: args.motivo,
        descartado_el: new Date().toISOString().slice(0, 10),
      }).eq("id", args.medicamento_id).eq("hogar_id", hogar);
      return error ? { error: error.message } : { ok: true };
    }

    case "crear_tratamiento": {
      const integrante = await integrantePorNombre(db, hogar, args.de_quien as string);
      if (!integrante) return { error: `No conozco a ${args.de_quien} en esta casa` };
      const producto = await resolverProducto(db, args as never);

      const tipo = args.duracion_tipo as string;
      const inicio = args.fecha_inicio as string;
      const termino = tipo === "dias" && args.duracion_dias
        ? new Date(Date.parse(inicio) + (args.duracion_dias as number) * 864e5)
            .toISOString().slice(0, 10)
        : null;

      const { data, error } = await db.from("tratamientos").insert({
        hogar_id: hogar,
        integrante_id: integrante,
        producto_id: producto,
        dosis_cantidad: args.dosis_cantidad,
        dosis_unidad: args.dosis_unidad,
        cada_horas: tipo === "sos" ? null : args.cada_horas,
        duracion: tipo,
        duracion_dias: tipo === "dias" ? args.duracion_dias : null,
        fecha_inicio: inicio,
        fecha_termino: termino,
        observaciones: args.observaciones ?? null,
      }).select("id, fecha_termino").single();
      // El CHECK de la base rechaza una pauta incoherente (sos con horario,
      // permanencia con término). Si llega acá, es un error del agente.
      return error ? { error: error.message } : { guardado: data };
    }

    default:
      return { error: `herramienta desconocida: ${nombre}` };
  }
}

// ── El bucle ────────────────────────────────────────────────

type Bloque = Record<string, unknown>;

/** Corre el agente hasta que deje de pedir herramientas. Devuelve el texto
 *  que hay que mandarle al usuario. */
export async function responder(
  db: SupabaseClient,
  hogar: string,
  entrada: Bloque[],
  historial: { role: string; content: unknown }[] = [],
): Promise<string> {
  const { data: contexto } = await db.rpc("contexto_hogar", { p_hogar: hogar });

  const sistema = [
    { type: "text", text: ALMA, cache_control: { type: "ephemeral" } },
    {
      type: "text",
      text:
        `## Lo que sabes ahora de esta casa\n\n` +
        "```json\n" + JSON.stringify(contexto, null, 2) + "\n```\n\n" +
        `El campo "hoy" es la fecha real de hoy en Chile. Úsala para todo ` +
        `cálculo de edad, vencimiento y duración de tratamiento. Las edades ya ` +
        `vienen calculadas: no las recalcules.\n\n` +
        (contexto?.onboarding === "nuevo"
          ? `Esta casa todavía no te ha contado quiénes viven en ella. Empieza por ahí, ` +
            `una pregunta a la vez, y cierra pidiendo la primera foto de una caja.`
          : `Ya conoces la casa. Responde a lo que te escriban.`),
    },
  ];

  const mensajes = [...historial, { role: "user", content: entrada }];

  for (let vuelta = 0; vuelta < 6; vuelta++) {
    const r = await fetch(ANTHROPIC, {
      method: "POST",
      headers: {
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: 8000,
        system: sistema,
        tools: HERRAMIENTAS,
        output_config: { effort: "medium" },
        messages: mensajes,
      }),
    });

    const d = await r.json();
    if (d.error) throw new Error(`claude: ${d.error.type} — ${d.error.message}`);
    if (d.stop_reason === "refusal") {
      return "Perdona, con eso no te puedo ayudar. Si es algo de salud, consúltalo " +
             "en un centro asistencial.";
    }

    mensajes.push({ role: "assistant", content: d.content });

    const usos = d.content.filter((b: Bloque) => b.type === "tool_use");
    if (usos.length === 0) {
      return d.content.filter((b: Bloque) => b.type === "text")
        .map((b: Bloque) => b.text).join("\n").trim();
    }

    const resultados = [];
    for (const u of usos) {
      let salida: unknown;
      try {
        salida = await ejecutar(db, hogar, u.name, u.input);
      } catch (e) {
        salida = { error: String(e) };
      }
      resultados.push({
        type: "tool_result",
        tool_use_id: u.id,
        content: JSON.stringify(salida),
      });
    }
    mensajes.push({ role: "user", content: resultados });
  }

  return "Me enredé con eso. ¿Me lo puedes decir de nuevo, más simple?";
}

// ── El comando "Botikin" ────────────────────────────────────
// Escribir "Botikin" a secas muestra el botiquín completo. Es una consulta
// con salida fija, así que NO pasa por el modelo: contesta al instante y no
// cuesta un peso. El agente igual tiene el inventario en su contexto, así
// que si preguntan "¿qué tengo?" en medio de una conversación, responde solo.

const SIN_TILDES = (s: string) =>
  s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();

export const esComandoBotikin = (texto: string) => SIN_TILDES(texto) === "botikin";

/** Hoy en Chile, como AAAA-MM-DD. El reloj vive en un solo lugar. */
function hoyEnChile(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santiago",
    year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date());
}

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
               "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

/** Las unidades no se pluralizan igual: "60 mL" pero "16 comprimidos".
 *  Las de medida son invariables; las contables llevan su plural. */
const PLURALES: Record<string, string> = {
  comprimido: "comprimidos", cápsula: "cápsulas", capsula: "cápsulas",
  sobre: "sobres", gota: "gotas", ampolla: "ampollas", supositorio: "supositorios",
  parche: "parches", inhalación: "inhalaciones", inhalacion: "inhalaciones",
  aplicación: "aplicaciones", aplicacion: "aplicaciones",
  // invariables: mL, mg, g, dosis, puff, spray
};

function unidad(cantidad: number, u: string): string {
  if (cantidad === 1) return u;
  return PLURALES[u.toLowerCase()] ?? u;
}

/** El semáforo del PRD 07: 30 días de aviso, no 7. */
function estado(vence: string | null, hoy: string) {
  if (!vence) return { marca: "", nota: "sin fecha de vencimiento", orden: 2 };
  const dias = Math.round((Date.parse(vence) - Date.parse(hoy)) / 864e5);
  const [a, m] = vence.split("-");
  const cuando = `${m}/${a}`;
  if (dias < 0) return { marca: "⚠️ ", nota: `venció ${cuando}`, orden: 0 };
  if (dias <= 30) return { marca: "⚠️ ", nota: `vence en ${dias} día${dias === 1 ? "" : "s"}`, orden: 1 };
  return { marca: "", nota: `vence ${cuando}`, orden: 3 };
}

export async function verBotiquin(db: SupabaseClient, hogar: string): Promise<string> {
  const { data } = await db.from("medicamentos")
    .select("cantidad, unidad, fecha_vencimiento, marca_comprada, " +
            "productos(principio_activo, concentracion, forma_farmaceutica), " +
            "integrantes(nombre)")
    .eq("hogar_id", hogar).eq("estado", "vigente");

  if (!data || data.length === 0) {
    return "No tienes nada registrado todavía.\n\n" +
           "Mándame una foto de cualquier caja que tengas a mano y la guardo — " +
           "con eso me basta para empezar.";
  }

  const hoy = hoyEnChile();

  // Agrupamos por persona: un botiquín familiar sin nombres no sirve de nada.
  const porPersona = new Map<string, string[]>();
  const filas = data.map((m) => {
    const p = m.productos as { principio_activo: string; concentracion: string; forma_farmaceutica: string } | null;
    const st = estado(m.fecha_vencimiento, hoy);
    const nombre = p
      ? `${p.principio_activo[0].toUpperCase()}${p.principio_activo.slice(1)} ${p.concentracion}`
      : (m.marca_comprada || "medicamento");
    const cantidad = Number(m.cantidad) % 1 === 0 ? Number(m.cantidad) : m.cantidad;
    return {
      quien: (m.integrantes as { nombre: string } | null)?.nombre ?? "De la casa",
      linea: `• ${st.marca}${nombre} — ${cantidad} ${unidad(Number(m.cantidad), m.unidad)} · ${st.nota}`,
      orden: st.orden,
    };
  });

  // Lo urgente arriba: primero lo vencido, después lo que vence pronto.
  filas.sort((a, b) => a.orden - b.orden);
  for (const f of filas) {
    if (!porPersona.has(f.quien)) porPersona.set(f.quien, []);
    porPersona.get(f.quien)!.push(f.linea);
  }

  const bloques = [...porPersona.entries()]
    .sort(([a], [b]) => (a === "De la casa" ? 1 : b === "De la casa" ? -1 : a.localeCompare(b)))
    .map(([quien, lineas]) => `*${quien}*\n${lineas.join("\n")}`);

  const urgentes = filas.filter((f) => f.orden <= 1).length;
  const pie = urgentes
    ? `\n\n⚠️ ${urgentes} necesita${urgentes === 1 ? "" : "n"} atención. ` +
      `Lo vencido va a punto limpio de farmacia, nunca al WC ni a la basura.`
    : "";

  const d = new Date(hoy + "T12:00:00");
  return `Tienes los siguientes medicamentos:\n\n${bloques.join("\n\n")}` + pie +
         `\n\n_Al ${d.getDate()} de ${MESES[d.getMonth()]}_`;
}
