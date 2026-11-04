import { google } from 'googleapis';
import { HttpException } from '@nestjs/common';
import {
  AuthProvider,
  AuthProviderAbstract,
} from '@gitroom/backend/services/auth/providers.interface';

const defaultRedirect = () =>
  `${process.env.FRONTEND_URL}/integrations/social/youtube`;

const makeClient = (redirectUri: string) =>
  new google.auth.OAuth2({
    clientId: process.env.GOOGLE_LOGIN_CLIENT_ID,
    clientSecret: process.env.GOOGLE_LOGIN_CLIENT_SECRET,
    redirectUri,
  });

@AuthProvider({ provider: 'GOOGLE' })
export class GoogleProvider extends AuthProviderAbstract {
  generateLink(query?: { redirect_uri?: string; state?: string }) {
    const redirectUri = query?.redirect_uri || defaultRedirect();
    return makeClient(redirectUri).generateAuthUrl({
      access_type: 'online',
      prompt: 'consent',
      state: query?.state || 'login',
      redirect_uri: redirectUri,
      scope: [
        'https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/userinfo.email',
      ],
    });
  }

  async getToken(code: string, redirectUri?: string) {
    const client = makeClient(redirectUri || defaultRedirect());
    try {
      const { tokens } = await client.getToken(code);
      return tokens.access_token!;
    } catch (err: any) {
      // The code is single use and short lived (callback reloaded or too slow)
      if (err?.response?.data?.error === 'invalid_grant') {
        throw new HttpException(
          'Google sign-in expired, please sign in again',
          400
        );
      }
      throw err;
    }
  }

  async getUser(providerToken: string) {
    const client = makeClient(defaultRedirect());
    // the token is sent back by the client during registration, so it must
    // have been issued to our login client and not to another Google app
    const { aud, email_verified } = await client.getTokenInfo(providerToken);
    if (aud !== process.env.GOOGLE_LOGIN_CLIENT_ID) {
      throw new Error('Invalid provider token');
    }

    client.setCredentials({ access_token: providerToken });
    const { data } = await google
      .oauth2({ version: 'v2', auth: client })
      .userinfo.get();

    return {
      id: data.id!,
      email: data.email!,
      emailVerified: !!email_verified,
    };
  }
}
