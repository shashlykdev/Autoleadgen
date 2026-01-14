import type { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Verify authorization
  const apiSecret = process.env.API_SECRET;
  const authHeader = req.headers.authorization;

  if (!apiSecret || authHeader !== `Bearer ${apiSecret}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Return API keys from environment variables
  return res.status(200).json({
    openai: process.env.OPENAI_API_KEY || null,
    anthropic: process.env.ANTHROPIC_API_KEY || null,
    xai: process.env.XAI_API_KEY || null,
    apollo: process.env.APOLLO_API_KEY || null
  });
}
