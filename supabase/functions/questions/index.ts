import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { errorJson, json, ok, supabaseFromRequest } from '../_shared.ts';

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  if (req.method !== 'GET') return errorJson('Method not allowed', 405, 'method_not_allowed');
  const url = new URL(req.url);
  const unitId = url.searchParams.get('unit_id');
  if (!unitId) return errorJson('unit_id required', 422, 'validation_error');
  const supabase = supabaseFromRequest(req);
  const { data: unit, error: uerr } = await supabase.from('units').select('id, unit_index').eq('id', Number(unitId)).single();
  if (uerr) return errorJson(uerr.message, 404, 'not_found');
  const { data, error } = await supabase
    .from('questions')
    .select('id, question_index, question_number, type, prompt, options')
    .eq('unit_id', Number(unitId))
    .order('question_index', { ascending: true })
    .order('question_number', { ascending: true });
  if (error) return errorJson(error.message);
  const questions = (data ?? []).map((q: any) => ({
    id: String(q.id),
    question_index: q.question_index ?? q.question_number ?? null,
    type: q.type ?? 'short_answer',
    prompt: q.prompt ?? {},
    options: q.options ?? null,
  }));
  return json({ unit: { id: String(unit.id), unit_index: unit.unit_index }, questions });
});

