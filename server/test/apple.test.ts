import { afterEach, describe, expect, it, vi } from "vitest";
import { resetAppleKeysForTest, verifyAppleIdToken } from "../src/apple";
import { base64url } from "../src/auth";

const audience = "com.example.zerozerotodo";
const nonce = "n".repeat(64);

async function signedToken(kid: string) {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  ) as CryptoKeyPair;
  const now = Math.floor(Date.now() / 1000);
  const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const input = `${encode({ alg: "RS256", kid })}.${encode({
    iss: "https://appleid.apple.com", aud: audience, sub: "apple-subject", iat: now, exp: now + 600, nonce,
  })}`;
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, new TextEncoder().encode(input)));
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey) as JsonWebKey;
  return { token: `${input}.${base64url(signature)}`, key: { kty: "RSA", kid, n: jwk.n!, e: jwk.e! } };
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
  resetAppleKeysForTest();
});

describe("Apple signing keys", () => {
  it("refetches once when Apple rotates to a key the cache has not seen", async () => {
    const old = await signedToken("old");
    const rotated = await signedToken("new");
    let published = [old.key];
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async () => Response.json({ keys: published }));
    vi.useFakeTimers({ toFake: ["Date"] });

    await verifyAppleIdToken(old.token, audience, nonce);
    published = [old.key, rotated.key];

    // Inside the refetch interval, an unknown key id does not cost a fetch.
    await expect(verifyAppleIdToken(rotated.token, audience, nonce)).rejects.toThrow("Unknown Apple signing key");
    expect(fetchMock).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(61_000);
    const claims = await verifyAppleIdToken(rotated.token, audience, nonce);
    expect(claims.sub).toBe("apple-subject");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
