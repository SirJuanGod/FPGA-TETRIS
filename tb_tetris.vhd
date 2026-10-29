-- Simulación con GHDL:
--   ghdl -a --std=08 tetris.vhd tb_tetris.vhd && ghdl -e --std=08 tb_tetris && ghdl -r --std=08 tb_tetris
library ieee;
use ieee.std_logic_1164.all;
use work.tetris_pkg.all;

entity tb_tetris is
end entity;

architecture sim of tb_tetris is
  -- La fila de abajo empieza llena para probar que se borra al fijar la primera pieza
  constant FULL19 : board_t := (19 => (others => 1), others => (others => 0));

  signal clk     : std_logic := '0';
  signal key     : std_logic_vector(3 downto 0) := "1111";
  signal hs, vs  : std_logic;
  signal game_ok : boolean := false;
  signal done    : boolean := false;

begin
  clk <= not clk after 10 ns when not done;

  dut : entity work.tetris
    generic map (GRAVITY => 2000, DEBOUNCE => 10, INIT => FULL19)
    port map (CLOCK_50 => clk, KEY => key, VGA_HS => hs, VGA_VS => vs);

  game : process
    procedure press(k : natural) is
    begin
      key(k) <= '0'; wait for 1 us;
      key(k) <= '1'; wait for 1 us;
    end procedure;
    variable minc, n : integer;
    alias board is <<signal .tb_tetris.dut.board : board_t>>;
    alias piece is <<signal .tb_tetris.dut.piece : natural range 0 to 6>>;
    alias rot   is <<signal .tb_tetris.dut.rot : natural range 0 to 3>>;
    alias px    is <<signal .tb_tetris.dut.px : integer range -3 to 12>>;
  begin
    wait for 5 us;
    press(1);
    assert rot = 1 report "no giró" severity failure;

    for i in 1 to 10 loop press(3); end loop;
    minc := 99;
    for r in 0 to 3 loop
      for c in 0 to 3 loop
        if filled(piece, rot, r, c) and px + c < minc then minc := px + c; end if;
      end loop;
    end loop;
    assert minc = 0 report "la pieza no quedó pegada a la pared izquierda" severity failure;

    wait until board(19) /= (0 to COLS-1 => 1) for 2 ms;
    n := 0;
    for r in 0 to ROWS-1 loop
      for c in 0 to COLS-1 loop
        if board(r)(c) /= 0 then n := n + 1; end if;
      end loop;
    end loop;
    assert n = 4 report "la fila llena no se borró: celdas=" & integer'image(n) severity failure;

    report "juego OK";
    game_ok <= true;
    wait;
  end process;

  vga : process
    variable t0 : time;
  begin
    wait until falling_edge(hs); t0 := now;
    wait until rising_edge(hs);
    assert now - t0 = 96 * 40 ns report "pulso HS incorrecto" severity failure;
    wait until falling_edge(hs);
    assert now - t0 = 800 * 40 ns report "periodo HS incorrecto" severity failure;
    wait until falling_edge(vs); t0 := now;
    wait until rising_edge(vs);
    assert now - t0 = 2 * 800 * 40 ns report "pulso VS incorrecto" severity failure;
    wait until falling_edge(vs);
    assert now - t0 = 525 * 800 * 40 ns report "periodo VS incorrecto" severity failure;
    report "VGA OK";

    if not game_ok then wait until game_ok; end if;
    done <= true;
    wait;
  end process;
end architecture;
