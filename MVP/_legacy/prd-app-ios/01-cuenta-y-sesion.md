# PRD — Cuenta y sesión

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** registro, ingreso, sesión persistente y perfil — NO toca login
social, NO toca recuperación de contraseña (MVP)

---

## 1 · RESUMEN

**Hoy:** no hay cuenta; no hay dónde guardar el botiquín.

**Después:** el usuario se registra con correo y clave, y entra a una app
que ya tiene saldo para probar la IA sin pagar nada.

---

## 2 · LA HISTORIA

**ANTES**
Carmen baja la app, la abre, y lo primero que ve es un formulario que le
pide una tarjeta. La cierra. **Nunca supo qué hacía la app.**

**DESPUÉS**
Carmen pone su correo y una clave. Entra directo a un botiquín vacío que la
invita a agregar su primer remedio, y arriba a la derecha ve un rayo con
**500**. No sabe todavía qué son, pero sabe que le alcanzan. Escanea su
primera receta esa misma tarde, gratis. **Cuando se le acaban, ya entendió
para qué sirve pagar.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — del primer toque al botiquín en menos de 30 segundos
- **O2** — todo usuario nuevo nace con plan gratis y 500 tokens, sin pedir
  tarjeta
- **O3** — la sesión sobrevive al cierre de la app; nadie vuelve a escribir
  la clave
- **O4** — el token de sesión nunca se guarda en texto plano

- **NO1** — no pedimos RUT, dirección ni datos de salud al registrarse
- **NO2** — no hay verificación de correo en el MVP
- **NO3** — el teléfono NO se pide al registrarse (se pide después, solo si
  quiere WhatsApp — ver [06](06-whatsapp.md))

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                    DESPUÉS

(no existe)            registro ─► se crea el usuario
                                    └─ se le crea la suscripción gratis
                                         └─ 500 tokens, renovación en 1 mes
                                              └─ entra al botiquín

                       ingreso   ─► credenciales ─► sesión
                                    └─ se guarda en el llavero del teléfono
                                         └─ al reabrir, entra solo
                                              └─ si expiró, se renueva sola
```

---

## 5 · LOS DATOS

**usuario**
| campo | qué es |
|---|---|
| correo | único, es la identidad |
| nombre | opcional, para saludarlo |
| teléfono | **vacío al nacer** — solo para WhatsApp |

**suscripción** (una por usuario, creada en el mismo acto que el usuario)
| campo | valor al nacer |
|---|---|
| plan | `gratis` |
| saldo total | 500 |
| saldo usado | 0 |
| renovación | hoy + 1 mes |

**El disparador:** crear un usuario crea su suscripción. No hay usuario sin
suscripción — nunca, ni por un instante.

**El candado:** cada usuario solo ve sus propias filas. Regla sin excepción,
en todas las tablas del producto.

**Dónde vive la sesión:** en el llavero del sistema, no en preferencias.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO alguien se registra

  ¿el correo ya existe?     → si sí, le decimos que inicie sesión
  ¿la clave es suficiente?  → si no, se lo decimos antes de enviar

  ENTONCES creamos el usuario Y su suscripción gratis en el mismo acto,
           y lo dejamos adentro sin pedirle nada más.


CUANDO la app arranca

  ¿hay sesión en el llavero?  → si no, pantalla de ingreso
  ¿sigue vigente?             → si no, la renovamos en silencio
                                 └─ si tampoco se puede, pantalla de ingreso

  ENTONCES lo llevamos directo a su botiquín.
```

**Promesas:**
- nunca pedimos tarjeta para entrar
- nunca mostramos la pantalla de ingreso a alguien que ya entró
- el saldo inicial es un regalo, no una prueba con cuenta regresiva
