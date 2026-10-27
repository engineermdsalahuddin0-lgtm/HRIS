// Edge Function assistant (Supabase, Deno). Called from the app with the user's login.
//   { action: "test_key", slot: "chat" | "embed" }   Admin / HR with assistant.manage: one tiny call per key
// (AI4 adds "ingest" and "index_guide", AI5 adds "ask"; design: docs/Part04Architecture.md sections 8, 12.)
// Rules live in the database. The company's keys are read with the service role (public.service_assistant_keys)
// and never leave this function. Every data read for answers goes through RPCs called AS THE USER.
// No LangChain: chunking, embeddings and the LLM call are small and done here with the providers' HTTP APIs.
//
// Deploy: supabase functions deploy assistant   (or paste this file in Dashboard -> Edge Functions -> New)
import { createClient } from "npm:@supabase/supabase-js@2";

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
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: (e as { message?: string }).message ?? "Something went wrong" }, 400);
  }
});
