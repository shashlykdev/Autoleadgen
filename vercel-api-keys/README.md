# Autoleadgen API Keys Storage

Vercel serverless API for secure API key storage using Vercel KV (Redis).

## Setup

### 1. Install Vercel CLI

```bash
npm install -g vercel
```

### 2. Deploy to Vercel

```bash
cd vercel-api-keys
vercel login
vercel
```

### 3. Set up Vercel KV

1. Go to your Vercel dashboard
2. Select your project
3. Go to **Storage** tab
4. Click **Create Database** → **KV**
5. Name it `autoleadgen-keys`
6. Click **Create**
7. The KV environment variables will be automatically added

### 4. Add Environment Variables

In your Vercel project settings, add these environment variables:

| Variable | Description |
|----------|-------------|
| `API_SECRET` | A secure random string (e.g., generate with `openssl rand -hex 32`) |
| `ENCRYPTION_KEY` | Another secure random string for key encryption |

### 5. Deploy to Production

```bash
vercel --prod
```

## API Endpoints

### Health Check
```
GET /api/health
```

### Get API Keys
```
GET /api/keys
Headers:
  Authorization: Bearer <API_SECRET>
  X-Device-ID: <unique-device-id>
```

### Store API Keys
```
POST /api/keys
Headers:
  Authorization: Bearer <API_SECRET>
  X-Device-ID: <unique-device-id>
Content-Type: application/json

{
  "openai": "sk-...",
  "anthropic": "sk-ant-...",
  "xai": "xai-..."
}
```

### Delete API Keys
```
DELETE /api/keys
Headers:
  Authorization: Bearer <API_SECRET>
  X-Device-ID: <unique-device-id>
```

## iOS App Configuration

After deploying, update your iOS app with:

1. **API URL**: Your Vercel deployment URL (e.g., `https://your-project.vercel.app`)
2. **API Secret**: The `API_SECRET` you configured

Store these in the app's configuration or as compile-time constants.

## Security Notes

- API keys are encrypted before storage using XOR + base64 (use AES for production)
- Each device has isolated key storage via device ID
- All requests require Bearer token authentication
- HTTPS is enforced by Vercel
