# Supply ERP · contratistas de alimentacion del Estado

Plataforma de cadena de suministro para empresas, uniones temporales y consorcios que ejecutan contratos estatales de alimentacion (PAE, USPEC/PPL, ICBF, fuerzas, bomberos, adulto mayor). Columna vertebral: la operacion. Momento de verdad: la racion entregada al beneficiario con la calidad y las evidencias que exige la entidad.

Nombre provisional ("Supply ERP"), paleta azul oscuro + ambar. El nombre definitivo, logo y colores se cambian en un solo sitio (`app/globals.css`, `app/layout.js`, `public/manifest.webmanifest`).

## Stack (el mismo de A2 PAN ERP)

- Next.js 15 (App Router, paginas de cliente) en Vercel, PWA instalable.
- Supabase (Postgres con RLS por empresa, Auth por correo, Storage privado para adjuntos). Toda la logica de permisos vive en la base.
- Migraciones en `supabase/migrations`, datos iniciales en `supabase/seed`.

## Puesta en marcha (F0)

1. Crear el proyecto en Supabase y correr, en orden, en el editor SQL:
   `20261101…nucleo_multiempresa`, `20261102…roles_matriz_alta_empresa`, `20261103…adjuntos_importaciones`, `20261104…contratos_nucleo`, y luego `seed/seed_001_empresas_iniciales.sql`.
2. Authentication > URL Configuration: Site URL = URL de Vercel; agregar `<url>/login` en Redirect URLs.
3. Authentication > Users > Invite user: `outria@gmail.com` (queda como superadministrador por el trigger de la migracion 001). Los demas usuarios se invitan igual y luego se les asigna empresa y rol en Usuarios y roles.
4. Vercel > Environment Variables: `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY` (nunca la `service_role`). Redeploy.

## Modulos

| Codigo | Modulo | Fase |
|---|---|---|
| M0 | Seguridad, empresas, usuarios, roles, adjuntos | F0 (listo) |
| M1 | Contratos y anexos: cabezote, adiciones (tope 50 % en SMLMV), sedes, agotamiento | F0/F1 (cabezote listo) |
| M2 | Planeacion: minuta ciclica, calendario, cupos, dietas, explosion de materiales | F1 |
| M3 / M4 | Compras, master de precios, OC, seguimiento en vivo / portal de proveedores | F2 |
| M5 / M6 | Inventario con lotes y PEPS / traslados y entregas a sedes | F3 |
| M7 / M8 | Operacion en sede y cuadro de raciones / calidad e interventoria | F4 |
| M9 / M10 | Facturacion a la entidad / facturas de proveedores, cotejo, causacion, pagos | F5 |
| M11 / M12 / M15 | Talento humano / IA del buzon y automatizaciones / tableros | F6 |
| M13 / M14 | Maestros (productos, terceros, fichas) / vehiculos | transversal |

Reglas de negocio y decisiones: ver `docs/` y `CONTROL_DE_CAMBIOS_ERP_CONTRATISTAS.md`. El plan maestro vive en el documento del proyecto en Claude.

## Desarrollo local

```
cp .env.example .env.local   # y llenar las dos variables
npm install
npm run dev
```
