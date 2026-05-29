# Homelab Telemetry Dashboard (POC)

This is a POC for testing for Push architecture. 
This will allow you to send metrics from your system to a frontend hosting in services. 

**Note: This is a Proof of Concept (POC).**

## The Problem

Having a homelab, if you need to do something externally, you almost always need a static IP or a domain (like a Cloudflare tunnel). For a task like just seeing metrics, do we really need a static IP? I tried this push architecture approach and it works better than I thought. 

The goal needs some way to see metrics for FREE. This entire setup will run completely within the free tiers of both Vercel and Upstash.

Note: To securely access your homelab across the internet without exposing your local network, Tailscale is a great proxy/VPN tool. (I mention this only because I use it personally and find it helpful. I have no affiliation with them—always do your own research and use at your own risk.)

## Architecture

Instead of the frontend trying to reach into your secure home network (which requires port forwarding or VPNs), your local server pushes its data out to a cloud database (Upstash Redis). The frontend (hosted on Vercel) simply reads that database. 

## API Specification

You can write whatever script or backend you want in any language. Your script just needs to send an HTTP POST request to the Vercel API endpoint.

### Endpoint
`POST /api/telemetry`

### Headers
* `Content-Type: application/json`
* `Authorization: Bearer <YOUR_HOMELAB_SECRET_KEY>`

### Request Payload
The API expects a JSON payload representing the current system state. Send this every 5-30 seconds.

```json
{
  "timestamp": "2026-05-30T02:15:00Z",
  "cpu_percent": 62.4,
  "memory": {
    "used_gb": 8.5,
    "total_gb": 16.0,
    "percent": 53.1
  },
  "network": {
    "download_kbps": 1250.5,
    "upload_kbps": 420.2
  },
  "storage": {
    "used_gb": 120.0,
    "total_gb": 500.0,
    "percent": 24.0
  }
}