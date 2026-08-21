# LensLab AI Retouch Server

This service runs the real GFPGAN face restoration model. LensLab keeps face
analysis and editing controls in the PWA, then calls this service for the
model-backed restoration pass.

## Start on Windows

Install Python 3.11, then run:

```powershell
cd ai-server
.\start.ps1
```

The first model check or retouch request downloads `GFPGANv1.4.pth` into `models/`.
Open `http://127.0.0.1:8000/health` to verify the service.

Alternatively, with Docker Desktop installed:

```powershell
docker compose up --build
```

In LensLab settings, set the AI endpoint to `http://127.0.0.1:8000` when the
browser and server run on the same computer.

For an iPad loading LensLab over HTTPS, the endpoint must also use trusted
HTTPS. Put this service behind Caddy, Cloudflare Tunnel, or another HTTPS
reverse proxy, then enter that HTTPS URL in LensLab settings. Browsers block an
HTTPS PWA from calling an insecure LAN HTTP endpoint.

## Production settings

These environment variables are supported:

```text
LENS_AI_ALLOWED_ORIGINS=https://your-site.example
LENS_AI_TOKEN=a-long-random-secret
LENS_AI_MODEL_DIR=D:\models
LENS_AI_MAX_UPLOAD_MB=40
```

If `LENS_AI_TOKEN` is set, callers must send it as a Bearer token or in the
`X-LensLab-Token` header. Do not expose an unauthenticated GPU server publicly.
