import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { INestApplication } from '@nestjs/common';

export const loadSwagger = (app: INestApplication) => {
  // The full route map (incl. internal endpoints) is public otherwise.
  if (process.env.DISABLE_SWAGGER === 'true') {
    return;
  }

  const config = new DocumentBuilder()
    .setTitle('Postiz Swagger file')
    .setDescription('API description')
    .setVersion('1.0')
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('docs', app, document);
};
