import { IsOptional, IsString } from 'class-validator';

export class PlatformCallbackDto {
  @IsString()
  @IsOptional()
  signed_request?: string;
}
