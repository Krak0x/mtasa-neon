# 2026-07-12 Windows VM entity profile

Environment:

- GTA SA 1.0 US under the Neon `Release|Win32` client;
- local server at `127.0.0.1:22003`;
- server FPS limit 120, client limited to 120 by VSync;
- unrelated Neon stress/demo resources stopped;
- fixed origin `(-698.46, 958.41, 12.31)` and fixed cameras;
- standard models: vehicle 411, ped 7, object 1271;
- five-second warm-up and one ten-second measurement per stage;
- client-local entities, so these results exclude real network traffic and
  remote-player interpolation.

This is one complete unattended profile, not three repeated samples. Keep p95,
p99, and worst-frame values; do not reduce the result to average FPS.

| # | Scenario | FPS | avg ms | p95 ms | p99 ms | worst ms |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | baseline static/visible | 104.4 | 9.57 | 11.20 | 15.08 | 23.60 |
| 2 | baseline static/hidden | 80.5 | 12.43 | 13.61 | 14.66 | 16.88 |
| 3 | vehicle 16 idle/visible/separate | 83.7 | 11.95 | 12.81 | 13.96 | 16.60 |
| 4 | vehicle 32 idle/visible/separate | 68.6 | 14.58 | 15.94 | 19.14 | 23.22 |
| 5 | vehicle 48 idle/visible/separate | 49.2 | 20.32 | 27.12 | 42.50 | 67.17 |
| 6 | vehicle 64 idle/visible/separate | 53.8 | 18.60 | 23.07 | 28.58 | 50.82 |
| 7 | vehicle 64 idle/hidden/separate | 71.9 | 13.90 | 15.41 | 19.91 | 23.72 |
| 8 | vehicle 64 idle/far/separate | 78.3 | 12.77 | 13.76 | 16.21 | 30.53 |
| 9 | vehicle 64 moving/visible/separate | 50.8 | 19.68 | 24.12 | 31.77 | 51.06 |
| 10 | vehicle 16 moving/visible/touching | 73.5 | 13.61 | 16.10 | 19.73 | 21.37 |
| 11 | vehicle 32 moving/visible/touching | 38.1 | 26.22 | 33.94 | 37.54 | 42.45 |
| 12 | vehicle 64 moving/visible/touching | 25.7 | 38.89 | 50.80 | 57.29 | 62.17 |
| 13 | vehicle 4 moving/visible/deep-contact | 47.9 | 20.92 | 24.98 | 31.17 | 45.34 |
| 14 | vehicle 8 moving/visible/deep-contact | 46.2 | 21.64 | 24.25 | 28.97 | 43.12 |
| 15 | vehicle 16 moving/visible/deep-contact | 6.4 | 157.23 | 176.50 | 184.04 | 184.04 |
| 16 | vehicle 16 moving/visible/deep-contact, collision off | 84.0 | 11.90 | 14.24 | 17.62 | 23.05 |
| 17 | ped 32 idle/visible/separate | 75.6 | 13.23 | 14.74 | 16.09 | 20.56 |
| 18 | ped 64 idle/visible/separate | 59.5 | 16.81 | 18.37 | 19.47 | 27.11 |
| 19 | ped 96 idle/visible/separate | 49.3 | 20.28 | 23.26 | 33.63 | 96.00 |
| 20 | ped 110 idle/visible/separate | 46.1 | 21.68 | 25.82 | 29.27 | 37.58 |
| 21 | ped 110 moving/visible/separate | 43.9 | 22.78 | 24.82 | 29.07 | 32.54 |
| 22 | ped 110 moving/hidden/separate | 45.5 | 21.98 | 23.76 | 26.60 | 30.65 |
| 23 | ped 110 moving/far/separate | 81.8 | 12.22 | 13.41 | 14.91 | 17.40 |
| 24 | object 128 static/visible/separate | 99.8 | 10.01 | 12.21 | 16.97 | 26.80 |
| 25 | object 512 static/visible/separate | 102.1 | 9.79 | 10.90 | 12.57 | 21.06 |
| 26 | object 900 static/visible/separate | 100.3 | 9.97 | 11.38 | 12.95 | 15.05 |
| 27 | object 1000 static/visible/separate | 99.7 | 10.03 | 11.58 | 15.15 | 30.36 |
| 28 | object 1000 static/hidden/separate | 76.8 | 13.02 | 16.01 | 20.75 | 25.76 |
| 29 | object 1000 static/far/separate | 82.1 | 12.18 | 13.34 | 14.43 | 19.66 |
| 30 | object 900 moving/visible/separate | 97.5 | 10.26 | 11.47 | 13.49 | 16.87 |
| 31 | mixed 96 idle/visible/separate | 49.4 | 20.26 | 22.42 | 26.72 | 55.39 |
| 32 | mixed 192 idle/visible/separate | 37.5 | 26.66 | 30.68 | 38.84 | 52.02 |
| 33 | mixed 192 moving/visible/separate | 32.0 | 31.24 | 33.97 | 36.87 | 40.13 |

Renderer high-water observations from the same log:

- visible entities were 36 for the visible baseline and 27 for the hidden
  baseline;
- separated idle vehicles reached 58, 74, 88, and 88 visible pointers at
  requested counts 16, 32, 48, and 64, so the 48-to-64 comparison did not add
  visible density;
- touching vehicles reached 56, 72, and 92 visible pointers at 16, 32, and 64;
- idle peds reached 72, 99, 118, and 124 visible pointers at 32, 64, 96, and 110;
- standard-object scenarios stayed near 88-89 visible pointers while the
  streaming RwObject high-water reached 966. Those runs test total/streamed
  population, not 1000 simultaneously visible objects.

No new crash dump was produced and the client remained responsive after all 33
stages. Full `console.log` remains in the VM test installation.
