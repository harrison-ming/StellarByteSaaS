import { ThrottlerGuard } from '@nestjs/throttler';
import { ExecutionContext, Injectable } from '@nestjs/common';
import { Request } from 'express';

// Behind Cloudflare the left-most X-Forwarded-For entry is whatever the client
// sent (Cloudflare appends, it does not replace), so it can be rotated to
// dodge the limit. CF-Connecting-IP is set by Cloudflare itself; fall back to
// X-Forwarded-For only for deployments without it.
const clientIp = (req: Record<string, any>): string =>
  String(req.headers?.['cf-connecting-ip'] || '').trim() ||
  String(req.headers?.['x-forwarded-for'] || '')
    .split(',')[0]
    .trim() ||
  req.ip ||
  'unknown';

const isPublicComment = (method: string, url: string) =>
  method === 'POST' && /^\/public\/posts\/[^/]+\/comments/.test(url);

@Injectable()
export class ThrottlerBehindProxyGuard extends ThrottlerGuard {
  public override async canActivate(
    context: ExecutionContext
  ): Promise<boolean> {
    const { url, method } = context.switchToHttp().getRequest<Request>();
    if (
      (method === 'POST' && url.includes('/public/v1/posts')) ||
      isPublicComment(method, url)
    ) {
      return super.canActivate(context);
    }

    return true;
  }

  protected override async getTracker(
    req: Record<string, any>
  ): Promise<string> {
    if (!req.org) {
      return 'ip_' + clientIp(req);
    }

    return (
      req.org.id + '_' + (req.url.indexOf('/posts') > -1 ? 'posts' : 'other')
    );
  }
}

// route-level guard for public endpoints, keyed by the client address the
// proxy forwards rather than the org the global guard expects
@Injectable()
export class ThrottlerRealIpGuard extends ThrottlerGuard {
  protected override async getTracker(
    req: Record<string, any>
  ): Promise<string> {
    return clientIp(req);
  }
}
