--SET work_mem = 64;
--SET temp_buffers = 100;
SET synchronous_commit = off;
SET client_min_messages = WARNING;

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
	piece_class	chesspiececlass
,	piece_side	boolean
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
	piece_class	chesspiececlass
,	piece_side	boolean
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
	CHECK (VALUE BETWEEN 1 AND 8)
;

CREATE TYPE d_chess_square AS (
	x1	chessint
,	y1	chessint
,	x2	chessint
,	y2	chessint
);

CREATE TYPE prevalidmove AS (
	d_score	real
,	mine	d_chess_square
);

CREATE TYPE gamemove AS (
	d_score	real
,	mine	d_chess_square
,	next	prevalidmove[]
);

CREATE FUNCTION prevalidmove_as_gamemove (
	p prevalidmove
) RETURNS gamemove
LANGUAGE plpgsql
AS $BODY$
DECLARE
	m gamemove;
BEGIN
	m.d_score := p.d_score;
	m.mine := p.mine;
	m.next := NULL;
	RETURN m;
END;
$BODY$;

COMMENT ON TYPE prevalidmove IS 'Recursive types are not allowed, so
we had to implement a separate type "prevalidmove", in order to endow
a gamemove with a list "next" of prevalid gamemoves. We embed the
prevalidmove type as a gamemove where next is NULL via the function
prevalidmove_as_gamemove. Its name is long but unambiguous, to reflect
the author''s preference for strong typing practices.';

CREATE TYPE gamestate AS (
	score	real
,	moves	gamemove[]
,	board	chess_square[]
,	next	prevalidmove[]
,	side_next boolean
);

COMMENT ON TYPE gamestate IS 'A gamestate has the property that next
IS NOT NULL, because it has been obtained by applying a valid move,
which carries the "next" prevalid moves which have been computed to
check its own validity.';

------------------------------------------------------------
-- (*) Implementing games and moves
------------------------------------------------------------

CREATE FUNCTION starting_gamestate()
RETURNS gamestate LANGUAGE plpgsql AS $BODY$
DECLARE
	g	gamestate;
BEGIN
	g.score := 0;
	g.board := CAST('{
{White Rook  ,White Pawn,empty,empty,empty,empty,Black Pawn,Black Rook  },
{White Knight,White Pawn,empty,empty,empty,empty,Black Pawn,Black Knight},
{White Bishop,White Pawn,empty,empty,empty,empty,Black Pawn,Black Bishop},
{White Queen ,White Pawn,empty,empty,empty,empty,Black Pawn,Black Queen },
{White King  ,White Pawn,empty,empty,empty,empty,Black Pawn,Black King  },
{White Bishop,White Pawn,empty,empty,empty,empty,Black Pawn,Black Bishop},
{White Knight,White Pawn,empty,empty,empty,empty,Black Pawn,Black Knight},
{White Rook  ,White Pawn,empty,empty,empty,empty,Black Pawn,Black Rook  }
		}' AS chess_square[]);
	g.moves := CAST(ARRAY[] AS gamemove[]);
	g.side_next := true;
	SELECT array_agg(pm.*)
		INTO g.next
		FROM prevalid_moves(g) pm;
	RETURN g;
END
$BODY$;

CREATE FUNCTION is_king_under_attack(
	g		gamestate
) RETURNS boolean LANGUAGE plpgsql AS $BODY$
DECLARE
	our_king	chess_square := CASE WHEN g.side_next THEN 'Black King' ELSE 'White King' END;
	i		int;
BEGIN
	FOR i IN 1 .. array_upper(g.next,1) LOOP
		IF (g).board[(g).next[i].mine.x2][(g).next[i].mine.y2] = our_king THEN
			RETURN true;
		END IF;
	END LOOP;
	RETURN false;
END;
$BODY$;

CREATE FUNCTION chesspiece_moves(
	g		gamestate
,	x		int
,	y		int
,	boardside	boolean[]
) RETURNS SETOF prevalidmove
LANGUAGE plpgsql AS $BODY$
DECLARE
	s chess_square := g.board[x][y];
	m prevalidmove;
	dz d_chess_square;
	dx int;
	dy int;
BEGIN
	dz.x1 := x;
	dz.y1 := y;
	-- (1) scanning all the pieces
	IF s = 'Black Queen' OR  s = 'White Queen' THEN
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,-1),(-1,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = g.side_next;
				m.d_score := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT g.side_next;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Rook' OR  s = 'White Rook' THEN
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = g.side_next;
				m.d_score := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT g.side_next;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Bishop' OR  s = 'White Bishop' THEN
		FOR dx,dy IN VALUES (1,1),(1,-1),(-1,-1),(-1,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = g.side_next;
				m.d_score := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT g.side_next;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Knight' OR  s = 'White Knight' THEN
		FOR dx,dy IN VALUES (1,2),(1,-2),(-1,-2),(-1,2),(2,1),(2,-1),(-2,-1),(-2,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 1 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = g.side_next;
				m.d_score := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT g.side_next;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black King' OR  s = 'White King' THEN
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,-1),(-1,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 1 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = g.side_next;
				m.d_score := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT g.side_next;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Pawn' THEN
		-- moving forward by 1
		IF boardside[x][y-1] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 - 1;
			m.d_score := 0.1 + CASE WHEN dz.y2 = 1 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
		-- moving forward by 2
		IF y = 7 AND boardside[x][y-1] IS NULL 
			 AND boardside[x][y-2] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 - 2;
			m.d_score := 0.2 ;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
		-- capturing left
		IF x > 1 AND boardside[x-1][y-1] = NOT g.side_next THEN
			dz.x2 := dz.x1 - 1;
			dz.y2 := dz.y1 - 1;
			m.d_score := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ 0.1 + CASE WHEN dz.y2 = 1 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
		-- capturing right
		IF x < 8 AND boardside[x+1][y-1] = NOT g.side_next THEN
			dz.x2 := dz.x1 + 1;
			dz.y2 := dz.y1 - 1;
			m.d_score := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ 0.1 + CASE WHEN dz.y2 = 1 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
	ELSIF s = 'White Pawn' THEN
		-- moving forward by 1
		IF boardside[x][y+1] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 + 1;
			m.d_score := 0.1 + CASE WHEN dz.y2 = 8 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
		-- moving forward by 2
		IF y = 2 AND boardside[x][y+1] IS NULL 
			 AND boardside[x][y+2] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 + 2;
			m.d_score := 0.2;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
		-- capturing left
		IF x > 1 AND boardside[x-1][y+1] = NOT g.side_next THEN
			dz.x2 := dz.x1 - 1;
			dz.y2 := dz.y1 + 1;
			m.d_score := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ 0.1 + CASE WHEN dz.y2 = 8 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
		-- capturing right
		IF x < 8 AND boardside[x+1][y+1] = NOT g.side_next THEN
			dz.x2 := dz.x1 + 1;
			dz.y2 := dz.y1 + 1;
			m.d_score := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ 0.1 + CASE WHEN dz.y2 = 8 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
		END IF;
	ELSE
		RAISE EXCEPTION 'unsupported chess_square %',s;
	END IF;
END;
$BODY$;

CREATE FUNCTION prevalid_moves (
	g	gamestate
) RETURNS SETOF prevalidmove
LANGUAGE plpgsql AS $BODY$
-- This function produces the set of prevalid moves starting from
-- configuration g.
DECLARE
	x chessint;
	y chessint;
	boardside boolean[] := array_fill(NULL::boolean,ARRAY[8,8]);
BEGIN
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		boardside[x][y] := side_of_chess_square(g.board[x][y]);
	END LOOP;
	END LOOP;
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		IF boardside[x][y] = g.side_next THEN
			RETURN QUERY
				SELECT *
				FROM chesspiece_moves(g,x,y,boardside);
		END IF;
	END LOOP;
	END LOOP;
END;
$BODY$;

CREATE FUNCTION valid_moves (
	g	gamestate
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
-- This function produces the set of valid moves starting from
-- configuration g. This is obtained by (a) taking the list all the
-- prevalid moves, which is available as g.next, (b) endowing each
-- prevalid move with the list of possible "answers", and finally (c)
-- using the information in (b) to select only those moves that do not
-- leave the King under attack.
DECLARE
	rec	record;
	m	gamemove;
	g1	gamestate;
BEGIN
	-- (*) Assertion
	IF g.next IS NULL THEN
		RAISE EXCEPTION 'E1';
	END IF;
	-- (*) Filter next_moves
	FOR i IN 1 .. array_upper((g).next,1) LOOP
		m := prevalidmove_as_gamemove((g).next[i]);
		g1 := apply_move(g,m);
		-- Consider the move only if it doesn't leave own King
		-- under attack
		IF NOT is_king_under_attack(g1) THEN
			-- Copy from g1 the list of next moves, that
			-- has been computed by the previous
			-- statement.
			m.next := g1.next;
			RETURN NEXT m;
		END IF;
	END LOOP;
END;
$BODY$;

CREATE FUNCTION apply_move(
	g gamestate
,	m gamemove
) RETURNS gamestate
LANGUAGE plpgsql
AS $BODY$
BEGIN
	-- (0) can't capture the King!
	IF g.board[(m).mine.x2][(m).mine.y2] = 'White King'
	OR g.board[(m).mine.x2][(m).mine.y2] = 'Black King' THEN
		RAISE EXCEPTION 'Tried to capture % @ %,%',
			g.board[(m).mine.x2][(m).mine.y2],
			(m).mine.x2,(m).mine.y2;
	END IF;
	-- (1) apply the move
	g.board[(m).mine.x2][(m).mine.y2] := 
		(g).board[(m).mine.x1][(m).mine.y1];
	-- (2) promote Pawns to Queens
	IF g.board[(m).mine.x2][(m).mine.y2] = 'Black Pawn'
	AND (m).mine.y2 = 1 THEN
		g.board[(m).mine.x2][(m).mine.y2] := 'Black Queen';
	END IF;
	IF g.board[(m).mine.x2][(m).mine.y2] = 'White Pawn'
	AND (m).mine.y2 = 8 THEN
		g.board[(m).mine.x2][(m).mine.y2] := 'White Queen';
	END IF;
	-- (3) vacate the starting position
	g.board[(m).mine.x1][(m).mine.y1] := 'empty';
	-- (4) remember the move
	g.moves := g.moves || m;
	-- (5) now the other side plays
	g.side_next := NOT g.side_next;
	-- (6) compute the possible answers
	SELECT array_agg(pm.*)
		INTO g.next
		FROM prevalid_moves(g) pm;
	RETURN g;
END;
$BODY$;

-- Unicode version, using "♔♕♖♗♘♙♚♛♜♝♞♟"
CREATE OR REPLACE FUNCTION to_char(
	chess_square
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
	g gamestate
) RETURNS text
LANGUAGE plpgsql AS $BODY$
DECLARE
	x chessint;
	y chessint;
	t text DEFAULT ' ';
	turn int;
BEGIN
	turn := 1 + COALESCE(array_upper((g).moves,1),0);
	IF turn % 2 = 1 THEN
		t := t || 'White';
	ELSE
		t := t || 'Black';
	END IF;
	t := t || ' - move ' || turn || E' \n\n';
	FOR y IN REVERSE 8 .. 1 LOOP
		t := t || to_char(y,'9') || ' ';
	FOR x IN 1 .. 8 LOOP
		t := t || to_char(g.board[x][y]) ||
			CASE WHEN x = 8 THEN E' \n' ELSE ' ' END;
	END LOOP;
	END LOOP;
	t := t || '   a b c d e f g h';
	RETURN t;
END;
$BODY$;

CREATE FUNCTION ui_parse_user_move (
	x text
) RETURNS boolean
LANGUAGE plpgsql AS $BODY$
DECLARE
	a		text[];
	m		gamemove;
BEGIN
	a := regexp_matches(x,'^([a-h])([1-8])([PRBNQK])([a-h])([1-8])$');
	IF a IS NULL THEN
		RAISE EXCEPTION 'syntax error in move "%"',x;
	END IF;
	m.mine := ROW(CAST(translate(a[1],'abcdefgh','12345678') AS int)
		  ,   a[2]
		  ,   CAST(translate(a[4],'abcdefgh','12345678') AS int)
		  ,   a[5]);
	-- TODO: check whether the move is valid (illegal moves are
	-- quite useful for debugging :-)
	TRUNCATE my_moves;
	INSERT INTO my_moves(current_game,this_move,move_level,score)
		SELECT	a.game
		,	m
		,	0
		,	(a.game).score
		FROM (
		SELECT game
		FROM my_states) a;
	TRUNCATE my_states;
	INSERT INTO my_states(game)
	SELECT apply_move(current_game, this_move)
	FROM (SELECT * FROM my_moves
	WHERE parent IS NULL
	ORDER BY score DESC
	LIMIT 1) x;
	RETURN found;
END;
$BODY$;

------------------------------------------------------------
-- (*) generic pg2podg library
------------------------------------------------------------

\i libpg2podg.sql
