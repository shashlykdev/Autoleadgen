import type { VercelRequest, VercelResponse } from '@vercel/node';
import { kv } from '@vercel/kv';

// Simple encryption using XOR with a secret (for basic obfuscation)
// In production, use proper encryption like AES
function encrypt(text: string, secret: string): string {
  let result = '';
  for (let i = 0; i < text.length; i++) {
    result += String.fromCharCode(text.charCodeAt(i) ^ secret.charCodeAt(i % secret.length));
  }
  return Buffer.from(result).toString('base64');
}

function decrypt(encoded: string, secret: string): string {
  const text = Buffer.from(encoded, 'base64').toString();
  let result = '';
  for (let i = 0; i < text.length; i++) {
    result += String.fromCharCode(text.charCodeAt(i) ^ secret.charCodeAt(i % secret.length));
  }
  return result;
}

interface ApiKeys {
  openai?: string;
  anthropic?: string;
  xai?: string;
  updatedAt: string;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Device-ID');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Verify API secret from environment
  const apiSecret = process.env.API_SECRET;
  if (!apiSecret) {
    return res.status(500).json({ error: 'Server configuration error' });
  }

  // Verify authorization header
  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${apiSecret}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Get device ID from header
  const deviceId = req.headers['x-device-id'] as string;
  if (!deviceId) {
    return res.status(400).json({ error: 'Device ID required' });
  }

  const kvKey = `apikeys:${deviceId}`;
  const encryptionKey = process.env.ENCRYPTION_KEY || apiSecret;

  try {
    switch (req.method) {
      case 'GET': {
        // Retrieve API keys
        const stored = await kv.get<ApiKeys>(kvKey);
        if (!stored) {
          return res.status(200).json({ keys: {} });
        }

        // Decrypt keys before sending
        const decrypted: Partial<ApiKeys> = {
          updatedAt: stored.updatedAt
        };

        if (stored.openai) {
          decrypted.openai = decrypt(stored.openai, encryptionKey);
        }
        if (stored.anthropic) {
          decrypted.anthropic = decrypt(stored.anthropic, encryptionKey);
        }
        if (stored.xai) {
          decrypted.xai = decrypt(stored.xai, encryptionKey);
        }

        return res.status(200).json({ keys: decrypted });
      }

      case 'POST': {
        // Store API keys
        const { openai, anthropic, xai } = req.body as Partial<ApiKeys>;

        const toStore: ApiKeys = {
          updatedAt: new Date().toISOString()
        };

        // Encrypt keys before storing
        if (openai) {
          toStore.openai = encrypt(openai, encryptionKey);
        }
        if (anthropic) {
          toStore.anthropic = encrypt(anthropic, encryptionKey);
        }
        if (xai) {
          toStore.xai = encrypt(xai, encryptionKey);
        }

        // Merge with existing keys
        const existing = await kv.get<ApiKeys>(kvKey);
        const merged = { ...existing, ...toStore };

        await kv.set(kvKey, merged);

        return res.status(200).json({ success: true, updatedAt: toStore.updatedAt });
      }

      case 'DELETE': {
        // Delete all keys for device
        await kv.del(kvKey);
        return res.status(200).json({ success: true });
      }

      default:
        return res.status(405).json({ error: 'Method not allowed' });
    }
  } catch (error) {
    console.error('KV Error:', error);
    return res.status(500).json({ error: 'Storage error' });
  }
}
