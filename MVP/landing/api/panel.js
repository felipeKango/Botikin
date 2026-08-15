// Panel de orquestación — el backend.
//
// La clave secreta de Supabase vive acá, en el servidor, y nunca viaja al
// navegador. El panel solo recibe números ya agregados.
//
// Acceso: cabecera `x-panel-clave` contra la variable PANEL_CLAVE.

const SB   = process.env.SUPABASE_URL;
const KEY  = process.env.SUPABASE_SERVICE_KEY;
const CLAVE = process.env.PANEL_CLAVE;

const cabeceras = { apikey: KEY, Authorization: `Bearer ${KEY}` };

async function sb(ruta, extra = {}) {
  const r = await fetch(`${SB}/rest/v1/${ruta}`, {
    headers: { ...cabeceras, ...extra },
  });
  if (!r.ok) throw new Error(`${ruta} → ${r.status} ${await r.text()}`);
  return r;
}

/** Cuenta filas sin traérselas: Postgrest devuelve el total en Content-Range. */
async function contar(tabla, filtro = "") {
  const r = await sb(`${tabla}?select=id${filtro ? "&" + filtro : ""}&limit=1`, {
    Prefer: "count=exact",
  });
  return Number(r.headers.get("content-range")?.split("/")[1] ?? 0);
}

const filas = async (ruta) => (await sb(ruta)).json();

/** ¿Está vivo el número de WhatsApp, y sigue apuntando a nosotros el webhook? */
async function saludKapso() {
  const k = process.env.KAPSO_API_KEY;
  if (!k) return { ok: false, detalle: "sin KAPSO_API_KEY" };
  try {
    const r = await fetch("https://api.kapso.ai/platform/v1/whatsapp/phone_numbers", {
      headers: { "X-API-Key": k },
    });
    if (!r.ok) return { ok: false, detalle: `HTTP ${r.status}` };
    const d = await r.json();
    const n = (d.data ?? d)[0];
    const w = await fetch("https://api.kapso.ai/platform/v1/whatsapp/webhooks", {
      headers: { "X-API-Key": k },
    }).then((x) => x.json()).catch(() => ({}));
    const activos = (w.data ?? []).filter((x) => x.active);
    const nuestro = activos.find((x) => (x.url ?? "").includes("supabase.co"));
    return {
      ok: n?.status === "CONNECTED" && Boolean(nuestro),
      numero: n?.display_phone_number,
      nombre: n?.display_name,
      estado: n?.status,
      webhooks_activos: activos.length,
      apunta_a_nosotros: Boolean(nuestro),
    };
  } catch (e) {
    return { ok: false, detalle: String(e) };
  }
}

export default async function handler(req, res) {
  if (!CLAVE) return res.status(500).json({ error: "PANEL_CLAVE no configurada" });
  if (req.headers["x-panel-clave"] !== CLAVE) {
    return res.status(401).json({ error: "clave incorrecta" });
  }

  try {
    const hoy = new Date().toISOString().slice(0, 10);

    const [
      pagos, codigos, hogares, mensajesHoy, medicamentos, integrantes,
      tratamientos, recetas, ultimosPagos, pendientes, casas, kapso,
      vencidosArrastrados,
    ] = await Promise.all([
      filas("pagos?select=monto,estado,pagado_el"),
      filas("access_codes?select=status,issued_at,expires_at,email,code,sent_at"),
      contar("hogares"),
      contar("mensajes", `created_at=gte.${hoy}`),
      contar("medicamentos", "estado=eq.vigente"),
      contar("integrantes", "activo=eq.true"),
      contar("tratamientos", "estado=eq.activo"),
      contar("recetas"),
      filas("pagos?select=orden_flow,monto,estado,email,medio_pago,pagado_el,hogar_id,access_codes(code,status)&order=pagado_el.desc&limit=8"),
      filas("access_codes?select=code,email,issued_at,expires_at,status,sent_at&status=in.(issued,sent)&order=issued_at.desc&limit=10"),
      filas("hogares?select=id,telefono,onboarding,created_at,integrantes(id),medicamentos(id),conversaciones(ultimo_mensaje_usuario)&order=created_at.desc&limit=10"),
      saludKapso(),
      // Un tratamiento con fecha pasada que sigue "activo" es un aviso de
      // toma que puede salir por un tratamiento que ya terminó.
      contar("tratamientos", `estado=eq.activo&duracion=eq.dias&fecha_termino=lt.${hoy}`),
    ]);

    const exitosos = pagos.filter((p) => p.estado === "exitoso");
    const cuenta = (s) => codigos.filter((c) => c.status === s).length;
    const ahora = Date.now();

    // El fallo más caro del producto: pagó y nunca entró. Silencioso,
    // porque nadie reclama de inmediato — simplemente no vuelve.
    const pagadosSinCanjear = pendientes.filter(
      (c) => (ahora - Date.parse(c.issued_at)) / 864e5 >= 1);

    const casasVivas   = casas.filter((c) => (c.medicamentos ?? []).length > 0).length;
    const casasConGente = casas.filter((c) => (c.integrantes ?? []).length > 0).length;

    res.setHeader("cache-control", "no-store");
    res.status(200).json({
      generado: new Date().toISOString(),

      // El embudo: solo pasos por los que pasa la MISMA persona, en orden.
      // El envío del correo no va acá — no es una etapa donde la gente se
      // caiga, es una entrega. Mezclarlos producía un "se pierden 1" falso.
      circuito: [
        { paso: "Pagó",               valor: exitosos.length,     unidad: "cobros" },
        { paso: "Recibió su código",  valor: codigos.length,      unidad: "códigos" },
        { paso: "Activó por WhatsApp", valor: cuenta("redeemed"), unidad: "canjes" },
        { paso: "Contó su casa",      valor: casasConGente,       unidad: "casas" },
        { paso: "Cargó un remedio",   valor: casasVivas,          unidad: "casas" },
      ],

      // La entrega del correo se mide aparte de la conversión.
      entrega: {
        despachados: cuenta("sent"),
        pendientes: codigos.filter((c) => c.status === "issued").length,
      },

      dinero: {
        recaudado: exitosos.reduce((s, p) => s + p.monto, 0),
        cobros: exitosos.length,
        fallidos: pagos.length - exitosos.length,
      },

      codigos: {
        emitidos: codigos.length,
        enviados: cuenta("sent"),
        canjeados: cuenta("redeemed"),
        revocados: cuenta("revoked"),
        vencidos: codigos.filter(
          (c) => c.status !== "redeemed" && Date.parse(c.expires_at) < ahora).length,
      },

      uso: { hogares, integrantes, medicamentos, tratamientos, recetas, mensajesHoy },

      servicios: {
        supabase: { ok: true, detalle: "consultado en esta llamada" },
        kapso,
        // Configurado ≠ funcionando. El panel distingue las dos cosas:
        // puede estar bien configurado y todavía no haber mandado nada.
        correo: (() => {
          const via = process.env.RESEND_API_KEY ? "Resend"
                    : process.env.SMTP_PASSWORD  ? `SMTP · ${process.env.SMTP_HOST ?? "?"}`
                    : null;
          if (!via) return { ok: false, detalle: "sin configurar: los códigos se entregan a mano" };
          return {
            ok: true,
            detalle: cuenta("sent")
              ? `${via} · ${cuenta("sent")} código${cuenta("sent") === 1 ? "" : "s"} despachado${cuenta("sent") === 1 ? "" : "s"}`
              : `${via} · configurado, sin códigos enviados todavía`,
          };
        })(),
      },

      alertas: [
        ...(pagadosSinCanjear.length
          ? [{
              nivel: "alto",
              texto: `${pagadosSinCanjear.length} pagó y no ha activado hace más de un día`,
              detalle: pagadosSinCanjear.map((c) => `${c.email} · ${c.code}`).join(" · "),
            }]
          : []),
        ...(kapso.apunta_a_nosotros === false
          ? [{ nivel: "alto", texto: "el webhook de Kapso no apunta a Botikin",
               detalle: "los mensajes entrantes se están perdiendo" }]
          : []),
        ...(kapso.nombre && kapso.nombre !== "Botikin"
          ? [{ nivel: "medio", texto: `el número se muestra como "${kapso.nombre}"`,
               detalle: "quien reciba el mensaje no va a reconocer la marca" }]
          : []),
        ...(!process.env.RESEND_API_KEY && !process.env.SMTP_PASSWORD && codigos.length
          ? [{ nivel: "medio", texto: "el envío de correos no está conectado",
               detalle: "cada código hay que entregarlo a mano" }]
          : []),
        ...(vencidosArrastrados
          ? [{ nivel: "alto",
               texto: `${vencidosArrastrados} tratamiento${vencidosArrastrados === 1 ? "" : "s"} terminado${vencidosArrastrados === 1 ? "" : "s"} sigue${vencidosArrastrados === 1 ? "" : "n"} marcado${vencidosArrastrados === 1 ? "" : "s"} como activo${vencidosArrastrados === 1 ? "" : "s"}`,
               detalle: "podría recordarse una toma de algo que ya se terminó · " +
                        "correr cerrar_tratamientos_vencidos()" }]
          : []),
        // SMTP por buzón propio: sirve hoy, pero tiene techo y no avisa rebotes.
        ...(!process.env.RESEND_API_KEY && process.env.SMTP_PASSWORD
          ? [{ nivel: "bajo",
               texto: "el correo sale por SMTP del buzón, no por un proveedor",
               detalle: "límite de unos cientos al día y sin registro de rebotes: " +
                        "si uno no llega, no nos enteramos" }]
          : []),
      ],

      ultimosPagos,
      pendientes,
      vencidosArrastrados,
      casas: casas.map((c) => ({
        telefono: c.telefono,
        onboarding: c.onboarding,
        creado: c.created_at,
        personas: (c.integrantes ?? []).length,
        medicamentos: (c.medicamentos ?? []).length,
        ultimoMensaje: c.conversaciones?.ultimo_mensaje_usuario ?? null,
      })),
    });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
}
