// Stands between Report a Bug and Discord, so the webhook's address never
// ships in the app. The app posts its report here exactly as it would to
// Discord (multipart: payload_json + files[n]); this checks it over, slows
// down anyone sending too many, and passes a cleaned-up copy on to the
// webhook, which only this Worker knows (the DISCORD_WEBHOOK secret).

const MOST_FILES = 10;
const MOST_BYTES = 10_000_000; // Discord's limit on a server that isn't boosted.

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return reply(405, "Reports are POSTed.");

    // One sender can't flood it, and nor can everyone at once (Discord
    // itself allows a webhook about 30 messages a minute).
    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    if (!(await env.PER_SENDER.limit({ key: ip })).success ||
        !(await env.OVERALL.limit({ key: "all" })).success) {
      return reply(429, "Too many reports just now.");
    }

    const length = Number(request.headers.get("Content-Length") ?? 0);
    if (length > MOST_BYTES + 200_000) return reply(413, "Too big.");
    if (!(request.headers.get("Content-Type") ?? "").startsWith("multipart/form-data")) {
      return reply(400, "Not a report.");
    }

    let form, payload;
    try {
      form = await request.formData();
      payload = JSON.parse(form.get("payload_json"));
    } catch {
      return reply(400, "Not a report.");
    }

    // Only what the app sends, rebuilt: its embed (or a follow-up's line of
    // text), under the app's name, never pinging anyone.
    const clean = {
      username: "Spider Buddy",
      allowed_mentions: { parse: [] },
    };
    if (Array.isArray(payload.embeds)) clean.embeds = payload.embeds.slice(0, 1);
    // (A follow-up's line is always this one, from BugReport.swift.)
    const more = /^More attachments for the report above \(\d+ of \d+\)\.$/;
    if (typeof payload.content === "string" && more.test(payload.content)) clean.content = payload.content;
    if (!clean.embeds && !clean.content) return reply(400, "Not a report.");

    const out = new FormData();
    out.append("payload_json", JSON.stringify(clean));
    let files = 0, bytes = 0;
    for (const [key, value] of form) {
      if (!/^files\[\d+\]$/.test(key) || typeof value === "string") continue;
      const type = value.type ?? "";
      if (!type.startsWith("image/") && !type.startsWith("video/")) continue;
      files += 1;
      bytes += value.size;
      if (files > MOST_FILES || bytes > MOST_BYTES) return reply(413, "Too big.");
      out.append(`files[${files - 1}]`, value, value.name);
    }

    const discord = await fetch(`${env.DISCORD_WEBHOOK}?wait=true`, { method: "POST", body: out });
    if (discord.ok) return reply(200, "Sent.");
    // Discord's own say, minus anything that might give the webhook away.
    const status = discord.status === 429 || discord.status === 413 ? discord.status : 502;
    return reply(status, "Discord didn't take it.");
  },
};

function reply(status, message) {
  return Response.json({ message }, { status });
}
