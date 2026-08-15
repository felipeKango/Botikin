# Botikin

**El botiquín de tu casa es una bodega sin inventario.**

Botikin es un agente de WhatsApp —**Doctor Botikin**— que administra el
botiquín de una casa chilena: registra los remedios con una foto, avisa 30
días antes de que venzan, lee las recetas del médico y recuerda cada toma.

Sin app que descargar. Producto de [Kango](https://getkango.com), Santiago de
Chile.

```
Usuario ──WhatsApp──► Kapso ──► Workflow + Agent
                                   │
                                   ├──► Claude (visión: cajas y recetas)
                                   ├──► Supabase (hogar, inventario, tratamientos)
                                   └──► Flow.cl (suscripción mensual)
```

## Cómo leer este repositorio

Empieza por acá, en este orden:

| archivo | qué es |
|---|---|
| [`MVP/prd/00-botikin.md`](MVP/prd/00-botikin.md) | el PRD padre: la historia, los objetivos y el índice |
| [`MVP/soul.md`](MVP/soul.md) | el alma del agente: qué sabe, qué nunca hace, cómo habla |
| [`MVP/prd/01-el-canal.md`](MVP/prd/01-el-canal.md) | la regla dura: la ventana de 24 h de WhatsApp |

Los PRD siguen el método de `MVP/how-i-spec.pdf`: historia, objetivos,
flujo hoy→mañana, datos y pseudo-código. **Nunca código final.**

## Estructura

```
MVP/
├── soul.md              el carácter y los límites del agente
├── prd/                 8 documentos: el padre y sus 7 hijos
├── landing/             la web de botikin.app
├── supabase/            schema y funciones (en migración al modelo nuevo)
└── _legacy/             la app iOS anterior, archivada — ver su README
```

## Estado

En especificación. El producto anterior era una app iOS nativa; el pivote a
agente de WhatsApp es del **15-08-2026**. La app está archivada, no borrada,
en `MVP/_legacy/`.

## Aviso

Botikin **no da asesoría médica**. No indica ni ajusta dosis, no recomienda
medicamentos y no reemplaza al médico ni al químico farmacéutico. Los
recordatorios siguen la pauta prescrita y los vencimientos usan la fecha
impresa en el envase.

## Datos personales

Este repositorio **no debe contener recetas médicas reales, fotos de cajas con
datos de pacientes, ni exportes de la base de datos**. La receta de ejemplo
usada durante el diseño está excluida en `.gitignore` a propósito. Si
necesitas una receta de referencia, anonimízala primero.

---

Hecho con ❤️ en Chile
