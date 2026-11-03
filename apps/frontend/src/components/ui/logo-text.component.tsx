import React from 'react';

// StellarByte brand: text logo replacing the upstream Postiz wordmark SVG
export const LogoTextComponent = () => {
  return (
    <div className="flex items-center gap-[8px] h-[33px]">
      <img src="/icon.svg" alt="StellarByte" width={33} height={33} />
      <span className="text-[24px] font-bold leading-none">StellarByte</span>
    </div>
  );
};
