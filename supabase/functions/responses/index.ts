import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { errorJson, json, ok, supabaseFromRequest, getChildIdHeader } from '../_shared.ts';

type IncomingAnswer = { question_id: string | number; answer: unknown };

function normalize(val: any) {
  if (typeof val === 'string') return val.trim().toLowerCase();
  return val;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  if (req.method !== 'POST') return errorJson('Method not allowed', 405, 'method_not_allowed');
  const supabase = supabaseFromRequest(req);
  const childId = getChildIdHeader(req);
  if (!childId) return errorJson('X-Child-Id header required', 422, 'validation_error');
  const body = await req.json().catch(() => ({}));
  const unit_id: number | undefined = body?.unit_id ? Number(body.unit_id) : undefined;
  const answers: IncomingAnswer[] = Array.isArray(body?.answers) ? body.answers : [];
  if (!unit_id || answers.length === 0) return errorJson('unit_id and answers required', 422, 'validation_error');

  // Create attempt
  const { data: attempt, error: aerr } = await supabase
    .from('unit_attempts')
    .insert({ child_id: childId, unit_id, started_at: new Date().toISOString() })
    .select('id')
    .single();
  if (aerr) return errorJson(aerr.message);

  // Fetch questions and keys
  const { data: qs, error: qerr } = await supabase
    .from('questions')
    .select('id, type, answer_key, correct_answer')
    .eq('unit_id', unit_id);
  if (qerr) return errorJson(qerr.message);
  const keyById = new Map<number, any>();
  const typeById = new Map<number, string>();
  for (const q of qs ?? []) {
    keyById.set(q.id, q.answer_key ?? q.correct_answer);
    typeById.set(q.id, q.type ?? 'short_answer');
  }

  const results: { question_id: string; correct: boolean }[] = [];
  let correct = 0;
  for (const a of answers) {
    const qid = Number(a.question_id);
    const expected = keyById.get(qid);
    // Basic grading: normalize strings, allow boolean direct compare
    let isCorrect = false;
    if (expected === undefined || expected === null) {
      isCorrect = false; // no key, mark false
    } else {
      if (typeof expected === 'boolean') isCorrect = Boolean(a.answer) === expected;
      else if (typeof expected === 'string') isCorrect = normalize(a.answer) === normalize(expected);
      else isCorrect = JSON.stringify(a.answer) === JSON.stringify(expected);
    }
    if (isCorrect) correct += 1;
    results.push({ question_id: String(qid), correct: isCorrect });
    await supabase.from('responses').upsert({
      attempt_id: attempt.id,
      question_id: qid,
      answer: a.answer,
      correct: isCorrect,
    });
  }

  const total = answers.length;
  const score = total ? correct / total : 0;
  await supabase
    .from('unit_attempts')
    .update({ correct_count: correct, total_count: total, completed_at: new Date().toISOString() })
    .eq('id', attempt.id);

  // Build redo set
  const redo = results.filter((r) => !r.correct).map((r) => ({ question_id: r.question_id }));

  // Find book and update progress via books/grade
  const { data: unit } = await supabase.from('units').select('book_id').eq('id', unit_id).single();
  let book_status: any = null;
  if (unit?.book_id) {
    // Re-grade this book aggregating attempts
    // We can call the grading logic by reusing DB here; simplest is to emulate the logic inline
    const { data: units } = await supabase.from('units').select('id').eq('book_id', unit.book_id);
    const unitIds = (units ?? []).map((u: any) => u.id);
    const { data: attempts } = await supabase
      .from('unit_attempts')
      .select('unit_id,correct_count,total_count,started_at')
      .eq('child_id', childId)
      .in('unit_id', unitIds)
      .order('started_at', { ascending: false });
    const latestByUnit = new Map<number, any>();
    for (const a of attempts ?? []) if (!latestByUnit.has(a.unit_id)) latestByUnit.set(a.unit_id, a);
    const latest = Array.from(latestByUnit.values());
    let status: 'not_started' | 'in_progress' | 'redo' | 'completed' = 'not_started';
    if (latest.length > 0) status = 'in_progress';
    let anyIncorrect = false;
    let denom = 0; let sum = 0;
    for (const a of latest) {
      if (a.total_count > 0) {
        denom += 1;
        sum += a.correct_count / a.total_count;
        if (a.correct_count < a.total_count) anyIncorrect = true;
      } else {
        anyIncorrect = true;
      }
    }
    if (latest.length > 0 && latest.every((a: any) => a.total_count > 0 && a.correct_count === a.total_count)) status = 'completed';
    else if (anyIncorrect && latest.length > 0) status = 'redo';
    const aggScore = denom > 0 ? sum / denom : null;
    await supabase.from('book_progress').upsert({ child_id: childId, book_id: unit.book_id, status, score: aggScore }, { onConflict: 'child_id,book_id' });
    book_status = { book_id: String(unit.book_id), status, score: aggScore };
  }

  return json({
    attempt_id: attempt.id,
    summary: { correct, total, score },
    results,
    redo,
    book_status,
  });
});

