import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { errorJson, json, ok, supabaseFromRequest } from '../_shared.ts';

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  if (req.method !== 'GET') return errorJson('Method not allowed', 405, 'method_not_allowed');
  const url = new URL(req.url);
  const bookId = url.searchParams.get('book_id');
  if (!bookId) return errorJson('book_id required', 422, 'validation_error');
  const supabase = supabaseFromRequest(req);
  const { data, error } = await supabase
    .from('units')
    .select('id, unit_index')
    .eq('book_id', Number(bookId))
    .order('unit_index');
  if (error) return errorJson(error.message);
  return json((data ?? []).map((u: any) => ({ id: String(u.id), unit_index: u.unit_index })));
});

