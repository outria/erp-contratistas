// Version del despliegue: la usa components/actualizador.js para aplicar las actualizaciones solas
// Si cambia, cada pantalla abierta se recarga sola cuando no hay un registro abierto (v1.42).
export const dynamic = 'force-dynamic';

export function GET() {
  const v = process.env.VERCEL_DEPLOYMENT_ID || process.env.VERCEL_GIT_COMMIT_SHA || '';
  return Response.json({ v }, { headers: { 'Cache-Control': 'no-store, max-age=0' } });
}
