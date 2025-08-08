import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { errorJson, json, ok, supabaseFromRequest, getChildIdHeader } from '../_shared.ts';

async function listBooks(req: Request) {
  const supabase = supabaseFromRequest(req);
  const url = new URL(req.url);
  const level = url.searchParams.get('level');
  if (!level) return errorJson('level query param required', 422, 'validation_error');
  // find level id
  const { data: lvl } = await supabase.from('levels').select('id,code').eq('code', level).maybeSingle();
  if (!lvl) return json([]);
  const { data, error } = await supabase
    .from('books')
    .select('id, level_id, category_id, title, order_index, total_units')
    .eq('level_id', lvl.id)
    .order('order_index');
  if (error) return errorJson(error.message);
  // Map skill codes
  const skillIds = Array.from(new Set((data ?? []).map((b: any) => b.category_id)));
  const { data: skills } = await supabase.from('skills').select('id,code');
  const skillCodeById: Record<number, string> = {};
  (skills ?? []).forEach((s: any) => (skillCodeById[s.id] = s.code));
  const out = (data ?? []).map((b: any) => ({
    id: String(b.id),
    level_code: lvl.code,
    skill_code: skillCodeById[b.category_id] ?? null,
    title: b.title,
    order_index: b.order_index,
    total_units: b.total_units ?? 0,
  }));
  return json(out);
}

async function getBook(req: Request, id: string) {
  const supabase = supabaseFromRequest(req);
  const childId = getChildIdHeader(req);
  const { data: book, error } = await supabase
    .from('books')
    .select('id, level_id, category_id, title, total_units')
    .eq('id', Number(id))
    .single();
  if (error) return errorJson(error.message, 404, 'not_found');
  const [{ data: level }, { data: skill }] = await Promise.all([
    supabase.from('levels').select('code').eq('id', book.level_id).single(),
    supabase.from('skills').select('code').eq('id', book.category_id).single(),
  ]);
  let progress: any = null;
  if (childId) {
    const { data: pg } = await supabase
      .from('book_progress')
      .select('status,score,started_at,completed_at')
      .eq('child_id', childId)
      .eq('book_id', book.id)
      .maybeSingle();
    if (pg) progress = pg;
  }
  return json({
    book: {
      id: String(book.id),
      level_code: level?.code ?? null,
      skill_code: skill?.code ?? null,
      title: book.title,
      total_units: book.total_units ?? 0,
    },
    progress,
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  const url = new URL(req.url);
  const parts = url.pathname.split('/').filter(Boolean);
  const maybeId = parts.length > 3 ? parts[3] : undefined; // /books/:id
  const maybeAction = parts.length > 4 ? parts[4] : undefined; // e.g., grade

  if (req.method === 'GET' && !maybeId) return listBooks(req);
  if (req.method === 'GET' && maybeId && !maybeAction) return getBook(req, maybeId);

  // POST /books/:id/grade (idempotent)
  if (req.method === 'POST' && maybeId && maybeAction === 'grade') {
    const supabase = supabaseFromRequest(req);
    const childId = getChildIdHeader(req);
    if (!childId) return errorJson('X-Child-Id header required', 422, 'validation_error');
    const bookId = Number(maybeId);
    // Compute latest attempts per unit
    const { data: units, error: uerr } = await supabase.from('units').select('id').eq('book_id', bookId);
    if (uerr) return errorJson(uerr.message);
    const unitIds = (units ?? []).map((u: any) => u.id);
    if (unitIds.length === 0) return json({ book_id: String(bookId), status: 'not_started', score: null });

    // Get latest attempt per unit for this child
    const { data: attempts } = await supabase
      .from('unit_attempts')
      .select('id,unit_id,correct_count,total_count,completed_at,started_at')
      .eq('child_id', childId)
      .in('unit_id', unitIds)
      .order('started_at', { ascending: false });

    const latestByUnit = new Map<number, any>();
    for (const a of attempts ?? []) {
      if (!latestByUnit.has(a.unit_id)) latestByUnit.set(a.unit_id, a);
    }
    const latest = Array.from(latestByUnit.values());
    let status: 'not_started' | 'in_progress' | 'redo' | 'completed' = 'not_started';
    if (latest.length > 0) status = 'in_progress';
    let allDone = true;
    let anyIncorrect = false;
    let scored = 0;
    let denom = 0;
    for (const a of latest) {
      if (!a.total_count || a.correct_count == null) { allDone = false; continue; }
      if (a.correct_count < a.total_count) anyIncorrect = true;
      scored += a.correct_count / Math.max(1, a.total_count);
      denom += 1;
    }
    if (latest.length > 0) {
      if (!anyIncorrect && latest.every((a: any) => a.total_count > 0 && a.correct_count === a.total_count)) status = 'completed';
      else if (anyIncorrect) status = 'redo';
      else status = 'in_progress';
    }
    const score = denom > 0 ? scored / denom : null;
    // Upsert book_progress
    const { error: upErr } = await supabase.from('book_progress').upsert({
      child_id: childId,
      book_id: bookId,
      status,
      score,
      started_at: latest.length ? (latest[latest.length - 1]?.started_at ?? null) : null,
      completed_at: status === 'completed' ? new Date().toISOString() : null,
    }, { onConflict: 'child_id,book_id' });
    if (upErr) return errorJson(upErr.message);
    return json({ book_id: String(bookId), status, score });
  }

  return errorJson('Not found', 404, 'not_found');
});

