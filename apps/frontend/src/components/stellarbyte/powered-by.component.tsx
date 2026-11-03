import { FC } from 'react';
import clsx from 'clsx';

// StellarByte attribution footer (AGPL-3.0 section 13 + honest attribution,
// see docs/redeploy-spec.md D10). Links to the exact public source of this
// deployment.
export const STELLARBYTE_SOURCE_URL =
  'https://github.com/harrison-ming/StellarByteSaaS';

export const PoweredByFooter: FC<{ className?: string }> = ({ className }) => {
  return (
    <div
      className={clsx(
        'text-[12px] text-center opacity-60 py-[6px] select-none',
        className
      )}
    >
      Powered by{' '}
      <a
        href="https://github.com/gitroomhq/postiz-app"
        target="_blank"
        rel="noopener noreferrer"
        className="underline hover:opacity-100"
      >
        Postiz
      </a>
      {' · '}
      <a
        href={STELLARBYTE_SOURCE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="underline hover:opacity-100"
      >
        Source
      </a>
    </div>
  );
};
