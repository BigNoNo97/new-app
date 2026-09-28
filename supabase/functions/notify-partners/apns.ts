// Apple Push Notification service: token-based (.p8 key) authentication over HTTP/2.

export interface ApnsConfig {
  /** Contents of the .p8 key file (PKCS#8 PEM). */
  keyPem: string;
  keyId: string;
  teamId: string;
  /** The app's bundle id, sent as apns-topic. */
  topic: string;
}

export type ApnsEnvironment = "sandbox" | "production";

export type SendResult = "sent" | "invalid_token" | "failed";

function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export async function importKey(keyPem: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(keyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

// ES256 JWT for APNs. WebCrypto's ECDSA signature is already the raw r||s form JWT expects.
export async function providerToken(config: ApnsConfig, now = new Date()): Promise<string> {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: Math.floor(now.getTime() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const key = await importKey(config.keyPem);
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)),
  );
  return `${signingInput}.${base64url(signature)}`;
}

export function apnsHost(environment: ApnsEnvironment): string {
  return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

// Tokens APNs says will never work again, so they can be deleted.
export function isInvalidToken(status: number, reason: string | undefined): boolean {
  return status === 410 || (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"));
}

export async function sendPush(
  deviceToken: string,
  environment: ApnsEnvironment,
  payload: unknown,
  jwt: string,
  config: ApnsConfig,
  fetcher: typeof fetch = fetch,
): Promise<SendResult> {
  const response = await fetcher(`${apnsHost(environment)}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": config.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) {
    await response.body?.cancel();
    return "sent";
  }
  let reason: string | undefined;
  try {
    reason = (await response.json())?.reason;
  } catch {
    reason = undefined;
  }
  return isInvalidToken(response.status, reason) ? "invalid_token" : "failed";
}
