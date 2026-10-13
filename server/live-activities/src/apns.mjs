import { connect } from 'node:http2';
import { createPrivateKey, sign } from 'node:crypto';

export class APNs {
  constructor({ teamID, keyID, privateKey, bundleID, environment, connectionFactory = connect }) {
    if (!/^[A-Z0-9]{10}$/.test(teamID) || !/^[A-Z0-9]{10}$/.test(keyID) || !/^[\w.-]+$/.test(bundleID)
      || !['sandbox', 'production'].includes(environment)) throw Error('Invalid APNs configuration');
    Object.assign(this, { teamID, keyID, bundleID, environment });
    this.connectionFactory = connectionFactory;
    this.key = createPrivateKey(privateKey);
    if (this.key.asymmetricKeyType !== 'ec' || this.key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw Error('APNs requires an ES256 P-256 key');
  }
  jwt(now) {
    if (this.cached && now - this.issued < 3000) return this.cached;
    const encode = object => Buffer.from(JSON.stringify(object)).toString('base64url');
    const value = `${encode({ alg: 'ES256', kid: this.keyID })}.${encode({ iss: this.teamID, iat: Math.floor(now) })}`;
    this.cached = `${value}.${sign('sha256', Buffer.from(value), { key: this.key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
    this.issued = now;
    return this.cached;
  }
  async send(token, body, expires, now = Date.now() / 1000) {
    const host = this.environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    if (!this.session || this.session.closed || this.session.destroyed) {
      const connection = this.connectionFactory(host);
      this.session = connection;
      connection.on('error', () => {}); // Stream errors below carry delivery failure; never log tokens.
      connection.on('goaway', () => connection.close());
    }
    return new Promise((resolve, reject) => {
      const request = this.session.request({ ':method': 'POST', ':path': `/3/device/${token}`,
        authorization: `bearer ${this.jwt(now)}`, 'apns-push-type': 'liveactivity',
        'apns-topic': `${this.bundleID}.push-type.liveactivity`, 'apns-priority': '5',
        'apns-expiration': String(Math.floor(expires)), 'content-type': 'application/json' });
      let status, data = '';
      request.setTimeout(15000, () => { request.close(); reject(Error('APNs timeout')); });
      request.on('response', headers => { status = headers[':status']; });
      request.on('data', chunk => { if (data.length < 4096) data += chunk; });
      request.on('error', reject);
      request.on('end', () => {
        let reason; try { reason = JSON.parse(data).reason; } catch {}
        resolve({ status, reason });
      });
      request.end(JSON.stringify(body));
    });
  }
  close() { this.session?.close(); }
}
