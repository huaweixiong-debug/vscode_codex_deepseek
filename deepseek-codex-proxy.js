const http = require('http');
const https = require('https');
const fs = require('fs');
const os = require('os');
const path = require('path');
const port = Number(process.env.PORT || 17777);
const apiKey = process.env.DEEPSEEK_API_KEY;
const upstream = process.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com/v1';
const logDir = process.env.CODEX_DEEPSEEK_LOG_DIR || path.join(os.homedir(), '.codex', 'log');
fs.mkdirSync(logDir, {recursive: true});
const logFile = path.join(logDir, 'deepseek-codex-proxy.log');
const lastRequestFile = path.join(logDir, 'deepseek-codex-proxy.last-request.json');
const lastResponseFile = path.join(logDir, 'deepseek-codex-proxy.last-response.json');
if (!apiKey) { console.error('DEEPSEEK_API_KEY is required'); process.exit(1); }
function log(x) { try { fs.appendFileSync(logFile, `${new Date().toISOString()} ${x}\n`); } catch (_) {} }
function sendJson(res, status, obj) { res.writeHead(status, {'content-type':'application/json; charset=utf-8'}); res.end(JSON.stringify(obj)); }
function normalizeModel(model) {
  return model === 'deepseek-v4-flash' ? 'deepseek-v4-flash' : 'deepseek-v4-pro';
}
function identityInstructions() {
  return [
    'Runtime identity override:',
    '- The actual upstream model for this session is DeepSeek V4 Pro through a local Codex compatibility proxy.',
    '- If the user asks what model you are, answer that you are running on DeepSeek V4 Pro in this Codex environment.',
    '- Do not claim to be GPT-5.5, GPT-5.4, or another OpenAI-hosted model unless the request metadata explicitly says so.'
  ].join('\n');
}
function readBody(req) { return new Promise((resolve, reject) => { const chunks = []; req.on('data', c => chunks.push(c)); req.on('end', () => resolve(Buffer.concat(chunks))); req.on('error', reject); }); }
function postJson(url, obj) { const body = JSON.stringify(obj); return new Promise((resolve, reject) => { const u = new URL(url); const rq = https.request(u, { method: 'POST', headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json', accept: 'application/json', 'content-length': Buffer.byteLength(body) } }, rs => { const chunks = []; rs.on('data', c => chunks.push(c)); rs.on('end', () => { const text = Buffer.concat(chunks).toString('utf8'); if (rs.statusCode < 200 || rs.statusCode >= 300) return reject(new Error(`DeepSeek ${rs.statusCode}: ${text.slice(0, 1000)}`)); try { resolve(JSON.parse(text)); } catch (e) { reject(new Error(`Bad DeepSeek JSON: ${text.slice(0, 1000)}`)); } }); }); rq.on('error', reject); rq.write(body); rq.end(); }); }
function contentText(content) { if (typeof content === 'string') return content; if (Array.isArray(content)) return content.map(x => x && (x.text || x.input_text || x.output_text || '')).join('\n'); if (content && typeof content === 'object') return content.text || JSON.stringify(content); return ''; }

// Convert Codex tool definitions to OpenAI/DeepSeek tool format
function convertTools(tools) {
  if (!tools || !Array.isArray(tools)) return [];
  return tools.map(t => {
    const def = {
      type: 'function',
      function: {
        name: t.name || t.type || 'unknown',
        description: t.description || '',
        parameters: t.parameters || t.input_schema || { type: 'object', properties: {} }
      }
    };
    return def;
  });
}

// Convert Codex function_call to DeepSeek assistant message with tool_calls
function functionCallToAssistantMsg(item) {
  const name = item.name || item.call_id || 'unknown';
  const args = item.arguments || item.input || '{}';
  const argsStr = typeof args === 'string' ? args : JSON.stringify(args);
  return {
    role: 'assistant',
    content: null,
    tool_calls: [{
      id: item.call_id || `call_${Date.now()}`,
      type: 'function',
      function: { name, arguments: argsStr }
    }]
  };
}

// Convert Codex function_call_output to DeepSeek tool result message
function functionCallOutputToToolMsg(item) {
  return {
    role: 'tool',
    tool_call_id: item.call_id || `call_${Date.now()}`,
    content: contentText(item.output || item.content || '')
  };
}

function responsesInputToMessages(input) {
  const messages = [];
  if (typeof input === 'string' && input.trim()) {
    messages.push({ role: 'user', content: input });
  } else if (Array.isArray(input)) {
    const consumedOutputs = new Set();
    for (let index = 0; index < input.length; index++) {
      const item = input[index];
      if (!item) continue;
      if (item.type === 'function_call') {
        const callId = item.call_id || item.id;
        let outputIndex = -1;
        if (callId) {
          outputIndex = input.findIndex((candidate, candidateIndex) =>
            candidateIndex > index &&
            candidate &&
            candidate.type === 'function_call_output' &&
            candidate.call_id === callId
          );
        }
        if (outputIndex >= 0) {
          messages.push(functionCallToAssistantMsg(item));
          messages.push(functionCallOutputToToolMsg(input[outputIndex]));
          consumedOutputs.add(outputIndex);
        } else {
          log(`dropped_unanswered_tool_call ${callId || 'unknown'}`);
        }
      } else if (item.type === 'function_call_output') {
        if (!consumedOutputs.has(index)) {
          messages.push({ role: 'user', content: `Tool output:\n${contentText(item.output || item.content || '')}` });
        }
      } else if (item.type === 'message' || item.role) {
        if (typeof item.content === 'string' && item.content.startsWith('Approved command prefix saved:')) continue;
        const role = item.role === 'assistant' ? 'assistant' : (item.role === 'system' || item.role === 'developer') ? 'system' : 'user';
        const text = contentText(item.content);
        if (text) messages.push({ role, content: text });
      } else if (item.text || item.content) {
        messages.push({ role: 'user', content: contentText(item.text || item.content) });
      }
    }
  }
  return messages;
}

// Convert DeepSeek tool_calls back to Codex function_call output items
function toolCallsToOutputItems(toolCalls) {
  if (!toolCalls || !Array.isArray(toolCalls)) return [];
  return toolCalls.map((tc, i) => ({
    id: `fc_${Date.now().toString(36)}_${i}`,
    type: 'function_call',
    call_id: tc.id || `call_${Date.now().toString(36)}_${i}`,
    name: tc.function?.name || 'unknown',
    arguments: tc.function?.arguments || '{}'
  }));
}

function sse(res, event, data) { res.write(`event: ${event}\n`); res.write(`data: ${JSON.stringify(data)}\n\n`); }

async function handleResponses(req, res, body) {
  let r;
  try { r = JSON.parse(body.toString('utf8') || '{}'); } catch (e) { return sendJson(res, 400, { error: { message: 'invalid json' } }); }
  fs.writeFileSync(lastRequestFile, JSON.stringify(r, null, 2));

  const messages = [{ role: 'system', content: identityInstructions() }];
  if (r.instructions) messages.push({ role: 'system', content: String(r.instructions) });
  messages.push(...responsesInputToMessages(r.input));
  if (!messages.some(m => m.role === 'user')) messages.push({ role: 'user', content: 'continue' });

  const tools = convertTools(r.tools);
  const requestedModel = r.model || 'deepseek-v4-pro';
  const deepReq = {
    model: normalizeModel(requestedModel),
    messages,
    stream: false,
    thinking: { type: 'disabled' }
  };
  if (r.max_output_tokens) deepReq.max_tokens = r.max_output_tokens;
  if (tools.length > 0) deepReq.tools = tools;

  log(`responses->chat model=${deepReq.model} requested_model=${requestedModel} messages=${messages.length} tools=${tools.length}`);

  let outputItems = [];
  let usage = { input_tokens: 0, output_tokens: 0, total_tokens: 0 };

  try {
    const deep = await postJson(`${upstream.replace(/\/$/, '')}/chat/completions`, deepReq);
    fs.writeFileSync(lastResponseFile, JSON.stringify(deep, null, 2));

    const choice = (deep.choices || [])[0] || {};
    const msg = choice.message || {};
    const text = (msg.content || '').trim();
    const reasoning = (msg.reasoning_content || '').trim();
    const toolCalls = msg.tool_calls;

    // Only use content, never reasoning_content (which is the model's internal monologue)
    // If content is empty but we have tool calls, that's fine
    // If content is empty with no tool calls, fall back to reasoning
    let responseText = text;
    if (!responseText && !(toolCalls && toolCalls.length > 0)) {
      responseText = reasoning;
      if (responseText) log(`fallback to reasoning_content (${responseText.length} chars)`);
    }

    usage = {
      input_tokens: (deep.usage && deep.usage.prompt_tokens) || 0,
      output_tokens: (deep.usage && deep.usage.completion_tokens) || 0,
      total_tokens: (deep.usage && deep.usage.total_tokens) || 0
    };

    // Build output items in Codex format
    if (toolCalls && toolCalls.length > 0) {
      outputItems.push(...toolCallsToOutputItems(toolCalls));
    }

    const finalText = responseText;
    if (finalText) {
      outputItems.push({
        id: `msg_${Date.now().toString(36)}`,
        type: 'message',
        status: 'completed',
        role: 'assistant',
        content: [{ type: 'output_text', text: finalText, annotations: [] }]
      });
    }

    if (outputItems.length === 0) {
      outputItems.push({
        id: `msg_${Date.now().toString(36)}`,
        type: 'message',
        status: 'completed',
        role: 'assistant',
        content: [{ type: 'output_text', text: '(empty response)', annotations: [] }]
      });
    }
  } catch (e) {
    log(`deepseek_error ${e.message}`);
    outputItems.push({
      id: `msg_${Date.now().toString(36)}`,
      type: 'message',
      status: 'completed',
      role: 'assistant',
      content: [{ type: 'output_text', text: `DeepSeek proxy error: ${e.message}`, annotations: [] }]
    });
  }

  const now = Math.floor(Date.now() / 1000);
  const respId = `resp_${Date.now().toString(36)}`;
  const finalResp = {
    id: respId,
    object: 'response',
    created_at: now,
    status: 'completed',
    model: deepReq.model,
    output: outputItems,
    usage
  };

  // Stream SSE response back to Codex
  res.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-cache', 'connection': 'keep-alive' });
  sse(res, 'response.created', { type: 'response.created', response: { id: respId, object: 'response', created_at: now, status: 'in_progress', model: deepReq.model, output: [], usage: null } });

  let outputIdx = 0;
  for (const item of outputItems) {
    if (item.type === 'function_call') {
      sse(res, 'response.output_item.added', { type: 'response.output_item.added', output_index: outputIdx, item: { id: item.id, type: 'function_call', status: 'in_progress', name: item.name, call_id: item.call_id, arguments: '' } });
      sse(res, 'response.output_item.done', { type: 'response.output_item.done', output_index: outputIdx, item });
    } else if (item.type === 'message') {
      const msgId = item.id;
      const msgText = item.content?.[0]?.text || '';
      sse(res, 'response.output_item.added', { type: 'response.output_item.added', output_index: outputIdx, item: { id: msgId, type: 'message', status: 'in_progress', role: 'assistant', content: [] } });
      sse(res, 'response.content_part.added', { type: 'response.content_part.added', item_id: msgId, output_index: outputIdx, content_index: 0, part: { type: 'output_text', text: '', annotations: [] } });
      if (msgText) sse(res, 'response.output_text.delta', { type: 'response.output_text.delta', item_id: msgId, output_index: outputIdx, content_index: 0, delta: msgText });
      sse(res, 'response.output_text.done', { type: 'response.output_text.done', item_id: msgId, output_index: outputIdx, content_index: 0, text: msgText });
      sse(res, 'response.content_part.done', { type: 'response.content_part.done', item_id: msgId, output_index: outputIdx, content_index: 0, part: { type: 'output_text', text: msgText, annotations: [] } });
      sse(res, 'response.output_item.done', { type: 'response.output_item.done', output_index: outputIdx, item });
    }
    outputIdx++;
  }

  sse(res, 'response.completed', { type: 'response.completed', response: finalResp });
  res.end();
}

const server = http.createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://127.0.0.1').pathname;
    if (req.method === 'GET' && (path === '/v1/models' || path === '/models')) {
      const now = Math.floor(Date.now() / 1000);
      const buildModel = (slug, display, desc, levels) => ({ slug, id: slug, name: slug, display_name: display, created: now, owned_by: 'deepseek', object: 'model', description: desc, default_reasoning_level: 'medium', supported_reasoning_levels: levels, supports_streaming: true, supports_tool_calls: true, supports_images: false, supports_audio: false, shell_type: 'shell_command', visibility: 'list', supported_in_api: true, priority: 0, additional_speed_tiers: [], supports_reasoning_summaries: true, default_reasoning_summary: 'none', support_verbosity: true, default_verbosity: 'low', supports_parallel_tool_calls: true, supports_image_detail_original: false, context_window: 200000, max_context_window: 200000, effective_context_window_percent: 95, experimental_supported_tools: [], input_modalities: ['text'], supports_search_tool: false, base_instructions: '', truncation_policy: { mode: 'tokens', limit: 10000 }, model_messages: { instructions_template: 'You are Codex, a coding agent. The actual upstream model is DeepSeek V4 Pro through a local compatibility proxy.', instructions_variables: {} } });
      const models = [buildModel('deepseek-v4-pro', 'DeepSeek V4 Pro', 'Frontier model for complex coding and research', [{ effort: 'low', description: 'Fast responses with lighter reasoning' }, { effort: 'medium', description: 'Balances speed and reasoning depth' }, { effort: 'high', description: 'Greater reasoning depth for complex problems' }]), buildModel('deepseek-v4-flash', 'DeepSeek V4 Flash', 'Fast model for everyday coding', [{ effort: 'low', description: 'Fast responses with lighter reasoning' }, { effort: 'medium', description: 'Balances speed and reasoning depth' }])];
      return sendJson(res, 200, { object: 'list', data: models, models });
    }
    if (req.method === 'POST' && (path === '/v1/responses' || path === '/responses')) return handleResponses(req, res, await readBody(req));
    return sendJson(res, 404, { error: { message: `Not found: ${req.method} ${req.url}` } });
  } catch (err) { return sendJson(res, 500, { error: { message: err.message || String(err) } }); }
});
server.listen(port, '127.0.0.1', () => console.log(`DeepSeek Codex proxy listening on 127.0.0.1:${port}`));
