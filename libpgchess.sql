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
--	CHECK (VALUE BETWEEN 1 AND 8)
;

CREATE TYPE d_chess_square AS (
	x1	chessint
,	y1	chessint
,	x2	chessint
,	y2	chessint
);

CREATE TYPE gamemove AS (
	dscore	real
,	mine	d_chess_square
--,	theirs	d_chess_square[]
);

CREATE TYPE gamestate AS (
	score		real
,	moves		gamemove[]
,	board		chess_square[]
,	next_moves	gamemove[]
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
	g		gamestate
,	our_side	boolean
) RETURNS boolean LANGUAGE plpgsql AS $BODY$
DECLARE
	procname	text := 'ikua';
--	their_side	boolean;
--??	our_king	chess_square;
	our_king	chess_square := CASE WHEN our_side = true THEN 'White King' ELSE 'Black King' END;
	i		int;
BEGIN
--	IF COALESCE(array_upper((g).moves,1),0) % 2 = 1 THEN
--		their_side := false;
--		our_king := 'White King';
--	ELSE
--		their_side := true;
--		our_king := 'Black King';
--	END IF;
--??	IF our_side = true THEN
--??		our_king := 'White King';
--??	ELSE
--??		our_king := 'Black King';
--??	END IF;
--?	RAISE DEBUG '[%] g = %',procname,g;
--?	IF (g).next_moves IS NULL THEN
--?		RAISE EXCEPTION '[%] g.next_moves IS NULL',procname;
--?	ELSE
--?		RAISE DEBUG '[%] g.next_moves = %',procname,g.next_moves;
--?	END IF;
	FOR i IN 1 .. array_upper(g.next_moves,1) LOOP
		IF (g).board[(g).next_moves[i].mine.x2][(g).next_moves[i].mine.y2] = our_king THEN
--			RAISE DEBUG '[%] => TRUE',procname;
			RETURN true;
		END IF;
	END LOOP;
--	RAISE DEBUG '[%] => FALSE',procname;
	RETURN false;
END;
$BODY$;

CREATE FUNCTION chesspiece_moves(
	g		gamestate
,	x		int
,	y		int
,	side		boolean
,	boardside	boolean[]
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
DECLARE
	procname text := 'cpm';
	s chess_square := g.board[x][y];
	m gamemove;
	dz d_chess_square;
	dx int;
	dy int;
	v_turn int;
--	side boolean;
--	boardside boolean[] := array_fill(NULL::boolean,ARRAY[8,8]);
BEGIN
	dz.x1 := x;
	dz.y1 := y;
--	RAISE DEBUG '[%] dz.x1,dz.y1 = %,% while x,y = %,%',procname,dz.x1,dz.y1,x,y;
	-- (1) compiling boardside[]
--?	v_turn := COALESCE(array_upper((g).moves,1),0);
--?	IF v_turn % 2 = 0 THEN
--?		side := true;
--?	ELSE
--?		side := false;
--?	END IF;
--	RAISE DEBUG '[%] v_turn = % ; side = %',procname,v_turn,side;
--?		FOR x IN 1 .. 8 LOOP
--?		FOR y IN 1 .. 8 LOOP
--?			boardside[x][y] := side_of_chess_square(g.board[x][y]);
--?		END LOOP;
--?		END LOOP;
	-- (2) scanning all the pieces
	IF s = 'Black Queen' OR  s = 'White Queen' THEN
--		RAISE DEBUG '[%] Qq',procname;
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,-1),(-1,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = side;
				m.dscore := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Rook' OR  s = 'White Rook' THEN
--		RAISE DEBUG '[%] Rr',procname;
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = side;
				m.dscore := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Bishop' OR  s = 'White Bishop' THEN
--		RAISE DEBUG '[%] Bb',procname;
		FOR dx,dy IN VALUES (1,1),(1,-1),(-1,-1),(-1,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 7 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = side;
				m.dscore := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Knight' OR  s = 'White Knight' THEN
--		RAISE DEBUG '[%] Nn',procname;
		FOR dx,dy IN VALUES (1,2),(1,-2),(-1,-2),(-1,2),(2,1),(2,-1),(-2,-1),(-2,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 1 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = side;
				m.dscore := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black King' OR  s = 'White King' THEN
--		RAISE DEBUG '[%] Kk',procname;
		FOR dx,dy IN VALUES (0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,-1),(-1,1) LOOP
			dz.x2 := dz.x1;
			dz.y2 := dz.y1;
			<<loop1>>
			FOR r IN 1 .. 1 LOOP
				dz.x2 := CASE WHEN dz.x2 + dx BETWEEN 1 AND 8 THEN dz.x2 + dx ELSE NULL END;
				dz.y2 := CASE WHEN dz.y2 + dy BETWEEN 1 AND 8 THEN dz.y2 + dy ELSE NULL END;
				EXIT loop1 WHEN dz.x2 IS NULL OR dz.y2 IS NULL;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = side;
				m.dscore := score_of_chess_square((g).board[dz.x2][dz.y2]);
				m.mine := dz;
				RETURN NEXT m;
				EXIT loop1 WHEN boardside[dz.x2][dz.y2] = NOT side;
			END LOOP;
		END LOOP;
	ELSIF s = 'Black Pawn' THEN
--		RAISE DEBUG '[%] P',procname;
		-- moving forward by 1
		IF boardside[x][y-1] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 - 1;
			m.dscore := CASE WHEN dz.y2 = 1 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cm1 (%,%) -> (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
		-- moving forward by 2
		IF y = 7 AND boardside[x][y-1] IS NULL 
			 AND boardside[x][y-2] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 - 2;
			m.dscore := 0;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cm2 (%,%) -> (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
		-- capturing left
		IF x > 1 AND boardside[x-1][y-1] = NOT side THEN
			dz.x2 := dz.x1 - 1;
			dz.y2 := dz.y1 - 1;
--			RAISE DEBUG '[%] % @ (%,%) captures % @ (%,%) on the left',procname,
--				(g).board[x][y],x,y,
--				(g).board[dz.x2][dz.y2],dz.x2,dz.y2;
			m.dscore := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ CASE WHEN dz.y2 = 1 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cml (%,%) -< (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
		-- capturing right
		IF x < 8 AND boardside[x+1][y-1] = NOT side THEN
			dz.x2 := dz.x1 + 1;
			dz.y2 := dz.y1 - 1;
--			RAISE DEBUG '[%] % @ (%,%) captures % @ (%,%) on the right',procname,
--				(g).board[x][y],x,y,
--				(g).board[dz.x2][dz.y2],dz.x2,dz.y2;
			m.dscore := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ CASE WHEN dz.y2 = 1 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cmr (%,%) -< (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
	ELSIF s = 'White Pawn' THEN
		RAISE DEBUG '[%] p',procname;
		-- moving forward by 1
		IF boardside[x][y+1] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 + 1;
			m.dscore := CASE WHEN dz.y2 = 8 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cm3 (%,%) -> (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
		-- moving forward by 2
		IF y = 2 AND boardside[x][y+1] IS NULL 
			 AND boardside[x][y+2] IS NULL THEN
			dz.x2 := dz.x1;
			dz.y2 := dz.y1 + 2;
			m.dscore := 0;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cm4 (%,%) -> (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
		-- capturing left
		IF x > 1 AND boardside[x-1][y+1] = NOT side THEN
			dz.x2 := dz.x1 - 1;
			dz.y2 := dz.y1 + 1;
--			RAISE DEBUG '[%] % @ (%,%) captures % @ (%,%) on the left',procname,
--				(g).board[x][y],x,y,
--				(g).board[dz.x2][dz.y2],dz.x2,dz.y2;
			m.dscore := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ CASE WHEN dz.y2 = 8 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cml (%,%) -< (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
		END IF;
		-- capturing right
		IF x < 8 AND boardside[x+1][y+1] = NOT side THEN
			dz.x2 := dz.x1 + 1;
			dz.y2 := dz.y1 + 1;
--			RAISE DEBUG '[%] % @ (%,%) captures % @ (%,%) on the right',procname,
--				(g).board[x][y],x,y,
--				(g).board[dz.x2][dz.y2],dz.x2,dz.y2;
			m.dscore := 
				score_of_chess_square((g).board[dz.x2][dz.y2])
				+ CASE WHEN dz.y2 = 8 THEN 9 ELSE 0 END;
			m.mine := dz;
			RETURN NEXT m;
--			RAISE DEBUG E'[%] cmr (%,%) -< (%,%)\t[score %]',procname,dz.x1,dz.y1,dz.x2,dz.y2,m.dscore;
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
-- This function produces the set of prevalid moves starting from
-- configuration v_g, assuming that side "side" is about to move.
DECLARE
	procname text := 'pvm';
	x chessint;
	y chessint;
--	dx int;
--	dy int;
--	z int;
--	m gamemove;
--	n int;
	boardside boolean[] := array_fill(NULL::boolean,ARRAY[8,8]);
--	v_turn int;
--	t0     timestamp;
--	t1     timestamp;
BEGIN
--	t1 := clock_timestamp();
--	t0 := t1;
--	z := COALESCE(array_upper((v_g).moves,1),0);
--	IF z < 3 THEN
--		RAISE DEBUG '[%] BEGIN #%',procname,z;
--	END IF;
--	RAISE DEBUG '[%] (1) compiling boardside[] dt = %',procname,
--		clock_timestamp() - t1;
--	t1 := clock_timestamp();
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		boardside[x][y] := side_of_chess_square(v_g.board[x][y]);
	END LOOP;
	END LOOP;
--	RAISE DEBUG '[%] (2) scanning all the pieces dt = %',procname,
--		clock_timestamp() - t1;
--	t1 := clock_timestamp();
	FOR x IN 1 .. 8 LOOP
	FOR y IN 1 .. 8 LOOP
		IF boardside[x][y] = side THEN
--			RAISE DEBUG '[%] considering (%,%) = %',procname
--				,x,y,(v_g).board[x][y];
			RETURN QUERY
				SELECT *
				FROM chesspiece_moves(v_g,x,y,side,boardside);
		END IF;
	END LOOP;
	END LOOP;
--	IF z < 3 THEN
--		RAISE DEBUG '[%] END dt = %, dt0 = %',procname,clock_timestamp() - t1,clock_timestamp() - t0 ;
--	END IF;
END;
$BODY$;

CREATE FUNCTION valid_moves (
	v_g	gamestate
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
-- This function produces the set of valid moves starting from
-- configuration v_g. This is obtained by (a) taking all the prevalid
-- moves, (b) endowing each prevalid move with the list of possible
-- "answers", and finally (c) using the information in (b) to select
-- only those moves that do not leave the King under attack.
DECLARE
	procname text := 'vm';
	side	boolean;
	rec	record;
	g1	gamestate;
	m1	gamemove;
BEGIN
	-- (*) Whose side is playing now?
	IF COALESCE(array_upper((v_g).moves,1),0) % 2 = 0 THEN
		side := true;
	ELSE
		side := false;
	END IF;
	-- FIXME: the list of prevalid moves should already be stored
	-- in v_g.next_moves, as they have been already computed to
	-- ensure that v_g was a legitimate status. However we have to
	-- allow for the case when they aren't there, which can happen
	-- at the very start of the game, i.e. when v_g has not been
	-- obtained by applying a move to a previous
	-- state. Alternatively we could have a separate function
	-- "compute_prevalid_moves" to be invoked from within
	-- starting_gamestate(), and skip this check, which on second
	-- thought seems like a better strategy.
	-- (a)
	IF v_g.next_moves IS NULL THEN
		RAISE DEBUG '[%] (1) computing next_moves',procname;
		SELECT array_agg(m.*)
			INTO v_g.next_moves
			FROM prevalid_moves(v_g,side) m;
	END IF;
	-- (b)
	RAISE DEBUG '[%] (2) validating the % next_moves',procname,array_upper((v_g).next_moves,1);
	FOR i IN 1 .. array_upper((v_g).next_moves,1) LOOP
		m1 := (v_g).next_moves[i];
		g1 := apply_move(v_g,m1);
		SELECT array_agg(m.*)
			INTO g1.next_moves
			FROM prevalid_moves(g1,NOT side) m;
		IF is_king_under_attack(g1,side) THEN
			RAISE DEBUG '[%] discarding move #% = % (% answers) since it leaves the King under attack',procname,
				i,m1,array_upper(g1.next_moves,1);
		ELSE
			RAISE DEBUG '[%] validating move #% = % (% answers)',procname,
				i,m1,array_upper(g1.next_moves,1);
			RETURN NEXT m1;
		END IF;
	END LOOP;
--	RETURN QUERY
--		SELECT m1.*
--		FROM prevalid_moves(v_g,side) m1
--		WHERE NOT is_king_under_attack(apply_move(v_g,m1.*));
END;
$BODY$;

CREATE FUNCTION apply_move(
	v_g gamestate
,	v_m gamemove
) RETURNS gamestate
LANGUAGE plpgsql
AS $BODY$
DECLARE
	procname text := 'am';
	this_side boolean;
BEGIN
	this_side := side_of_chess_square(v_g.board[(v_m).mine.x1][(v_m).mine.y1]);
	RAISE DEBUG '[%] BEGIN %',procname,clock_timestamp();
	RAISE DEBUG '[%] #% % : % (%,%) -> (%,%)',procname,
		COALESCE(array_upper((v_g).moves,1),0),
		v_g.board[(v_m).mine.x1][(v_m).mine.y1],
		(v_m).dscore,(v_m).mine.x1,(v_m).mine.y1,(v_m).mine.x2,(v_m).mine.y2;
	-- (1) apply the move
	v_g.board[(v_m).mine.x2][(v_m).mine.y2] := (v_g).board[(v_m).mine.x1][(v_m).mine.y1];
	-- (2) promote Pawns to Queens
	IF v_g.board[(v_m).mine.x2][(v_m).mine.y2] = 'Black Pawn' AND (v_m).mine.y2 = 1 THEN
		v_g.board[(v_m).mine.x2][(v_m).mine.y2] := 'Black Queen';
	END IF;
	IF v_g.board[(v_m).mine.x2][(v_m).mine.y2] = 'White Pawn' AND (v_m).mine.y2 = 8 THEN
		v_g.board[(v_m).mine.x2][(v_m).mine.y2] := 'White Queen';
	END IF;
--?	-- (3) refresh the under_attack grid, for the convenience of
--?	-- the next player
--?	FOR x IN 1 .. 8 LOOP
--?	FOR y IN 1 .. 8 LOOP
--?		IF side_of_chess_square(v_g.board[x][y]) = this_side THEN
--?			RAISE DEBUG '[%] % @ (%,%) is now attacking',
--?				v_g.board[x][y],x,y;
--?			
--?		END IF;
--?	END LOOP;
--?	END LOOP;
	-- (4) empty the old position
	v_g.board[(v_m).mine.x1][(v_m).mine.y1] := 'empty';
	-- (5) remember the move
	v_g.moves := v_g.moves || v_m;
	RAISE DEBUG '[%] => %',procname,display(v_g);
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

CREATE FUNCTION ui_parse_user_move (
	x text
) RETURNS boolean
LANGUAGE plpgsql AS $BODY$
DECLARE
	procname	text := 'upum';
	a		text[];
	m		gamemove;
BEGIN
	RAISE NOTICE '[%] (1) reset available moves',procname;
	a := regexp_matches(x,'^([a-h])([1-8])([PRBNQK])([a-h])([1-8])$');
	IF a IS NULL THEN
		RAISE EXCEPTION 'syntax error in move "%"',x;
	END IF;
	m.mine := ROW(CAST(translate(a[1],'abcdefgh','12345678') AS int)
		  ,   a[2]
		  ,   CAST(translate(a[4],'abcdefgh','12345678') AS int)
		  ,   a[5]);
	TRUNCATE my_moves;
	INSERT INTO my_moves(current_game,this_move,move_level,score)
		SELECT	a.game
		,	m
		,	0
		,	(a.game).score
		FROM (
		SELECT game
		FROM my_games) a;
	TRUNCATE my_games;
	INSERT INTO my_games(game)
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
