'use client';

import { useCallback } from 'react';
import Particles from 'react-tsparticles';
import { loadSlim } from 'tsparticles-slim';
import type { Engine } from 'tsparticles-engine';

export function ParticlesBackground() {
  const particlesInit = useCallback(async (engine: Engine) => {
    await loadSlim(engine);
  }, []);

  return (
    <Particles
      id="tsparticles"
      init={particlesInit}
      options={{
        background: {
          color: {
            value: 'transparent',
          },
        },
        fpsLimit: 60,
        interactivity: {
          events: {
            onHover: {
              enable: true,
              mode: 'grab',
            },
            resize: true,
          },
          modes: {
            grab: {
              distance: 140,
              links: {
                opacity: 0.5,
              },
            },
          },
        },
        particles: {
          number: {
            value: 60,
            density: {
              enable: true,
              area: 800,
            },
          },
          color: {
            value: '#01d408',
          },
          shape: {
            type: 'triangle',
          },
          opacity: {
            value: 0.5,
            random: false,
          },
          size: {
            value: 3,
            random: true,
          },
          links: {
            enable: true,
            distance: 120,
            color: '#01d408',
            opacity: 0.3,
            width: 1,
          },
          move: {
            enable: true,
            speed: 1.8,
            direction: 'none',
            random: false,
            straight: false,
            outModes: {
              default: 'bounce',
            },
            attract: {
              enable: false,
            },
          },
        },
        detectRetina: true,
      }}
    />
  );
}
