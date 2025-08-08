import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-child-id',
};

export function json(body: unknown, init?: ResponseInit) {
  return new Response(JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
    ...init,
  });
}

export function errorJson(message: string, status = 400, code = 'bad_request') {
  return json({ error: { code, message } }, { status });
}

export function supabaseFromRequest(req: Request) {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } },
  );
  return supabase;
}

export async function requireAuthUserId(supabase: ReturnType<typeof createClient>) {
  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user?.id) throw new Error('unauthorized');
  return data.user.id;
}

export function getChildIdHeader(req: Request) {
  const id = req.headers.get('X-Child-Id') || req.headers.get('x-child-id');
  return id ?? undefined;
}

export function ok() {
  return new Response('ok', { headers: corsHeaders });
}

