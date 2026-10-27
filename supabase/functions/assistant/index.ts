// Edge Function assistant (Supabase, Deno). Called from the app with the user's login.
//   { action: "test_key", slot: "chat" | "embed" }   assistant.manage: one tiny call per key
//   { action: "ingest", resource_id }                 assistant.manage: index one batch of a resource; { more } says if
//                                                     the browser should call again (resume point in the database)
//   { action: "index_guide" }                         assistant.manage: (re)index the app guide with the company's key
// (AI5 adds "ask"; design: docs/Part04Architecture.md sections 8, 12.)
// Rules live in the database. The company's keys are read with the service role (public.service_assistant_keys)
// and never leave this function. Every data read for answers goes through RPCs called AS THE USER.
// No LangChain: chunking, embeddings and the LLM call are small and done here with the providers' HTTP APIs.
//
// Deploy: supabase functions deploy assistant   (or paste this file in Dashboard -> Edge Functions -> New)
import { createClient } from "npm:@supabase/supabase-js@2";
import { extractText, getDocumentProxy } from "npm:unpdf";
import mammoth from "npm:mammoth";
import { Buffer } from "node:buffer";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Every vector in the store has this many dimensions; each provider is asked for exactly this. */
export const DIMENSIONS = 1024;

type Key = { provider: string; model: string; api_key: string };
type Client = ReturnType<typeof createClient>;

async function readError(res: Response, label: string): Promise<string> {
  const body = await res.json().catch(() => null) as { error?: { message?: string } | string; message?: string } | null;
  const detail = typeof body?.error === "string" ? body.error : body?.error?.message ?? body?.message ?? res.statusText;
  return `${label} ${res.status}: ${detail}`.slice(0, 280);
}

// ----------------------------------------------------------------------------- embeddings
/** Embeds texts with the company's embedding key. kind: document (indexing) or query (a question). */
export async function embed(key: Key, texts: string[], kind: "document" | "query"): Promise<number[][]> {
  if (key.provider === "openai") {
    const res = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: { Authorization: `Bearer ${key.api_key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: key.model, input: texts, dimensions: DIMENSIONS }),
    });
    if (!res.ok) throw new Error(await readError(res, "OpenAI"));
    const body = await res.json();
    return (body.data as { index: number; embedding: number[] }[]).sort((a, b) => a.index - b.index).map((d) => d.embedding);
  }
  if (key.provider === "voyage") {
    const res = await fetch("https://api.voyageai.com/v1/embeddings", {
      method: "POST",
      headers: { Authorization: `Bearer ${key.api_key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: key.model, input: texts, input_type: kind, output_dimension: DIMENSIONS }),
    });
    if (!res.ok) throw new Error(await readError(res, "Voyage"));
    const body = await res.json();
    return (body.data as { index: number; embedding: number[] }[]).sort((a, b) => a.index - b.index).map((d) => d.embedding);
  }
  if (key.provider === "google") {
    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${key.model}:batchEmbedContents`, {
      method: "POST",
      headers: { "x-goog-api-key": key.api_key, "Content-Type": "application/json" },
      body: JSON.stringify({
        requests: texts.map((text) => ({
          model: `models/${key.model}`,
          content: { parts: [{ text }] },
          taskType: kind === "query" ? "RETRIEVAL_QUERY" : "RETRIEVAL_DOCUMENT",
          outputDimensionality: DIMENSIONS,
        })),
      }),
    });
    if (!res.ok) throw new Error(await readError(res, "Gemini"));
    const body = await res.json();
    return (body.embeddings as { values: number[] }[]).map((e) => e.values);
  }
  throw new Error(`Unknown embedding provider ${key.provider}`);
}

// ----------------------------------------------------------------------------- chat (non-streaming)
export interface ChatInput { system: string; messages: { role: "user" | "assistant"; content: string }[]; temperature: number; maxTokens: number }
export interface ChatOutput { text: string; tokensIn: number; tokensOut: number }

export async function chat(key: Key, input: ChatInput): Promise<ChatOutput> {
  if (key.provider === "anthropic") {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key.api_key, "anthropic-version": "2023-06-01", "Content-Type": "application/json" },
      body: JSON.stringify({ model: key.model, system: input.system, messages: input.messages, temperature: input.temperature, max_tokens: input.maxTokens }),
    });
    if (!res.ok) throw new Error(await readError(res, "Anthropic"));
    const body = await res.json();
    const text = (body.content as { type: string; text?: string }[]).filter((c) => c.type === "text").map((c) => c.text).join("");
    return { text, tokensIn: body.usage?.input_tokens ?? 0, tokensOut: body.usage?.output_tokens ?? 0 };
  }
  if (key.provider === "openai") {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${key.api_key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: key.model, temperature: input.temperature, max_completion_tokens: input.maxTokens,
        messages: [{ role: "system", content: input.system }, ...input.messages],
      }),
    });
    if (!res.ok) throw new Error(await readError(res, "OpenAI"));
    const body = await res.json();
    return { text: body.choices?.[0]?.message?.content ?? "", tokensIn: body.usage?.prompt_tokens ?? 0, tokensOut: body.usage?.completion_tokens ?? 0 };
  }
  if (key.provider === "google") {
    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${key.model}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": key.api_key, "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: input.system }] },
        contents: input.messages.map((m) => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.content }] })),
        generationConfig: { temperature: input.temperature, maxOutputTokens: input.maxTokens },
      }),
    });
    if (!res.ok) throw new Error(await readError(res, "Gemini"));
    const body = await res.json();
    const text = (body.candidates?.[0]?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("");
    return { text, tokensIn: body.usageMetadata?.promptTokenCount ?? 0, tokensOut: body.usageMetadata?.candidatesTokenCount ?? 0 };
  }
  throw new Error(`Unknown chat provider ${key.provider}`);
}

// ----------------------------------------------------------------------------- context
async function myOrg(user: Client): Promise<{ orgId: string; permissions: string[] }> {
  const { data, error } = await user.rpc("get_my_context");
  if (error) throw error;
  if (!data?.organization?.id) throw new Error("Sign in to a company first");
  return { orgId: data.organization.id, permissions: data.permissions ?? [] };
}

async function companyKeys(admin: Client, orgId: string): Promise<{ chat: Key | null; embed: Key | null }> {
  const { data, error } = await admin.rpc("service_assistant_keys", { p_org_id: orgId });
  if (error) throw error;
  return { chat: data?.chat ?? null, embed: data?.embed ?? null };
}

// ----------------------------------------------------------------------------- files -> passages -> chunks
interface Passage { location: string; section: string; text: string }
interface Chunk { chunk_index: number; location: string; section: string; passage: string; token_count: number }

/** About 4 characters per token: enough for sizing chunks. */
const tokensOf = (text: string) => Math.max(1, Math.ceil(text.length / 4));

function htmlToSections(html: string): Passage[] {
  // Headings start sections; paragraphs, list items and table rows become lines.
  const text = html
    .replace(/<h[1-6][^>]*>(.*?)<\/h[1-6]>/gis, (_m, t) => `\n@@SECTION@@${t.replace(/<[^>]+>/g, "")}\n`)
    .replace(/<li[^>]*>(.*?)<\/li>/gis, "\n- $1")
    .replace(/<\/(p|tr)>/gi, "\n").replace(/<\/(td|th)>/gi, " | ").replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  const out: Passage[] = [];
  let section = "";
  let lines: string[] = [];
  let tokens = 0;
  const flush = () => {
    const body = lines.join("\n").trim();
    // DOCX has no fixed pages: about 450 tokens per page (decision D4).
    if (body) out.push({ location: `about p.${Math.max(1, Math.ceil(tokens / 450))}`, section, text: body });
    lines = [];
  };
  for (const line of text.split("\n")) {
    if (line.startsWith("@@SECTION@@")) { flush(); section = line.slice(11).trim(); continue; }
    if (line.trim()) { lines.push(line.trim()); tokens += tokensOf(line); }
  }
  flush();
  return out;
}

function flattenJson(value: unknown, path = ""): string[] {
  if (value === null || ["string", "number", "boolean"].includes(typeof value)) return [`${path || "value"}: ${String(value)}`];
  if (Array.isArray(value)) {
    if (value.every((v) => v === null || typeof v !== "object")) return [`${path || "value"}: ${value.join(", ")}`];
    return value.flatMap((v, i) => flattenJson(v, `${path}[${i}]`));
  }
  return Object.entries(value as Record<string, unknown>).flatMap(([k, v]) => flattenJson(v, path ? `${path}.${k}` : k));
}

async function toPassages(bytes: Uint8Array, kind: string): Promise<{ passages: Passage[]; units: number }> {
  if (kind === "pdf") {
    const pdf = await getDocumentProxy(new Uint8Array(bytes));
    const { text } = await extractText(pdf, { mergePages: false });
    const pages = (Array.isArray(text) ? text : [text]).map((p) => p.replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim());
    const passages = pages.map((t, i) => ({ location: String(i + 1), section: "", text: t })).filter((p) => p.text.length > 20);
    if (passages.length === 0) throw new Error("This PDF has no text layer (a scanned copy). Upload a text PDF or the DOCX.");
    return { passages, units: pages.length };
  }
  if (kind === "docx") {
    const { value } = await mammoth.convertToHtml({ buffer: Buffer.from(bytes) });
    const passages = htmlToSections(value);
    if (passages.length === 0) throw new Error("The document is empty.");
    return { passages, units: passages.length };
  }
  const data = JSON.parse(new TextDecoder().decode(bytes));
  const records: [string, unknown][] = Array.isArray(data) ? data.map((v, i) => [`$[${i}]`, v])
    : data && typeof data === "object" ? Object.entries(data).map(([k, v]) => [`$.${k}`, v]) : [["$", data]];
  const passages = records.map(([path, v]) => {
    const title = v && typeof v === "object" && !Array.isArray(v)
      ? ["title", "name", "heading", "subject"].map((k) => (v as Record<string, unknown>)[k]).find((x) => typeof x === "string") as string | undefined
      : undefined;
    return { location: path, section: title ?? path, text: flattenJson(v).join("\n") };
  }).filter((p) => p.text.trim());
  if (passages.length === 0) throw new Error("The JSON file has no records.");
  return { passages, units: passages.length };
}

/**
 * Splits each passage into chunks of about chunkSize tokens with overlapPercent repeated, cutting at
 * paragraph, then line, then sentence ends so a rule (or a table row) is not cut in half.
 */
export function chunkPassages(passages: Passage[], chunkSize: number, overlapPercent: number): Chunk[] {
  const max = chunkSize * 4;
  const overlap = Math.round(max * overlapPercent / 100);
  const out: Chunk[] = [];
  for (const p of passages) {
    const pieces = p.text.split(/\n{2,}/).flatMap((para) => para.length <= max ? [para] : para.split(/\n/))
      .flatMap((line) => line.length <= max ? [line] : line.split(/(?<=[.।!?])\s+/));
    let current = "";
    const push = () => {
      const passage = current.trim();
      if (passage) out.push({ chunk_index: out.length, location: p.location, section: p.section, passage, token_count: tokensOf(passage) });
    };
    for (const piece of pieces) {
      if (current && current.length + piece.length + 1 > max) {
        push();
        current = overlap > 0 ? current.slice(-overlap) : "";
      }
      current = current ? `${current}\n${piece}` : piece;
    }
    push();
  }
  return out;
}

const BATCH = 48;

async function ingest(user: Client, admin: Client, body: Record<string, unknown>) {
  const ctx = await myOrg(user);
  if (!ctx.permissions.includes("assistant.manage")) throw new Error("You do not have permission for this action (assistant.manage)");
  const id = String(body.resource_id ?? "");
  const { data: r, error } = await admin.rpc("service_assistant_resource", { p_id: id, p_org_id: ctx.orgId });
  if (error) throw error;
  if (!r) throw new Error("Resource not found");
  if (r.status !== "processing") return { status: r.status, more: false };
  const fail = async (message: string) => {
    await admin.rpc("service_fail_assistant_resource", { p_id: id, p_org_id: ctx.orgId, p_error: message });
    return { status: "failed", more: false, error: message };
  };
  try {
    const keys = await companyKeys(admin, ctx.orgId);
    if (!keys.embed) return await fail("No embedding key: add it on the API keys tab");
    const { data: file, error: dl } = await admin.storage.from("assistant-resources").download(r.path);
    if (dl || !file) return await fail("The file is missing in storage; upload it again");
    const { passages, units } = await toPassages(new Uint8Array(await file.arrayBuffer()), r.kind);
    const chunks = chunkPassages(passages, r.hyper.chunk_size, r.hyper.chunk_overlap);
    const from = r.processed_through ?? 0;
    const slice = chunks.slice(from, from + BATCH);
    const vectors = slice.length
      ? await embed(keys.embed, slice.map((c) => `${r.name} · ${c.location}${c.section ? ` · ${c.section}` : ""}\n${c.passage}`), "document")
      : [];
    const done = from + slice.length >= chunks.length;
    const { error: saveError } = await admin.rpc("service_save_assistant_chunks", {
      p_id: id, p_org_id: ctx.orgId, p_from: from,
      p_chunks: slice.map((c, i) => ({ ...c, embedding: vectors[i] })),
      p_done: done, p_units: units, p_total: chunks.length, p_model: keys.embed.model,
    });
    if (saveError) throw saveError;
    return { status: done ? "ready" : "processing", more: !done, processed: from + slice.length, total: chunks.length };
  } catch (e) {
    return await fail((e as Error).message);
  }
}

async function indexGuide(user: Client, admin: Client) {
  const ctx = await myOrg(user);
  if (!ctx.permissions.includes("assistant.manage")) throw new Error("You do not have permission for this action (assistant.manage)");
  const keys = await companyKeys(admin, ctx.orgId);
  if (!keys.embed) throw new Error("Add and test the embedding key first");
  const { data: articles, error } = await admin.rpc("service_guide_articles");
  if (error) throw error;
  const items = (articles as { key: string; route: string; title: string; body: string; keywords: string[] }[]).flatMap((a) =>
    chunkPassages([{ location: a.route, section: a.title, text: a.body }], 400, 10)
      .map((c) => ({ ...c, guide_key: a.key, keywords: a.keywords })));
  const chunks: Record<string, unknown>[] = [];
  for (let i = 0; i < items.length; i += BATCH) {
    const part = items.slice(i, i + BATCH);
    const vectors = await embed(keys.embed, part.map((c) => `Olympus HRIS app guide · ${c.section} (${c.location})\n${c.passage}\nKeywords: ${c.keywords.join(", ")}`), "document");
    part.forEach((c, j) => chunks.push({ guide_key: c.guide_key, chunk_index: c.chunk_index, location: c.location, section: c.section,
                                         passage: c.passage, token_count: c.token_count, embedding: vectors[j] }));
  }
  const { data: saved, error: saveError } = await admin.rpc("service_save_guide_chunks", { p_org_id: ctx.orgId, p_chunks: chunks, p_model: keys.embed.model });
  if (saveError) throw saveError;
  return { indexed: saved, articles: (articles as unknown[]).length };
}

// ----------------------------------------------------------------------------- actions
async function testKey(user: Client, admin: Client, body: Record<string, unknown>) {
  const slot = body.slot === "embed" ? "embed" : "chat";
  const ctx = await myOrg(user);
  if (!ctx.permissions.includes("assistant.manage")) throw new Error("You do not have permission for this action (assistant.manage)");
  const keys = await companyKeys(admin, ctx.orgId);
  let ok = false;
  let message: string;
  try {
    if (slot === "chat") {
      if (!keys.chat) throw new Error("Save the chat key first");
      await chat(keys.chat, { system: "Reply with OK.", messages: [{ role: "user", content: "ping" }], temperature: 0, maxTokens: 5 });
      message = `Connected to ${keys.chat.provider} (${keys.chat.model})`;
    } else {
      if (!keys.embed) throw new Error("Save an embedding key first");
      const [vector] = await embed(keys.embed, ["Olympus test"], "query");
      if (vector?.length !== DIMENSIONS) throw new Error(`The model returned ${vector?.length ?? 0} dimensions; ${DIMENSIONS} are needed`);
      message = `Embeddings work (${keys.embed.provider} ${keys.embed.model}, ${DIMENSIONS} dimensions)`;
    }
    ok = true;
  } catch (e) {
    message = (e as Error).message;
  }
  // The embedding slot may be the chat key (OpenAI / Gemini); record the test on the row that holds it.
  const recordSlot = slot === "embed" && keys.embed && keys.chat && keys.embed.api_key === keys.chat.api_key ? "chat" : slot;
  await user.rpc("record_assistant_key_test", { p_slot: recordSlot, p_ok: ok, p_message: message });
  return { ok, message };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Sign in first" }, 401);
  const user = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } });
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  try {
    const body = await req.json();
    if (body.action === "test_key") return json(await testKey(user, admin, body));
    if (body.action === "ingest") return json(await ingest(user, admin, body));
    if (body.action === "index_guide") return json(await indexGuide(user, admin));
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: (e as { message?: string }).message ?? "Something went wrong" }, 400);
  }
});
