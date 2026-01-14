import type { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const apiSecret = process.env.API_SECRET;
  const authHeader = req.headers.authorization;

  return res.status(200).json({
    hasApiSecret: !!apiSecret,
    apiSecretLength: apiSecret?.length || 0,
    apiSecretFirst4: apiSecret?.substring(0, 4) || 'none',
    authHeader: authHeader ? `${authHeader.substring(0, 20)}...` : 'none',
    authHeaderLength: authHeader?.length || 0,
    match: authHeader === `Bearer ${apiSecret}`
  });
}
