import { corsHeaders } from './config.js';
import { _runLlama } from './ai_suggest.js';

async function handleAutoFix(request, env) {
  try {
    const { code = '', errors = '' } = await request.json();
    const prompt =
      'Fix this Dart/Flutter code using the error list. Return only the fixed source code.\n\n' +
      `Errors:\n${errors}\n\nCode:\n${code}`;
    const suggestion = await _runLlama(prompt, env) ?? '';
    return new Response(JSON.stringify({ fixedCode: suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ fixedCode: '', error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

async function handleAutoFixFull(request, env) {
  try {
    const { files = [], errors = '' } = await request.json();
    const combined = Array.isArray(files)
      ? files.map((f) => `=== ${f?.path || 'file'} ===\n${f?.content || ''}`).join('\n\n')
      : '';
    const prompt =
      'Fix the provided project files based on the errors. Return only a JSON array of objects with path and content.\n\n' +
      `Errors:\n${errors}\n\nFiles:\n${combined}`;
    const raw = await _runLlama(prompt, env) ?? '[]';
    let fixedFiles = [];
    try {
      fixedFiles = JSON.parse(raw);
      if (!Array.isArray(fixedFiles)) fixedFiles = [];
    } catch (_) {
      fixedFiles = [];
    }
    return new Response(JSON.stringify({ fixedFiles }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ fixedFiles: [], error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Fan‑out notifications ============

export { handleAutoFix, handleAutoFixFull };
