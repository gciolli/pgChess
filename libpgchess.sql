DROP SCHEMA IF EXISTS chess CASCADE;
CREATE SCHEMA chess;
SET search_path = chess, public;

------------------------------------------------------------
-- (*) custom data types
------------------------------------------------------------

CREATE TYPE chesspiececlass AS ENUM (
	'Pawn' , 'Knight' , 'Bishop' , 'Rook' , 'Queen' , 'King' );

------------------------------------------------------------
-- (*) moves
------------------------------------------------------------

CREATE FUNCTION chesspiece_score(
	chesspiececlass
) RETURNS real
LANGUAGE SQL
AS $BODY$
SELECT CASE
	WHEN $1 = 'Pawn' THEN 1
	WHEN $1 = 'Knight' THEN 3
	WHEN $1 = 'Bishop' THEN 3
	WHEN $1 = 'Rook' THEN 5
	WHEN $1 = 'Queen' THEN 9
	WHEN $1 = 'King' THEN 'Infinity'::real
	END
$BODY$;

------------------------------------------------------------
-- (*) display and UI
------------------------------------------------------------

-- ASCII version, using "KQRBNPkqrbnp"
CREATE FUNCTION to_char(
	v_x chesspiececlass
,	v_s boolean
) RETURNS text LANGUAGE SQL
AS $BODY$ SELECT CASE WHEN $2 THEN
	CASE
	WHEN $1 = 'King' THEN 'K'
	WHEN $1 = 'Queen' THEN 'Q'
	WHEN $1 = 'Rook' THEN 'R'
	WHEN $1 = 'Bishop' THEN 'B'
	WHEN $1 = 'Knight' THEN 'N'
	WHEN $1 = 'Pawn' THEN 'P'
	ELSE '.'
	END
ELSE
	CASE
	WHEN $1 = 'King' THEN 'k'
	WHEN $1 = 'Queen' THEN 'q'
	WHEN $1 = 'Rook' THEN 'r'
	WHEN $1 = 'Bishop' THEN 'b'
	WHEN $1 = 'Knight' THEN 'n'
	WHEN $1 = 'Pawn' THEN 'p'
	ELSE '.'
	END
END $BODY$;

-- Unicode version, using "♔♕♖♗♘♙♚♛♜♝♞♟"
CREATE OR REPLACE FUNCTION to_char(
	v_x chesspiececlass
,	v_s boolean
) RETURNS text LANGUAGE SQL
AS $BODY$ SELECT CASE WHEN $2 THEN
	CASE
	WHEN $1 = 'King' THEN '♔'
	WHEN $1 = 'Queen' THEN '♕'
	WHEN $1 = 'Rook' THEN '♖'
	WHEN $1 = 'Bishop' THEN '♗'
	WHEN $1 = 'Knight' THEN '♘'
	WHEN $1 = 'Pawn' THEN '♙'
	ELSE '.'
	END
ELSE
	CASE
	WHEN $1 = 'King' THEN '♚'
	WHEN $1 = 'Queen' THEN '♛'
	WHEN $1 = 'Rook' THEN '♜'
	WHEN $1 = 'Bishop' THEN '♝'
	WHEN $1 = 'Knight' THEN '♞'
	WHEN $1 = 'Pawn' THEN '♟'
	ELSE '.'
	END
END $BODY$;

------------------------------------------------------------
-- (*) custom data types
------------------------------------------------------------

CREATE TYPE chess_square AS ENUM (
	'White Pawn' , 'White Knight' , 'White Bishop' , 
	'White Rook' , 'White Queen' , 'White King' ,
	'Black Pawn' , 'Black Knight' , 'Black Bishop' ,
	'Black Rook' , 'Black Queen' , 'Black King' ,
	'empty');

CREATE FUNCTION side_of_chess_square(chess_square)
RETURNS bool LANGUAGE SQL AS $BODY$ SELECT CASE $1
WHEN	'White Pawn'	THEN true
WHEN	'White Knight'	THEN true
WHEN	'White Bishop'	THEN true
WHEN	'White Rook'	THEN true
WHEN	'White Queen'	THEN true
WHEN	'White King'	THEN true
WHEN	'Black Pawn'	THEN false
WHEN	'Black Knight'	THEN false
WHEN	'Black Bishop'	THEN false
WHEN	'Black Rook'	THEN false
WHEN	'Black Queen'	THEN false
WHEN	'Black King'	THEN false
END $BODY$;

CREATE FUNCTION score_of_chess_square(chess_square)
RETURNS real LANGUAGE SQL AS $BODY$ SELECT CASE $1
WHEN	'White Pawn'	THEN 1
WHEN	'White Knight'	THEN 3
WHEN	'White Bishop'	THEN 3
WHEN	'White Rook'	THEN 5
WHEN	'White Queen'	THEN 9
WHEN	'White King'	THEN 'Infinity'::real
WHEN	'Black Pawn'	THEN 1
WHEN	'Black Knight'	THEN 3
WHEN	'Black Bishop'	THEN 3
WHEN	'Black Rook'	THEN 5
WHEN	'Black Queen'	THEN 9
WHEN	'Black King'	THEN 'Infinity'::real
ELSE	0
END $BODY$;

CREATE DOMAIN chessint AS int
	CHECK (VALUE BETWEEN 1 AND 8);

CREATE TYPE gamemove AS (
	dscore	real
,	x1	chessint
,	y1	chessint
,	x2	chessint
,	y2	chessint
);

CREATE TYPE gamestate AS (
	score		real
,	moves		gamemove[]
,	board		chess_square[]
--,	under_attack	boolean[]
);

------------------------------------------------------------
-- (*) Implementing games and moves
------------------------------------------------------------

CREATE FUNCTION starting_gamestate()
RETURNS gamestate LANGUAGE plpgsql AS $BODY$
DECLARE
	v_g	gamestate;
BEGIN
	v_g.score := 0;
	v_g.board := CAST('{
{White Rook  ,White Pawn,empty,empty,empty,empty,Black Pawn,Black Rook  },
{White Knight,White Pawn,empty,empty,empty,empty,Black Pawn,Black Knight},
{White Bishop,White Pawn,empty,empty,empty,empty,Black Pawn,Black Bishop},
{White Queen ,White Pawn,empty,empty,empty,empty,Black Pawn,Black Queen },
{White King  ,White Pawn,empty,empty,empty,empty,Black Pawn,Black King  },
{White Bishop,White Pawn,empty,empty,empty,empty,Black Pawn,Black Bishop},
{White Knight,White Pawn,empty,empty,empty,empty,Black Pawn,Black Knight},
{White Rook  ,White Pawn,empty,empty,empty,empty,Black Pawn,Black Rook  }
		}' AS chess_square[]);
	v_g.moves := CAST(ARRAY[] AS gamemove[]);
	RETURN v_g;
END
$BODY$;

CREATE FUNCTION is_king_under_attack(
	g	gamestate
) RETURNS boolean LANGUAGE plpgsql AS $BODY$
DECLARE
	their_side	boolean;
	our_king	chess_square;
BEGIN
	IF COALESCE(array_upper((g).moves,1),0) % 2 = 1 THEN
		their_side := false;
		our_king := 'White King';
	ELSE
		their_side := true;
		our_king := 'Black King';
	END IF;
	PERFORM m.*
		FROM prevalid_moves(g,their_side) m
		WHERE g.board[m.x2][m.y2] = our_king
		LIMIT 1;
	IF FOUND THEN
		RETURN true;
	END IF;
	RETURN false;
END;
$BODY$;

CREATE FUNCTION chesspiece_moves(
	g	gamestate
,	x	int
,	y	int
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
DECLARE
	s chess_square := g.board[x][y];
	m gamemove;
	dx int;
	dy int;
	v_turn int;
	side boolean;
	boardside boolean[] := array_fill(NULL::boolean,ARRAY[8,8]);
BEGIN
	m.x1 := x;
	m.y1 := y;
--	RAISE DEBUG 'm.x1,m.y1 = %,% while x,y = %,%',m.x1,m.y1,x,y;
	-- (1) compiling boardside[]
	v_turn := COALESCE(array_upper((g).moves,1),0);
	IF v_turn % 2 = 0 THEN
		side := true;
	ELSE
		side := false;
	END IF;
	RAISE DEBUG 'v_turn = % ; side = %',v_turn,side;
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		boardside[x][y] := side_of_chess_square(g.board[x][y]);
	END LOOP;
	END LOOP;
	-- (2) scanning all the pieces
	IF s = 'Black Queen' OR  s = 'White Queen' THEN
		RAISE DEBUG 'Qq';
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,-1),(-1,1) LOOP
			m.x2 := m.x1;
			m.y2 := m.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				m.x2 := CASE WHEN m.x2 + dx BETWEEN 1 AND 8 THEN m.x2 + dx ELSE NULL END;
				m.y2 := CASE WHEN m.y2 + dy BETWEEN 1 AND 8 THEN m.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN m.x2 IS NULL OR m.y2 IS NULL;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = side;
				m.dscore := score_of_chess_square((g).board[m.x2][m.y2]);
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Rook' OR  s = 'White Rook' THEN
		RAISE DEBUG 'Rr';
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0) LOOP
			m.x2 := m.x1;
			m.y2 := m.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				m.x2 := CASE WHEN m.x2 + dx BETWEEN 1 AND 8 THEN m.x2 + dx ELSE NULL END;
				m.y2 := CASE WHEN m.y2 + dy BETWEEN 1 AND 8 THEN m.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN m.x2 IS NULL OR m.y2 IS NULL;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = side;
				m.dscore := score_of_chess_square((g).board[m.x2][m.y2]);
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Bishop' OR  s = 'White Bishop' THEN
		RAISE DEBUG 'Bb';
		FOR dx,dy IN VALUES (1,1),(1,-1),(-1,-1),(-1,1) LOOP
			m.x2 := m.x1;
			m.y2 := m.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				m.x2 := CASE WHEN m.x2 + dx BETWEEN 1 AND 8 THEN m.x2 + dx ELSE NULL END;
				m.y2 := CASE WHEN m.y2 + dy BETWEEN 1 AND 8 THEN m.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN m.x2 IS NULL OR m.y2 IS NULL;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = side;
				m.dscore := score_of_chess_square((g).board[m.x2][m.y2]);
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Knight' OR  s = 'White Knight' THEN
		RAISE DEBUG 'Nn';
		FOR dx,dy IN VALUES (1,2),(1,-2),(-1,-2),(-1,2),(2,1),(2,-1),(-2,-1),(-2,1) LOOP
			m.x2 := m.x1;
			m.y2 := m.y1;
			<<loop1>>
			FOR r IN 1 .. 1 LOOP
				m.x2 := CASE WHEN m.x2 + dx BETWEEN 1 AND 8 THEN m.x2 + dx ELSE NULL END;
				m.y2 := CASE WHEN m.y2 + dy BETWEEN 1 AND 8 THEN m.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN m.x2 IS NULL OR m.y2 IS NULL;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = side;
				m.dscore := score_of_chess_square((g).board[m.x2][m.y2]);
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black King' OR  s = 'White King' THEN
		RAISE DEBUG 'Kk';
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,-1),(-1,1) LOOP
			m.x2 := m.x1;
			m.y2 := m.y1;
			<<loop1>>
			FOR r IN 1 .. 1 LOOP
				m.x2 := CASE WHEN m.x2 + dx BETWEEN 1 AND 8 THEN m.x2 + dx ELSE NULL END;
				m.y2 := CASE WHEN m.y2 + dy BETWEEN 1 AND 8 THEN m.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN m.x2 IS NULL OR m.y2 IS NULL;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = side;
				m.dscore := score_of_chess_square((g).board[m.x2][m.y2]);
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[m.x2][m.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Pawn' THEN
		RAISE DEBUG 'P';
		-- moving forward by 1
		IF boardside[x][y-1] IS NULL THEN
			m.x2 := m.x1;
			m.y2 := m.y1 - 1;
			m.dscore := CASE WHEN m.y2 = 1 THEN 9 ELSE 0 END;
			RETURN NEXT m;
			RAISE DEBUG E'cm1 (%,%) -> (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
		-- moving forward by 2
		IF y = 7 AND boardside[x][y-1] IS NULL 
			 AND boardside[x][y-2] IS NULL THEN
			m.x2 := m.x1;
			m.y2 := m.y1 - 2;
			m.dscore := 0;
			RETURN NEXT m;
			RAISE DEBUG E'cm2 (%,%) -> (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
		-- capturing left
		IF x > 1 AND boardside[x-1][y-1] = NOT side THEN
			m.x2 := m.x1 - 1;
			m.y2 := m.y1 - 1;
			RAISE DEBUG '% @ (%,%) captures % @ (%,%) on the left',
				(g).board[x][y],x,y,
				(g).board[m.x2][m.y2],m.x2,m.y2;
			m.dscore := 
				score_of_chess_square((g).board[m.x2][m.y2])
				+ CASE WHEN m.y2 = 1 THEN 9 ELSE 0 END;
			RETURN NEXT m;
			RAISE DEBUG E'cml (%,%) -< (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
		-- capturing right
		IF x < 8 AND boardside[x+1][y-1] = NOT side THEN
			m.x2 := m.x1 + 1;
			m.y2 := m.y1 - 1;
			RAISE DEBUG '% @ (%,%) captures % @ (%,%) on the right',
				(g).board[x][y],x,y,
				(g).board[m.x2][m.y2],m.x2,m.y2;
			m.dscore := 
				score_of_chess_square((g).board[m.x2][m.y2])
				+ CASE WHEN m.y2 = 1 THEN 9 ELSE 0 END;
			RETURN NEXT m;
			RAISE DEBUG E'cmr (%,%) -< (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
	ELSIF s = 'White Pawn' THEN
		RAISE DEBUG 'p';
		-- moving forward by 1
		IF boardside[x][y+1] IS NULL THEN
			m.x2 := m.x1;
			m.y2 := m.y1 + 1;
			m.dscore := CASE WHEN m.y2 = 8 THEN 9 ELSE 0 END;
			RETURN NEXT m;
			RAISE DEBUG E'cm3 (%,%) -> (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
		-- moving forward by 2
		IF y = 7 AND boardside[x][y+1] IS NULL 
			 AND boardside[x][y+2] IS NULL THEN
			m.x2 := m.x1;
			m.y2 := m.y1 + 2;
			m.dscore := 0;
			RETURN NEXT m;
			RAISE DEBUG E'cm4 (%,%) -> (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
		-- capturing left
		IF x > 1 AND boardside[x-1][y+1] = NOT side THEN
			m.x2 := m.x1 - 1;
			m.y2 := m.y1 + 1;
			RAISE DEBUG '% @ (%,%) captures % @ (%,%) on the left',
				(g).board[x][y],x,y,
				(g).board[m.x2][m.y2],m.x2,m.y2;
			m.dscore := 
				score_of_chess_square((g).board[m.x2][m.y2])
				+ CASE WHEN m.y2 = 8 THEN 9 ELSE 0 END;
			RETURN NEXT m;
			RAISE DEBUG E'cml (%,%) -< (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
		-- capturing right
		IF x < 8 AND boardside[x+1][y+1] = NOT side THEN
			m.x2 := m.x1 + 1;
			m.y2 := m.y1 + 1;
			RAISE DEBUG '% @ (%,%) captures % @ (%,%) on the right',
				(g).board[x][y],x,y,
				(g).board[m.x2][m.y2],m.x2,m.y2;
			m.dscore := 
				score_of_chess_square((g).board[m.x2][m.y2])
				+ CASE WHEN m.y2 = 8 THEN 9 ELSE 0 END;
			RETURN NEXT m;
			RAISE DEBUG E'cmr (%,%) -< (%,%)\n[score %]',m.x1,m.y1,m.x2,m.y2,m.dscore;
		END IF;
	ELSE
		RAISE EXCEPTION 'unsupported chess_square %',s;
	END IF;
END;
$BODY$;

CREATE FUNCTION prevalid_moves (
	v_g	gamestate
,	side	boolean
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
DECLARE
	x chessint;
	y chessint;
	dx int;
	dy int;
	z int;
	m gamemove;
	n int;
	boardside boolean[] := array_fill(NULL::boolean,ARRAY[8,8]);
	v_turn int;
	t1     timestamp;
BEGIN
	t1 := clock_timestamp();
	z := COALESCE(array_upper((v_g).moves,1),0);
	IF z < 3 THEN
		RAISE DEBUG 'prevalid_moves BEGIN #%',z;
	END IF;
	RAISE DEBUG 'prevalid_moves -- (1) compiling boardside[] dt = %',
		clock_timestamp() - t1;
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		boardside[x][y] := side_of_chess_square(v_g.board[x][y]);
	END LOOP;
	END LOOP;
	RAISE DEBUG 'prevalid_moves -- (2) scanning all the pieces dt = %',
		clock_timestamp() - t1;
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		IF boardside[x][y] = side THEN
--			RAISE DEBUG 'prevalid_moves considering (%,%) = %'
--				,x,y,(v_g).board[x][y];
			RETURN QUERY
				SELECT *
				FROM chesspiece_moves(v_g,x,y);
		END IF;
	END LOOP;
	END LOOP;
	IF z < 3 THEN
		RAISE DEBUG 'prevalid_moves END dt = %',
			clock_timestamp() - t1;
	END IF;
END;
$BODY$;

CREATE FUNCTION valid_moves (
	v_g	gamestate
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
DECLARE
	side boolean;
BEGIN
	IF COALESCE(array_upper((v_g).moves,1),0) % 2 = 0 THEN
		side := true;
	ELSE
		side := false;
	END IF;
	RETURN QUERY
		SELECT m1.*
		FROM prevalid_moves(v_g,side) m1
		WHERE NOT is_king_under_attack(apply_move(v_g,m1.*));
		-- FIXME
END;
$BODY$;

CREATE FUNCTION apply_move(
	v_g gamestate
,	v_m gamemove
) RETURNS gamestate
LANGUAGE plpgsql
AS $BODY$
DECLARE
	this_side boolean := side_of_chess_square(v_g.board[v_m.x1][v_m.y1]);
BEGIN
	RAISE DEBUG 'apply_move BEGIN %',clock_timestamp();
	RAISE DEBUG 'apply_move #% % : % (%,%) -> (%,%)',
		COALESCE(array_upper((v_g).moves,1),0),
		v_g.board[v_m.x1][v_m.y1],
		v_m.dscore,v_m.x1,v_m.y1,v_m.x2,v_m.y2;
	-- (1) apply the move
	v_g.board[v_m.x2][v_m.y2] := (v_g).board[v_m.x1][v_m.y1];
	-- (2) promote Pawns to Queens
	IF v_g.board[v_m.x2][v_m.y2] = 'Black Pawn' AND v_m.y2 = 1 THEN
		v_g.board[v_m.x2][v_m.y2] := 'Black Queen';
	END IF;
	IF v_g.board[v_m.x2][v_m.y2] = 'White Pawn' AND v_m.y2 = 8 THEN
		v_g.board[v_m.x2][v_m.y2] := 'White Queen';
	END IF;
--?	-- (3) refresh the under_attack grid, for the convenience of
--?	-- the next player
--?	FOR x IN 1 .. 8 LOOP
--?	FOR y IN 1 .. 8 LOOP
--?		IF side_of_chess_square(v_g.board[x][y]) = this_side THEN
--?			RAISE DEBUG '% @ (%,%) is now attacking',
--?				v_g.board[x][y],x,y;
--?			
--?		END IF;
--?	END LOOP;
--?	END LOOP;
	-- (4) empty the old position
	v_g.board[v_m.x1][v_m.y1] := NULL;
	-- (5) remember the move
	v_g.moves := v_g.moves || v_m;
	RAISE DEBUG 'apply_move => %',display(v_g);
	RETURN v_g;
END;
$BODY$;

-- Unicode version, using "♔♕♖♗♘♙♚♛♜♝♞♟"
CREATE OR REPLACE FUNCTION to_char(
	v_x chess_square
) RETURNS text LANGUAGE SQL
AS $BODY$ SELECT CASE $1
	WHEN 'White King' THEN '♔'
	WHEN 'White Queen' THEN '♕'
	WHEN 'White Rook' THEN '♖'
	WHEN 'White Bishop' THEN '♗'
	WHEN 'White Knight' THEN '♘'
	WHEN 'White Pawn' THEN '♙'
	WHEN 'Black King' THEN '♚'
	WHEN 'Black Queen' THEN '♛'
	WHEN 'Black Rook' THEN '♜'
	WHEN 'Black Bishop' THEN '♝'
	WHEN 'Black Knight' THEN '♞'
	WHEN 'Black Pawn' THEN '♟'
	ELSE '.'
END $BODY$;

CREATE FUNCTION display (
	v_g gamestate
) RETURNS text
LANGUAGE plpgsql AS $BODY$
DECLARE
	x chessint;
	y chessint;
	t text DEFAULT '	';
	v_turn int;
BEGIN
	v_turn := COALESCE(array_upper((v_g).moves,1),0);
	IF v_turn % 2 = 0 THEN
		t := t || 'White';
	ELSE
		t := t || 'Black';
	END IF;
	t := t || ' - move ' || v_turn || E' \n\n	';
	FOR y IN REVERSE 8 .. 1 LOOP
	FOR x IN 1 .. 8 LOOP
		t := t || to_char(v_g.board[x][y]) ||
			CASE WHEN x = 8 THEN E' \n	' ELSE ' ' END;
	END LOOP;
	END LOOP;
	RETURN t;
END;
$BODY$;

------------------------------------------------------------
-- (*) generic pg2podg library
------------------------------------------------------------

\i libpg2podg.sql
