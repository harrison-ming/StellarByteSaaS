import { Agent, buildConnector } from 'undici';
import axios, { AxiosInstance } from 'axios';
import dns from 'node:dns';
import net from 'node:net';
import http from 'node:http';
import https from 'node:https';
import { isBlockedIp } from './webhook.url.validator';

// Pins DNS resolution: every resolved IP is checked with `isBlockedIp` and
// the caller connects to that same set. Closes the TOCTOU window
// `isSafePublicHttpsUrl` alone leaves open (see GHSA-f7jj-p389-4w45).
function ssrfSafeLookup(
  hostname: string,
  options: any,
  callback: (
    err: NodeJS.ErrnoException | null,
    address: any,
    family?: number
  ) => void
) {
  if (net.isIP(hostname)) {
    const family = net.isIP(hostname);
    if (isBlockedIp(hostname)) {
      return callback(new Error('Blocked IP'), '', 0);
    }
    return options && (options as any).all
      ? callback(null, [{ address: hostname, family }] as any, family)
      : callback(null, hostname, family);
  }

  dns.lookup(hostname, options, (err, address: any, family: any) => {
    if (err) return callback(err, '', 0);
    if (Array.isArray(address)) {
      for (const entry of address) {
        if (isBlockedIp(entry.address)) {
          return callback(new Error('Blocked IP'), '', 0);
        }
      }
      return callback(null, address as any, 0);
    }
    if (isBlockedIp(address)) {
      return callback(new Error('Blocked IP'), '', 0);
    }
    callback(null, address, family);
  });
}

// Node (net/tls) and undici skip the `lookup` hook entirely when the target
// host is already an IP literal, so `http://169.254.169.254/` or a redirect to
// `http://127.0.0.1/` would never reach `ssrfSafeLookup`. Every connection is
// therefore also checked here, right before the socket is opened; this covers
// the first request and every redirect hop, because each hop opens its own
// connection through the same dispatcher / agent.
function blockedLiteralHost(host?: string | null): boolean {
  if (!host) {
    return false;
  }
  const bare = host.replace(/^\[|\]$/g, '');
  return net.isIP(bare) !== 0 && isBlockedIp(bare);
}

const baseConnector = buildConnector({ lookup: ssrfSafeLookup } as any);

export const ssrfSafeDispatcher = new Agent({
  connect: (options, callback) => {
    if (blockedLiteralHost(options.hostname)) {
      return callback(new Error('Blocked IP'), null);
    }
    return baseConnector(options, callback);
  },
});

class SsrfSafeHttpAgent extends http.Agent {
  createConnection(options: any, callback: any) {
    if (blockedLiteralHost(options.host)) {
      callback(new Error('Blocked IP'));
      return undefined as any;
    }
    // createConnection is public Node API but missing from @types/node
    return (http.Agent.prototype as any).createConnection.call(
      this,
      options,
      callback
    );
  }
}

class SsrfSafeHttpsAgent extends https.Agent {
  createConnection(options: any, callback: any) {
    if (blockedLiteralHost(options.host)) {
      callback(new Error('Blocked IP'));
      return undefined as any;
    }
    // createConnection is public Node API but missing from @types/node
    return (https.Agent.prototype as any).createConnection.call(
      this,
      options,
      callback
    );
  }
}

// axios can't use an undici dispatcher, but Node's http(s) agents accept the
// same `lookup` hook, so axios requests (providers that need form-data /
// stream uploads) get the identical pinned-DNS guard as `this.fetch`.
const ssrfSafeAxios = axios.create({
  httpAgent: new SsrfSafeHttpAgent({
    lookup: ssrfSafeLookup,
  } as http.AgentOptions),
  httpsAgent: new SsrfSafeHttpsAgent({
    lookup: ssrfSafeLookup,
  } as https.AgentOptions),
});

// Self-hosters legitimately connect Postiz to WordPress/Mastodon/Lemmy/Listmonk
// instances that live on a private network (e.g. the same Docker network or VPC).
// Setting DISABLE_SSRF_PROTECTION=true opts those deployments out of the IP
// guard. It stays ON by default so the hosted product is protected.
export function getSsrfSafeDispatcher(): Agent | undefined {
  return process.env.DISABLE_SSRF_PROTECTION === 'true'
    ? undefined
    : ssrfSafeDispatcher;
}

export function getSsrfSafeAxios(): AxiosInstance {
  return process.env.DISABLE_SSRF_PROTECTION === 'true' ? axios : ssrfSafeAxios;
}
