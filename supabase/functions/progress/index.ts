import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { errorJson, json, ok, supabaseFromRequest } from '../_shared.ts';

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  if (req.method !== 'GET') return errorJson('Method not allowed', 405, 'method_not_allowed');
  const url = new URL(req.url);
  const parts = url.pathname.split('/').filter(Boolean); // ..., progress, child, :id
  if (parts.length < 5 || parts[3] !== 'child') return errorJson('Not found', 404, 'not_found');
  const childId = parts[4];
  const supabase = supabaseFromRequest(req);

  // Fetch child
  const { data: child, error: cerr } = await supabase.from('children').select('id,name,current_level_id').eq('id', childId).single();
  if (cerr) return errorJson(cerr.message, 404, 'not_found');
  const { data: lvl } = await supabase.from('levels').select('code').eq('id', child.current_level_id).maybeSingle();

  // Fetch books for that level
  const { data: books } = await supabase
    .from('books')
    .select('id, category_id')
    .eq('level_id', child.current_level_id)
    .order('order_index');
  const bookIds = (books ?? []).map((b: any) => b.id);
  const { data: skills } = await supabase.from('skills').select('id,code');
  const skillCodeById: Record<number, string> = {};
  (skills ?? []).forEach((s: any) => (skillCodeById[s.id] = s.code));
  const { data: progress } = await supabase
    .from('book_progress')
    .select('book_id,status,score')
    .eq('child_id', childId)
    .in('book_id', bookIds);
  const progByBook: Record<number, any> = {};
  (progress ?? []).forEach((p: any) => (progByBook[p.book_id] = p));

  const levelBlock = {
    code: lvl?.code ?? null,
    books: (books ?? []).map((b: any) => ({
      book_id: String(b.id),
      skill_code: skillCodeById[b.category_id] ?? null,
      status: progByBook[b.id]?.status ?? 'not_started',
      score: progByBook[b.id]?.score ?? null,
    })),
  };

  return json({ child: { id: child.id, name: child.name, level_code: lvl?.code ?? null }, levels: [levelBlock] });
});

