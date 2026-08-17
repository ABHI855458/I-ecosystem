// FCM HTTP v1 sender — used for both iOS and Android device tokens (Firebase
// can deliver to APNs under the hood for iOS, so this is the one push path
// for both platforms; see supabase/functions/README.md for the Firebase
// project setup this depends on).
//
// Needs three Edge Function secrets (`supabase secrets set ...`), not
// checked into this repo:
//   FCM_PROJECT_ID    — Firebase project id
//   FCM_CLIENT_EMAIL  — service account client_email
//   FCM_PRIVATE_KEY   — service account private_key (PEM, literal \n's ok)
//
// Get all three from Firebase Console → Project Settings → Service
// accounts → Generate new private key.

interface AccessToken {
  token: string;
  expiresAt: number; // epoch ms
}

let cachedToken: AccessToken | null = null;

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (const b of arr) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(clean);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

async function getAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) {
    return cachedToken.token;
  }

  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKeyPem = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  if (!projectId || !clientEmail || !privateKeyPem) {
    throw new Error("FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY not configured");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const signingInput =
    `${base64url(encoder.encode(JSON.stringify(header)))}.` +
    `${base64url(encoder.encode(JSON.stringify(claims)))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput),
  );
  const jwt = `${signingInput}.${base64url(signature)}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    throw new Error(`FCM token exchange failed: ${resp.status} ${await resp.text()}`);
  }
  const json = await resp.json();
  cachedToken = { token: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cachedToken.token;
}

export interface PushPayload {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

/** Sends one push. Returns false (never throws) on a stale/invalid token so
 * callers can fan out over many tokens without one bad token failing the
 * batch — see notify.ts sendToUser. */
export async function sendPush(payload: PushPayload): Promise<boolean> {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const accessToken = await getAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: payload.token,
          notification: { title: payload.title, body: payload.body },
          data: payload.data,
          apns: { payload: { aps: { sound: "default" } } },
          android: { priority: "high" },
        },
      }),
    },
  );

  if (!resp.ok) {
    const errText = await resp.text();
    console.error(`FCM send failed for token ${payload.token.slice(0, 12)}…: ${resp.status} ${errText}`);
    return false;
  }
  return true;
}
