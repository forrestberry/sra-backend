import { serve } from 'https://deno.land/std@0.223.0/http/server.ts';
import { corsHeaders, errorJson, json, ok, requireAuthUserId, supabaseFromRequest } from '../_shared.ts';

serve(async (req) => {
  if (req.method === 'OPTIONS') return ok();
  const supabase = supabaseFromRequest(req);

  try {
    const url = new URL(req.url);
    const parts = url.pathname.split('/').filter(Boolean); // [..., 'functions','v1','children', '<id>?']
    const maybeId = parts.length > 3 ? parts[3] : undefined;

    if (req.method === 'GET' && !maybeId) {
      // List children for authenticated parent
      await requireAuthUserId(supabase);
      const { data, error } = await supabase.from('children').select('id,name,current_level_id,created_at');
      if (error) throw error;
      // Map level_code via levels table
      let levelCodes: Record<number, string> = {};
      if (data && data.length > 0) {
        const levelIds = Array.from(new Set(data.map((c: any) => c.current_level_id).filter(Boolean)));
        if (levelIds.length) {
          const { data: levels } = await supabase.from('levels').select('id,code').in('id', levelIds as number[]);
          (levels ?? []).forEach((l: any) => (levelCodes[l.id] = l.code));
        }
      }
      const out = (data ?? []).map((c: any) => ({
        id: c.id,
        name: c.name,
        level_code: levelCodes[c.current_level_id!] ?? null,
        created_at: c.created_at,
      }));
      return json(out);
    }

    if (req.method === 'POST' && !maybeId) {
      // Create child { name, level_code }
      const userId = await requireAuthUserId(supabase);
      const body = await req.json().catch(() => ({}));
      const name: string | undefined = body?.name;
      const level_code: string | undefined = body?.level_code;
      if (!name || !level_code) return errorJson('name and level_code required', 422, 'validation_error');
      const { data: level } = await supabase.from('levels').select('id,code').eq('code', level_code).maybeSingle();
      if (!level) return errorJson('invalid level_code', 422, 'validation_error');
      const { data, error } = await supabase
        .from('children')
        .insert([{ name, parent_id: userId, current_level_id: level.id }])
        .select('id,name,current_level_id,created_at')
        .single();
      if (error) throw error;
      return json({ id: data.id, name: data.name, level_code: level.code, created_at: data.created_at }, { status: 201 });
    }

    if (req.method === 'PATCH' && maybeId) {
      // Update child name and/or level
      await requireAuthUserId(supabase);
      const body = await req.json().catch(() => ({}));
      const patch: any = {};
      if (typeof body?.name === 'string') patch.name = body.name;
      if (typeof body?.level_code === 'string') {
        const { data: level } = await supabase.from('levels').select('id').eq('code', body.level_code).maybeSingle();
        if (!level) return errorJson('invalid level_code', 422, 'validation_error');
        patch.current_level_id = level.id;
      }
      if (Object.keys(patch).length === 0) return errorJson('No valid fields to update', 422, 'validation_error');
      const { data, error } = await supabase
        .from('children')
        .update(patch)
        .eq('id', maybeId)
        .select('id,name,current_level_id')
        .single();
      if (error) throw error;
      let level_code: string | null = null;
      if (data.current_level_id) {
        const { data: level } = await supabase.from('levels').select('code').eq('id', data.current_level_id).single();
        level_code = level?.code ?? null;
      }
      return json({ id: data.id, name: data.name, level_code });
    }

    return errorJson('Not found', 404, 'not_found');
  } catch (e: any) {
    if (e?.message === 'unauthorized') return errorJson('Unauthorized', 401, 'unauthorized');
    return errorJson(e?.message ?? 'Unexpected error');
  }
});

