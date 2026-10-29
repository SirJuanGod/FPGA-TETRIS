library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tetris_pkg is
  constant COLS : natural := 10;
  constant ROWS : natural := 20;
  subtype cell_t is natural range 0 to 7;  -- 0 = vacía, 1..7 = color de la pieza
  type row_t is array (0 to COLS-1) of cell_t;
  type board_t is array (0 to ROWS-1) of row_t;
  type shapes_t is array (0 to 6) of std_logic_vector(0 to 15);

  -- Rotación 0 de cada pieza en una caja 4x4 (bit = fila*4 + col): I O T S Z J L
  constant SHAPES : shapes_t := (
    "0000111100000000", "0000011001100000", "0100111000000000", "0110110000000000",
    "1100011000000000", "1000111000000000", "0010111000000000");

  function filled(p : natural range 0 to 6; rot : natural range 0 to 3; r, c : integer) return boolean;
  function fits(b : board_t; p : natural range 0 to 6; rot : natural range 0 to 3; x, y : integer) return boolean;
end package;

package body tetris_pkg is
  -- ¿La celda (r, c) de la caja 4x4 está ocupada por la pieza p girada rot veces a la derecha?
  function filled(p : natural range 0 to 6; rot : natural range 0 to 3; r, c : integer) return boolean is
    variable n : integer := 3;
    variable rr, cc, t : integer;
  begin
    if p <= 1 then n := 4; end if;  -- I y O giran en 4x4, el resto en 3x3
    if r < 0 or c < 0 or r >= n or c >= n then return false; end if;
    rr := r; cc := c;
    for k in 1 to 3 loop
      if k <= rot then t := rr; rr := n - 1 - cc; cc := t; end if;
    end loop;
    return SHAPES(p)(rr*4 + cc) = '1';
  end function;

  -- ¿Cabe la pieza con su caja en (x, y) sin salirse ni chocar? Filas negativas (arriba) se permiten.
  function fits(b : board_t; p : natural range 0 to 6; rot : natural range 0 to 3; x, y : integer) return boolean is
    variable ok : boolean := true;
  begin
    for r in 0 to 3 loop
      for c in 0 to 3 loop
        if filled(p, rot, r, c) then
          if x + c < 0 or x + c >= COLS or y + r >= ROWS then
            ok := false;
          elsif y + r >= 0 then
            if b(y + r)(x + c) /= 0 then ok := false; end if;
          end if;
        end if;
      end loop;
    end loop;
    return ok;
  end function;
end package body;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tetris is
  generic (
    GRAVITY  : positive := 25_000_000;  -- ciclos de 50 MHz por cada caída (0.5 s)
    DEBOUNCE : positive := 500_000;     -- los botones se muestrean cada 10 ms
    INIT     : board_t  := (others => (others => 0)));
  port (
    CLOCK_50 : in  std_logic;
    KEY      : in  std_logic_vector(3 downto 0);  -- activos en bajo: 3=izq 2=der 1=rotar 0=bajar
    VGA_R, VGA_G, VGA_B : out std_logic_vector(7 downto 0);
    VGA_CLK, VGA_BLANK_N, VGA_SYNC_N, VGA_HS, VGA_VS : out std_logic);
end entity;

architecture rtl of tetris is
  constant BX : integer := 220;  -- esquina superior izquierda del tablero en pantalla
  constant BY : integer := 40;
  constant CS : integer := 20;   -- pixeles por celda

  type palette_t is array (cell_t) of std_logic_vector(23 downto 0);
  constant PALETTE : palette_t := (x"000000", x"00F0F0", x"F0F000", x"A000F0",
                                   x"00F000", x"F00000", x"0000F0", x"F0A000");

  signal board : board_t := INIT;
  signal piece : natural range 0 to 6 := 0;
  signal rot   : natural range 0 to 3 := 0;
  signal px    : integer range -3 to 12 := 3;
  signal py    : integer range -3 to 22 := 0;

  type state_t is (SPAWN, PLAY, CHECK, CLEAR);
  type act_t is (MOVE, FALL, NEW_PIECE);
  signal state : state_t := SPAWN;
  signal act   : act_t := MOVE;
  signal c_rot : natural range 0 to 3 := 0;      -- posición candidata que CHECK valida
  signal c_x   : integer range -3 to 12 := 3;
  signal c_y   : integer range -3 to 22 := 0;
  signal crow  : integer range -1 to ROWS-1 := ROWS-1;

  signal lfsr      : std_logic_vector(15 downto 0) := x"ACE1";
  signal key_sync  : std_logic_vector(3 downto 0) := (others => '0');
  signal keys      : std_logic_vector(3 downto 0) := (others => '0');
  signal pend      : std_logic_vector(3 downto 0) := (others => '0');
  signal fall_pend : std_logic := '0';
  signal deb_cnt   : natural range 0 to DEBOUNCE-1 := 0;
  signal grav_cnt  : natural range 0 to GRAVITY+7 := 0;

  signal pclk : std_logic := '0';
  signal hc   : natural range 0 to 799 := 0;
  signal vc   : natural range 0 to 524 := 0;
begin

  game : process (CLOCK_50)
    variable p    : std_logic_vector(3 downto 0);
    variable f    : std_logic;
    variable full : boolean;
  begin
    if rising_edge(CLOCK_50) then
      lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      p := pend;
      f := fall_pend;

      -- Botones: sincronizar y muestrear cada 10 ms (antirrebote); un flanco de bajada = una acción
      key_sync <= not KEY;
      if deb_cnt = DEBOUNCE-1 then
        deb_cnt <= 0;
        keys <= key_sync;
        p := p or (key_sync and not keys);
      else
        deb_cnt <= deb_cnt + 1;
      end if;

      -- Gravedad: 8 veces más rápida mientras KEY0 está presionado
      if grav_cnt >= GRAVITY then
        grav_cnt <= 0;
        f := '1';
      elsif keys(0) = '1' then
        grav_cnt <= grav_cnt + 8;
      else
        grav_cnt <= grav_cnt + 1;
      end if;

      case state is
        when SPAWN =>
          piece <= to_integer(unsigned(lfsr)) mod 7;
          c_x <= 3; c_y <= 0; c_rot <= 0;
          act <= NEW_PIECE;
          state <= CHECK;

        when PLAY =>
          c_x <= px; c_y <= py; c_rot <= rot;
          act <= MOVE;
          state <= CHECK;
          if p(1) = '1' then
            p(1) := '0'; c_rot <= (rot + 1) mod 4;
          elsif p(3) = '1' then
            p(3) := '0'; c_x <= px - 1;
          elsif p(2) = '1' then
            p(2) := '0'; c_x <= px + 1;
          elsif f = '1' then
            f := '0'; c_y <= py + 1; act <= FALL;
          else
            state <= PLAY;
          end if;

        when CHECK =>
          state <= PLAY;
          if fits(board, piece, c_rot, c_x, c_y) then
            px <= c_x; py <= c_y; rot <= c_rot;
          elsif act = FALL then  -- ya no puede bajar: se fija en el tablero
            for r in 0 to 3 loop
              for c in 0 to 3 loop
                if filled(piece, rot, r, c) and py + r >= 0 then
                  board(py + r)(px + c) <= piece + 1;
                end if;
              end loop;
            end loop;
            crow <= ROWS-1;
            state <= CLEAR;
          elsif act = NEW_PIECE then  -- la pieza nueva no cabe: fin del juego, empieza otro
            board <= (others => (others => 0));
            state <= SPAWN;
          end if;

        when CLEAR =>  -- revisa de abajo hacia arriba y baja todo lo que está encima de cada fila llena
          if crow < 0 then
            state <= SPAWN;
          else
            full := true;
            for c in 0 to COLS-1 loop
              if board(crow)(c) = 0 then full := false; end if;
            end loop;
            if full then
              for r in ROWS-1 downto 1 loop
                if r <= crow then board(r) <= board(r - 1); end if;
              end loop;
              board(0) <= (others => 0);
            else
              crow <= crow - 1;
            end if;
          end if;
      end case;

      pend <= p;
      fall_pend <= f;
    end if;
  end process;

  -- VGA 640x480 a 60 Hz: el pixel avanza cada 2 ciclos (25 MHz, el monitor tolera la diferencia con 25.175)
  vga : process (CLOCK_50)
    variable x   : integer range -BX to 799;
    variable y   : integer range -BY to 524;
    variable col : integer range 0 to COLS-1;
    variable row : integer range 0 to ROWS-1;
    variable cell : cell_t;
    variable rgb : std_logic_vector(23 downto 0);
  begin
    if rising_edge(CLOCK_50) then
      pclk <= not pclk;
      if pclk = '1' then  -- los datos cambian aquí y el DAC los toma en el siguiente flanco de subida de VGA_CLK
        if hc = 799 then
          hc <= 0;
          if vc = 524 then vc <= 0; else vc <= vc + 1; end if;
        else
          hc <= hc + 1;
        end if;

        x := hc - BX;
        y := vc - BY;
        rgb := x"000000";
        if x >= 0 and x < COLS*CS and y >= 0 and y < ROWS*CS then
          col := x / CS;
          row := y / CS;
          if x mod CS /= 0 and y mod CS /= 0 then  -- línea negra entre celdas
            cell := board(row)(col);
            if filled(piece, rot, row - py, col - px) then cell := piece + 1; end if;
            rgb := PALETTE(cell);
          end if;
        elsif x >= -4 and x < COLS*CS + 4 and y >= -4 and y < ROWS*CS + 4 then
          rgb := x"808080";  -- marco
        end if;

        VGA_R <= rgb(23 downto 16);
        VGA_G <= rgb(15 downto 8);
        VGA_B <= rgb(7 downto 0);
        if hc >= 656 and hc < 752 then VGA_HS <= '0'; else VGA_HS <= '1'; end if;
        if vc >= 490 and vc < 492 then VGA_VS <= '0'; else VGA_VS <= '1'; end if;
        if hc < 640 and vc < 480 then VGA_BLANK_N <= '1'; else VGA_BLANK_N <= '0'; end if;
      end if;
    end if;
  end process;

  VGA_CLK    <= pclk;
  VGA_SYNC_N <= '0';
end architecture;
