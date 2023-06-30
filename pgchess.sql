-- pgchess, an extension for playing and analysing Chess games
-- Copyright (C) 2010-2012, 2022 Gianni Ciolli <gianni.ciolli@enterprisedb.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
------------------------------------------------------------------------

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pgchess" to load this file. \quit

CREATE FUNCTION piece_value(character(1))
RETURNS double precision
LANGUAGE sql
AS $$
SELECT CASE $1
WHEN ' ' THEN 0
WHEN 'p' THEN -1
WHEN 'r' THEN -5
WHEN 'n' THEN -3
WHEN 'b' THEN -3
WHEN 'q' THEN -9
WHEN 'k' THEN double precision '-Infinity'
WHEN 'P' THEN 1
WHEN 'R' THEN 5
WHEN 'N' THEN 3
WHEN 'B' THEN 3
WHEN 'Q' THEN 9
WHEN 'K' THEN double precision 'Infinity'
END
$$;

CREATE FUNCTION piece_display_ascii(character(1))
RETURNS text
LANGUAGE sql
AS $$
SELECT CASE $1 WHEN ' ' THEN '.' ELSE $1 END :: text
$$;

CREATE FUNCTION piece_display_utf8(character(1))
RETURNS text
LANGUAGE sql
AS $$
SELECT CASE $1
       WHEN ' ' THEN ' '
       WHEN 'p' THEN '♟'
       WHEN 'r' THEN '♜'
       WHEN 'n' THEN '♞'
       WHEN 'b' THEN '♝'
       WHEN 'q' THEN '♛'
       WHEN 'k' THEN '♚'
       WHEN 'P' THEN '♙'
       WHEN 'R' THEN '♖'
       WHEN 'N' THEN '♘'
       WHEN 'B' THEN '♗'
       WHEN 'Q' THEN '♕'
       WHEN 'K' THEN '♔'
       ELSE '?' END :: text
$$;

CREATE OPERATOR #
( PROCEDURE = piece_display_utf8
, RIGHTARG = character(1)
);

CREATE TYPE location AS (x int2, y int2);

CREATE TYPE move AS (x1 int2, y1 int2, x2 int2, y2 int2, ppc int2);

--
-- "ppc" is the pawn promotion choice; values 0,1,2,3 correspond
-- respectively to q,b,n,r. Its value is ignored unless the move is a
-- pawn promotion.
--

CREATE FUNCTION int_to_int_to_location
( IN x int
, IN y int
) RETURNS location
LANGUAGE SQL
AS $$
SELECT ROW($1 :: int2,$2 :: int2) :: location
$$;

CREATE OPERATOR @
( PROCEDURE = int_to_int_to_location
, leftarg = int
, rightarg = int
);

CREATE FUNCTION location_to_location_to_move
( IN a location
, IN b location
) RETURNS move
LANGUAGE SQL
AS $$
SELECT ROW($1.x,$1.y,$2.x,$2.y,0) :: move
$$;

--
-- Note: ppc is currently set to 0, that is, Queen, by default. We
-- could have added an operator which allowes changing the ppc to a
-- different piece, but the use case was not strong enough.
--

CREATE OPERATOR ->
( PROCEDURE = location_to_location_to_move
, leftarg = location
, rightarg = location
);

CREATE FUNCTION chess_x_to_letter(int2)
RETURNS text
LANGUAGE SQL
AS $$
SELECT CASE $1
WHEN 1 THEN 'a'
WHEN 2 THEN 'b'
WHEN 3 THEN 'c'
WHEN 4 THEN 'd'
WHEN 5 THEN 'e'
WHEN 6 THEN 'f'
WHEN 7 THEN 'g'
WHEN 8 THEN 'h'
ELSE '<ERROR>' END
$$;

CREATE FUNCTION chess_letter_to_x(char)
RETURNS int2
LANGUAGE SQL
AS $$
SELECT CASE $1
WHEN 'a' THEN 1
WHEN 'b' THEN 2
WHEN 'c' THEN 3
WHEN 'd' THEN 4
WHEN 'e' THEN 5
WHEN 'f' THEN 6
WHEN 'g' THEN 7
WHEN 'h' THEN 8
ELSE 0 END :: int2
$$;

CREATE FUNCTION move_to_int2
( IN m move
, OUT o int2
) LANGUAGE SQL
AS $$
SELECT CAST(($1.x1 - 1) + ($1.y1 - 1)*8 + ($1.x2 - 1)*64 + ($1.y2 - 1)*512 + $1.ppc*4096 AS int2)
$$;

CREATE FUNCTION int2_to_move
( IN i int2
, OUT o move
) LANGUAGE SQL
AS $$
SELECT ROW($1%8 + 1, ($1/8)%8 + 1, ($1/64)%8 + 1, ($1/512)%8 + 1, ($1/4096)%4) :: move
$$;

CREATE OPERATOR %%
( PROCEDURE = move_to_int2
, RIGHTARG = move
);

CREATE OPERATOR %%
( PROCEDURE = int2_to_move
, RIGHTARG = int2
);

CREATE FUNCTION move_to_text
( IN m move
, OUT o text
)LANGUAGE SQL
AS $$
SELECT
CASE
WHEN $1.x1 = $1.x2 AND $1.y1 = $1.y2
THEN CASE
     WHEN $1.x1 = 1 AND $1.y1 = 1
     THEN 'Void move'
     ELSE 'Other virtual move'
     END
ELSE	chess_x_to_letter($1.x1)
||	$1.y1 :: text
||	' -> '
||	chess_x_to_letter($1.x2)
||	$1.y2 :: text
END
$$;

CREATE OPERATOR #
( PROCEDURE = move_to_text
, RIGHTARG = move
);

CREATE TYPE game AS (board character(69), halfmove_counter int2, moves int2[]);

COMMENT ON TYPE game IS

'"moves" is encoded via the %% operators, which throughout this file
represent a compact textual encoding of a game or a move.

"board" could be computed from "moves", but only for standard games
(e.g. not for chess problems). Also, remembering "board" is efficient
and simpler.

The first 64 characters of "board" represent the chessgame locations;
the next four characters encode castling information, and the last
character is the piece captured in the last move (if any).';

CREATE FUNCTION game_display
( IN indent text
, IN g game
, OUT o text
)LANGUAGE plpgsql
AS $$
DECLARE
	i int;
	j int;
BEGIN
	o := '';
	FOR i IN REVERSE 8 .. 1 LOOP
		o := o
		|| indent;
		FOR j IN 1 .. 8 LOOP
			o := o
			|| CASE (i+j)%2 WHEN 0 THEN '[47m' ELSE '' END
			|| # substr((g).board, j + (i-1) * 8, 1)
			|| ' [m';
		END LOOP;
		o := o || ' ' || i || E'\n';
	END LOOP;
	o := o
	|| indent
	|| 'a b c d e f g h  ';
END;
$$;

CREATE FUNCTION game_display(game)
RETURNS text
LANGUAGE plpgsql
AS $BODY$
BEGIN
	RETURN game_display(' ', $1);
END;
$BODY$;

CREATE OPERATOR #
( PROCEDURE = game_display
, RIGHTARG = game
);

CREATE OPERATOR ###
( PROCEDURE = game_display
, LEFTARG = text
, RIGHTARG = game
);

CREATE FUNCTION game_display_vt100
( IN b game
, OUT o text
)LANGUAGE plpgsql
AS $$
DECLARE
	i int;
	j int;
	n int := array_length(b.moves,1);
BEGIN
	-- FEN
	o := E'[36mFEN: ' || COALESCE(%% b,'<NULL>') || E'[m\n';
	-- Board
	o := o || # b || E'\n';
	-- Moves
	o := o || E'[4;23H'
	  || CASE WHEN n IS NULL THEN 'No moves so far' ELSE 'Half moves so far:' END
	  || E'\n';
	FOR i IN 0 .. 6 LOOP
		IF i < n THEN
			o := o || '[22C' || n - i || ': ' || coalesce(# %% b.moves[n-i],'<move>') || E'\n';
		END IF;
	END LOOP;
END;
$$;

CREATE OPERATOR ##
( PROCEDURE = game_display_vt100
, RIGHTARG = game
);

--
-- Forsyth-Edwards notation
--

CREATE FUNCTION fen_to_game
( fen IN text
, g OUT game
) LANGUAGE plpgsql
IMMUTABLE STRICT
AS $BODY$
DECLARE
	a text[];
	x text;
	y text;
	i int;
BEGIN
	--
	-- TODO: regexp-based sanity check?
	--
	-- (1) piece placement
	a := regexp_split_to_array(fen, ' ');
	x := a[1];
	x := regexp_replace(x,'1',' ','g');
	x := regexp_replace(x,'2','  ','g');
	x := regexp_replace(x,'3','   ','g');
	x := regexp_replace(x,'4','    ','g');
	x := regexp_replace(x,'5','     ','g');
	x := regexp_replace(x,'6','      ','g');
	x := regexp_replace(x,'7','       ','g');
	x := regexp_replace(x,'8','        ','g');
	x := regexp_replace(x,'/','','g');
	IF length(x) != 64 THEN
		RAISE EXCEPTION 'parsing error in FEN component 1: "%" ==> "%")', a[1], x;
	END IF;
	x := substr(x,57,8)
	  || substr(x,49,8)
	  || substr(x,41,8)
	  || substr(x,33,8)
	  || substr(x,25,8)
	  || substr(x,17,8)
	  || substr(x, 9,8)
	  || substr(x, 1,8)
	  ;
	-- (2) active colour
	CASE a[2]
	WHEN 'w' THEN
		g.moves := '{}' :: int2[];
	WHEN 'b' THEN
		g.moves := '{0}' :: int2[];
	ELSE
		RAISE EXCEPTION 'parsing error in FEN component 2: "%")', a[2];
	END CASE;	
	-- (3) castling availability
	IF a[3] = '-' THEN
		x := x || 'nnnn';
	ELSE
		x := x ||
		     CASE WHEN a[3] ~ 'K' THEN 'y' ELSE 'n' END ||
		     CASE WHEN a[3] ~ 'Q' THEN 'y' ELSE 'n' END ||
		     CASE WHEN a[3] ~ 'k' THEN 'y' ELSE 'n' END ||
		     CASE WHEN a[3] ~ 'q' THEN 'y' ELSE 'n' END ;
	END IF;
	g.board := x || ' ';	
	-- (4) en-passant target square
	-- TODO
	-- (5) halfmove clock
	g.halfmove_counter := a[5] :: int2;
	-- TODO
	-- (6) fullmove number
	FOR i IN 2 .. a[6] LOOP
		g.moves := g.moves || ('{0,0}' :: int2[]);
	END LOOP;
END;
$BODY$;

CREATE OPERATOR %%
( PROCEDURE = fen_to_game
, RIGHTARG = text
);

CREATE FUNCTION game_to_fen
( g IN game
, fen OUT text
) IMMUTABLE STRICT LANGUAGE C AS
'chess', 'chess_game_to_fen';

CREATE OPERATOR %%
( PROCEDURE = game_to_fen
, RIGHTARG = game
);

--
--
--

CREATE FUNCTION parse_move
( human_move IN text
, g IN game
, o OUT move
) LANGUAGE plpgsql
AS $BODY$
DECLARE
	x int2;
	y int2;
	a text[];
BEGIN
	-- For now, we use this syntax:
	--
	--   XXpYYz
	--
	-- where XX is the starting square, YY is the ending square, p
	-- is the piece and z is an optional square where the desired
	-- promotion is specified.
	a := regexp_matches(human_move,
	     '^([a-h])([1-8])([pnbrqk])([a-h])([1-8])([nbrq])?$');
	x := chess_letter_to_x(a[1]);
	y := a[2] :: int2;
	IF a IS NULL THEN
		RAISE EXCEPTION
			'parse_move(%): syntax error', human_move;
	END IF;
	IF lower(substr((g).board, x + (y-1) * 8, 1)) != a[3] THEN
		RAISE EXCEPTION
			'parse_move(%): unexpected piece % in starting location',
			human_move,
			substr((g).board, x + (y-1) * 8, 1);
	END IF;
	o := (x @ y) -> (chess_letter_to_x(a[4]) @ (a[5] :: int2));
	IF array_upper(a,1) = 6 THEN
		o.ppc := CASE a[6]
			 WHEN 'b' THEN 1
			 WHEN 'n' THEN 2
			 WHEN 'r' THEN 3
			 ELSE 0
			 END;
	END IF;
END;
$BODY$;

--
-- the initial game
--

CREATE FUNCTION new_game
(OUT o game
) LANGUAGE plpgsql AS
$BODY$
BEGIN
	o.board :=
		'RNBQKBNR'
	||	'PPPPPPPP'
	||	'        '
	||	'        '
	||	'        '
	||	'        '
	||	'pppppppp'
	||	'rnbqkbnr'
	||	'yyyy ';
	o.halfmove_counter := 0;
	o.moves := ARRAY[] :: int2[];
END;
$BODY$;

--
-- apply a move to a game
--

CREATE FUNCTION apply_move
(IN b game
,IN m move
,OUT o game
) LANGUAGE plpgsql AS
$BODY$
--
-- Caveat: apply_move does NOT check whether the move is admissible in
-- any sense; it just applies the move as it is. Castling is detected
-- by the movement of the King; in that case the corresponding
-- movement of the Rook is performed.
--
DECLARE
	i1 int := (m).x1 + 8 * ((m).y1 - 1);
	i2 int := (m).x2 + 8 * ((m).y2 - 1);
	square1	character(1) := substr(b.board, i1, 1);
	square2	character(1) := substr(b.board, i2, 1);
BEGIN
	o.halfmove_counter := b.halfmove_counter + 1;
	IF square1 = 'P' AND (m).y1 = 7 AND (m).y2 = 8 THEN
		square1 := CASE (m).ppc
			   WHEN 0 THEN 'Q'
			   WHEN 1 THEN 'B'
			   WHEN 2 THEN 'N'
			   WHEN 3 THEN 'R'
			   END;
	END IF;
	IF square1 = 'p' AND (m).y1 = 2 AND (m).y2 = 1 THEN
		square1 := CASE (m).ppc
			   WHEN 0 THEN 'q'
			   WHEN 1 THEN 'b'
			   WHEN 2 THEN 'n'
			   WHEN 3 THEN 'r'
			   END;
	END IF;

	o.board := b.board;
	o.moves := b.moves || %% m;
	o.board := overlay(o.board placing square2 from 69 for 1);
	o.board := overlay(o.board placing square1 from i2 for 1);
	o.board := overlay(o.board placing ' ' from i1 for 1);
		
	
	CASE
	-- castling check 1
	WHEN	square1 = 'K'
	AND	(m).y1 = 1
	AND	(m).y2 = 1
	AND	(m).x1 = 5
	AND	(m).x2 = 3
	AND	substr(b.board,66,1) = 'y'
	THEN	o.board := overlay(o.board placing ' ' from 1 for 1);
		o.board := overlay(o.board placing 'R' from 4 for 1);
		o.board := overlay(o.board placing 'n' from 65 for 1);
	-- castling check 1
	WHEN	square1 = 'K'
	AND	(m).y1 = 1
	AND	(m).y2 = 1
	AND	(m).x1 = 5
	AND	(m).x2 = 7
	AND	substr(b.board,65,1) = 'y'
	THEN	o.board := overlay(o.board placing ' ' from 8 for 1);
		o.board := overlay(o.board placing 'R' from 6 for 1);
		o.board := overlay(o.board placing 'n' from 66 for 1);
	-- castling check 1
	WHEN	square1 = 'k'
	AND	(m).y1 = 8
	AND	(m).y2 = 8
	AND	(m).x1 = 5
	AND	(m).x2 = 3
	AND	substr(b.board,68,1) = 'y'
	THEN	o.board := overlay(o.board placing ' ' from 57 for 1);
		o.board := overlay(o.board placing 'r' from 60 for 1);
		o.board := overlay(o.board placing 'n' from 67 for 1);
	-- castling check 1
	WHEN	square1 = 'k'
	AND	(m).y1 = 8
	AND	(m).y2 = 8
	AND	(m).x1 = 5
	AND	(m).x2 = 7
	AND	substr(b.board,67,1) = 'y'
	THEN	o.board := overlay(o.board placing ' ' from 64 for 1);
		o.board := overlay(o.board placing 'r' from 62 for 1);
		o.board := overlay(o.board placing 'n' from 68 for 1);
	ELSE NULL;
	END CASE;
	IF square1 = 'p' OR square1 = 'P' OR square2 != ' ' THEN
		o.halfmove_counter := 0;
	END IF;
END;
$BODY$;

CREATE OPERATOR ^
( PROCEDURE = apply_move
, leftarg = game
, rightarg = move
);

CREATE FUNCTION valid_moves
( IN b game
) RETURNS SETOF move
IMMUTABLE STRICT LANGUAGE C AS
'chess', 'chess_valid_moves';

CREATE FUNCTION is_king_safe
( IN b game
) RETURNS boolean
IMMUTABLE STRICT LANGUAGE C AS
'chess', 'chess_is_king_safe';

CREATE FUNCTION is_game_ended
( IN b game
) RETURNS boolean
IMMUTABLE STRICT LANGUAGE C AS
'chess', 'chess_is_game_ended';

CREATE FUNCTION c_score
( IN b game
) RETURNS double precision
IMMUTABLE STRICT LANGUAGE C AS
'chess', 'chess_game_score';

CREATE FUNCTION score
( IN g game
, OUT o double precision
) LANGUAGE plpgsql STRICT AS $$
DECLARE
	t char;
	i int;
BEGIN
	IF is_game_ended(g) THEN
		IF is_king_safe(g) THEN
			-- stalemate
			o := double precision 'NaN';
		ELSE
			-- checkmate
			o := double precision '-Infinity';
		END IF;
	ELSE
		o := c_score(g);
	END IF;
END;
$$;

--
-- Gain 
--

CREATE FUNCTION gain
( IN g1 game
, IN g2 game
, OUT o double precision
) LANGUAGE plpgsql STRICT AS $$
BEGIN
	o := - score(g2) - score(g1);
	-- Note: we sum instead of subtracting, because of the sign
	-- change induced by swapping sides.
END;
$$;
