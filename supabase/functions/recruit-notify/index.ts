// Edge Function recruit-notify (Supabase, Deno). Called from the app with the user's login.
//   { action: "send" }                 send up to 20 queued messages of this company
//   { action: "test", channel, to }    Admin: one test email / SMS to check the settings
// The queue, templates and permissions live in the database (claim_notifications / mark_notification).
// Provider keys are read with the service role (public.service_messaging_config) and never leave here.
// Email: Resend (https://api.resend.com/emails). SMS: a generic HTTP gateway (most Bangladeshi gateways take
// the number, the text, a key and a sender ID as GET or POST fields); it stays off until the Admin enables it.
//
// Deploy: supabase functions deploy recruit-notify   (or paste this file in Dashboard -> Edge Functions)
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

type Config = Record<string, string | boolean | null> & { api_key: string };
type Sent = { ok: boolean; ref?: string; error?: string };

async function sendEmail(cfg: Config, to: string, subject: string, text: string): Promise<Sent> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${cfg.api_key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: `${cfg.from_name} <${cfg.from_address}>`, to: [to], subject, text }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) return { ok: false, error: `Email provider ${res.status}: ${body?.message ?? body?.name ?? "error"}`.slice(0, 480) };
  return { ok: true, ref: body?.id };
}

async function sendSms(cfg: Config, to: string, text: string): Promise<Sent> {
  // Gateways expect 8801XXXXXXXXX without the plus sign.
  const fields: Record<string, string> = { [String(cfg.to_param)]: to.replace(/^\+/, ""), [String(cfg.text_param)]: text };
  if (cfg.key_param) fields[String(cfg.key_param)] = cfg.api_key;
  if (cfg.sender_param && cfg.sender_id) fields[String(cfg.sender_param)] = String(cfg.sender_id);
  const params = new URLSearchParams(fields);
  const url = String(cfg.url);
  const res = cfg.method === "GET"
    ? await fetch(`${url}${url.includes("?") ? "&" : "?"}${params}`)
    : await fetch(url, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: params });
  const text2 = await res.text().catch(() => "");
  if (!res.ok) return { ok: false, error: `SMS gateway ${res.status}: ${text2}`.slice(0, 480) };
  return { ok: true, ref: text2.slice(0, 190) };
}

async function sendQueue(user: ReturnType<typeof createClient>, admin: ReturnType<typeof createClient>) {
  const { data: claim, error } = await user.rpc("claim_notifications", { p_limit: 20 });
  if (error) throw error;
  const configs: Record<string, Config | null> = {};
  const configFor = async (channel: string) => {
    if (!(channel in configs)) {
      const { data } = await admin.rpc("service_messaging_config", { p_org_id: claim.org_id, p_channel: channel });
      configs[channel] = data ?? null;
    }
    return configs[channel];
  };
  let sent = 0;
  let failed = 0;
  for (const item of claim.items as { id: string; channel: string; to: string; subject: string | null; body: string }[]) {
    let result: Sent
    try {
      const cfg = await configFor(item.channel);
      if (!cfg || !cfg.enabled) result = { ok: false, error: `${item.channel} is not set up or switched off` };
      else if (item.channel === "email") result = await sendEmail(cfg, item.to, item.subject ?? "", item.body);
      else result = await sendSms(cfg, item.to, item.body);
    } catch (e) {
      result = { ok: false, error: (e as Error).message.slice(0, 480) };
    }
    await user.rpc("mark_notification", { p_id: item.id, p_ok: result.ok, p_provider_ref: result.ref ?? null, p_error: result.error ?? null });
    if (result.ok) sent += 1;
    else failed += 1;
  }
  return { sent, failed };
}

async function sendTest(user: ReturnType<typeof createClient>, admin: ReturnType<typeof createClient>, body: Record<string, unknown>) {
  const channel = body.channel === "sms" ? "sms" : "email";
  const { data: ctx, error } = await user.rpc("messaging_test_context", { p_channel: channel });
  if (error) throw error;
  const { data: cfg } = await admin.rpc("service_messaging_config", { p_org_id: ctx.org_id, p_channel: channel });
  if (!cfg) return { ok: false, message: "Save the settings first" };
  const to = String(body.to ?? "").trim();
  const result = channel === "email"
    ? await sendEmail(cfg, to, `Test email from ${ctx.company}`, `This is a test from Olympus HRIS. Email sending works for ${ctx.company}.`)
    : await sendSms(cfg, to, `Test SMS from ${ctx.company} (Olympus HRIS).`);
  const message = result.ok ? `Sent to ${to}` : result.error ?? "Not sent";
  await user.rpc("record_messaging_test", { p_channel: channel, p_ok: result.ok, p_message: message });
  return { ok: result.ok, message };
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
    if (body.action === "send") return json(await sendQueue(user, admin));
    if (body.action === "test") return json(await sendTest(user, admin, body));
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: (e as { message?: string }).message ?? "Something went wrong" }, 400);
  }
});
