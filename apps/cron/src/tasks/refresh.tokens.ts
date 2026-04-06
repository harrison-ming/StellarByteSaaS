import { Injectable } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { IntegrationService } from '@gitroom/nestjs-libraries/database/prisma/integrations/integration.service';

@Injectable()
export class RefreshTokens {
  constructor(private _integrationService: IntegrationService) {}
  @Cron('0 */6 * * *')
  async handleCron() {
    console.log(`[${new Date().toISOString()}] Starting token refresh`);
    await this._integrationService.refreshTokens();
    console.log(`[${new Date().toISOString()}] Token refresh completed`);
  }
}
