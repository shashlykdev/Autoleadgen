import type { VercelRequest, VercelResponse } from '@vercel/node';

interface Model {
  id: string;
  name: string;
  provider: string;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
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

  const models: Model[] = [];

  // Fetch OpenAI models
  if (process.env.OPENAI_API_KEY) {
    try {
      const response = await fetch('https://api.openai.com/v1/models', {
        headers: { 'Authorization': `Bearer ${process.env.OPENAI_API_KEY}` }
      });
      if (response.ok) {
        const data = await response.json();
        const chatModels = data.data
          .filter((m: any) => m.id.includes('gpt'))
          .map((m: any) => ({
            id: m.id,
            name: m.id,
            provider: 'openai'
          }))
          .sort((a: Model, b: Model) => b.id.localeCompare(a.id));
        models.push(...chatModels.slice(0, 10)); // Top 10 GPT models
      }
    } catch (e) {
      console.error('OpenAI error:', e);
    }
  }

  // Fetch Anthropic models (no list endpoint, hardcode available ones)
  if (process.env.ANTHROPIC_API_KEY) {
    models.push(
      { id: 'claude-sonnet-4-20250514', name: 'Claude Sonnet 4', provider: 'anthropic' },
      { id: 'claude-3-5-sonnet-20241022', name: 'Claude 3.5 Sonnet', provider: 'anthropic' },
      { id: 'claude-3-5-haiku-20241022', name: 'Claude 3.5 Haiku', provider: 'anthropic' },
      { id: 'claude-3-opus-20240229', name: 'Claude 3 Opus', provider: 'anthropic' },
      { id: 'claude-3-haiku-20240307', name: 'Claude 3 Haiku', provider: 'anthropic' }
    );
  }

  // Fetch xAI models
  if (process.env.XAI_API_KEY) {
    try {
      const response = await fetch('https://api.x.ai/v1/models', {
        headers: { 'Authorization': `Bearer ${process.env.XAI_API_KEY}` }
      });
      if (response.ok) {
        const data = await response.json();
        const xaiModels = data.data.map((m: any) => ({
          id: m.id,
          name: m.id,
          provider: 'xai'
        }));
        models.push(...xaiModels);
      }
    } catch (e) {
      console.error('xAI error:', e);
    }
  }

  return res.status(200).json({ models });
}
