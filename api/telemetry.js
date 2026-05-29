const DOWN_TIMEOUT_MS = 60000;
const RECOVERY_STREAK_REQUIRED = 3;
const RECOVERY_BUFFER_MS = 45000;

export default async function handler(request, response) {
  const redisUrl = process.env.UPSTASH_REDIS_REST_URL;
  const redisToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  const secretAuthToken = process.env.HOMELAB_SECRET_KEY;
  const headers = { Authorization: `Bearer ${redisToken}` };

  if (request.method === 'GET') {
    try {
      const [dataRes, statusRes] = await Promise.all([
        fetch(`${redisUrl}/lrange/telemetry/0/59`, { headers }).then(r => r.json()),
        fetch(`${redisUrl}/get/telemetry_status`, { headers }).then(r => r.json())
      ]);

      const metrics = (dataRes.result || []).map(item => JSON.parse(item));
      let statusObj = statusRes.result ? JSON.parse(statusRes.result) : { state: 'DOWN', lastPing: 0, streak: 0 };

      if (Date.now() - statusObj.lastPing > DOWN_TIMEOUT_MS) {
        statusObj.state = 'DOWN';
      }

      return response.status(200).json({ status: statusObj.state, telemetry: metrics });
    } catch (error) {
      return response.status(500).json({ error: "Database read failed" });
    }
  }

  if (request.method === 'POST') {
    const authHeader = request.headers['authorization'];
    if (!authHeader || authHeader !== `Bearer ${secretAuthToken}`) {
      return response.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const now = Date.now();
      const statusRes = await fetch(`${redisUrl}/get/telemetry_status`, { headers }).then(r => r.json());
      let statusObj = statusRes.result ? JSON.parse(statusRes.result) : { state: 'DOWN', lastPing: 0, streak: 0 };

      const timeDiff = now - statusObj.lastPing;

      if (timeDiff > DOWN_TIMEOUT_MS) {
         statusObj.state = 'DOWN';
      }

      if (statusObj.state === 'DOWN') {
        if (timeDiff <= RECOVERY_BUFFER_MS) {
          statusObj.streak += 1;
        } else {
          statusObj.streak = 1;
        }
        
        if (statusObj.streak >= RECOVERY_STREAK_REQUIRED) {
          statusObj.state = 'UP';
        }
      } else {
        statusObj.streak = RECOVERY_STREAK_REQUIRED;
      }

      statusObj.lastPing = now;

      const payload = request.body;
      const stringifiedPayload = JSON.stringify(payload);
      const stringifiedStatus = JSON.stringify(statusObj);

      await Promise.all([
        fetch(`${redisUrl}/set/telemetry_status/${encodeURIComponent(stringifiedStatus)}`, { headers }),
        fetch(`${redisUrl}/lpush/telemetry/${encodeURIComponent(stringifiedPayload)}`, { headers })
      ]);

      await fetch(`${redisUrl}/ltrim/telemetry/0/59`, { headers });

      return response.status(200).json({ success: true, state: statusObj.state });
    } catch (error) {
      return response.status(500).json({ error: "Database write failed" });
    }
  }

  return response.status(405).json({ error: 'Method not allowed' });
}