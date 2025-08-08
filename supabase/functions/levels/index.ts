import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { corsHeaders, errorJson, json, ok, supabaseFromRequest } from '../_shared.ts';

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  if (req.method !== 'GET') return errorJson('Method not allowed', 405, 'method_not_allowed');
  const supabase = supabaseFromRequest(req);
  const { data, error } = await supabase.from('levels').select('code,ordinal,label').order('ordinal');
  if (error) return errorJson(error.message);
  return json(data ?? []);
});

