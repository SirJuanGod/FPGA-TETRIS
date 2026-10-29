# FPGA-TETRIS

Tetris en VHDL para la **Terasic DE10-Standard** (Cyclone V SoC `5CSXFC6D6F31C6`) con salida **VGA 640x480 @ 60 Hz**.

## Controles

| Botón | Acción |
|-------|--------|
| KEY3 | Mover a la izquierda |
| KEY2 | Mover a la derecha |
| KEY1 | Rotar |
| KEY0 | Bajar rápido (mientras se mantiene presionado) |

Cuando una pieza nueva ya no cabe, el tablero se limpia y empieza otra partida.

## Archivos

- `tetris.vhd` — todo el diseño: paquete con piezas y colisiones, lógica del juego y controlador VGA.
- `tetris.qpf`, `tetris.qsf`, `tetris.sdc` — proyecto de Quartus con los pines de la DE10-Standard.
- `tb_tetris.vhd` — banco de pruebas (rotación, movimiento, borrado de línea y tiempos VGA).

## Compilar y programar

1. Abrir `tetris.qpf` en Quartus Prime (Lite sirve).
2. *Processing → Start Compilation*.
3. *Tools → Programmer*, cargar `output_files/tetris.sof` en el dispositivo `5CSXFC6` de la cadena JTAG (la DE10-Standard muestra también el HPS; programa solo la FPGA).
4. Conectar un monitor al puerto VGA.

## Simular (GHDL)

```sh
ghdl -a --std=08 tetris.vhd tb_tetris.vhd
ghdl -r --std=08 tb_tetris --assert-level=error
```

Debe imprimir `juego OK` y `VGA OK`.
