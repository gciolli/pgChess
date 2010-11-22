DROP SCHEMA IF EXISTS tictactoe CASCADE;
CREATE SCHEMA tictactoe;
SET search_path = tictactoe, public;

------------------------------------------------------------
-- (*) custom data types
------------------------------------------------------------

CREATE TYPE gamemove AS (
	dscore	real
,	x	int
,	y	int
);

CREATE TYPE gamestate AS (
	score	real
,	moves	gamemove[]
,	cells	boolean[]
);

------------------------------------------------------------
-- (*) Implementing games and moves
------------------------------------------------------------

CREATE FUNCTION starting_gamestate()
RETURNS gamestate LANGUAGE plpgsql AS $BODY$
DECLARE
	v_g	gamestate;
BEGIN
	v_g.score = 0;
	v_g.moves = CAST(ARRAY[] as gamemove[]);
	v_g.cells := array_fill(NULL::boolean,ARRAY[3,3]);
	RETURN v_g;
END
$BODY$;

CREATE FUNCTION examine_line (boolean,boolean,boolean)
RETURNS real LANGUAGE plpgsql AS $BODY$
DECLARE
	x real;
BEGIN
	x := CASE
		-- three trues => 1
		WHEN $1 AND $2 AND $3
		THEN 'Infinity'::real
		-- three falses => -1
		WHEN NOT $1 AND NOT $2 AND NOT $3
		THEN '-Infinity'::real
		-- anything else => 0
		ELSE 0
	END;
	RAISE DEBUG 'examine_line: %,%,% ==> %',$1,$2,$3,x;
	RETURN x;
END;
$BODY$;

CREATE FUNCTION valid_moves (
	g	gamestate
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
DECLARE
	x int;
	y int;
	m gamemove;
	g1 gamestate;
	side boolean;
BEGIN
	IF COALESCE(array_upper((g).moves,1),0) % 2 = 0 THEN
		side := true;
	ELSE
		side := false;
	END IF;
	RAISE DEBUG 'side = %', side;
	FOR x IN 1 .. 3 LOOP
	FOR y IN 1 .. 3 LOOP
		IF g.cells[x][y] IS NULL THEN
			-- The move is allowed, therefore we have to
			-- compute its score.
			m.x := x;
			m.y := y;
			g1 := apply_move(g,m);
			m.dscore := g1.score - g.score;
			RAISE DEBUG 'returning valid move %',m;
			RETURN NEXT m;
		END IF;
	END LOOP;
	END LOOP;
END;
$BODY$;

CREATE FUNCTION apply_move(
	g gamestate
,	m gamemove
) RETURNS gamestate
LANGUAGE plpgsql
AS $BODY$
DECLARE
	side boolean;
BEGIN
	IF COALESCE(array_upper((g).moves,1),0) % 2 = 0 THEN
		side := true;
	ELSE
		side := false;
	END IF;
	RAISE DEBUG 'applying move % (side = %)',m,side;
	g.cells[m.x][m.y] := side;
	g.moves := g.moves || m;
	SELECT
	CASE WHEN side
		THEN max(examine_line(
			g.cells[x1][y1]
		,	g.cells[x2][y2]
		,	g.cells[x3][y3]))
		ELSE min(examine_line(
			g.cells[x1][y1]
		,	g.cells[x2][y2]
		,	g.cells[x3][y3]))
	END INTO g.score
	FROM (VALUES
		(1,1,1,2,1,3)
	,	(2,1,2,2,2,3)
	,	(3,1,3,2,3,3)
	,	(1,1,2,1,3,1)
	,	(1,2,2,2,3,2)
	,	(1,3,2,3,3,3)
	,	(1,1,2,2,3,3)
	,	(1,3,2,2,3,1)
	) t(x1,y1,x2,y2,x3,y3);
	RAISE DEBUG 'resulting score is %',g.score;
	RETURN g;
END;
$BODY$;

CREATE FUNCTION display (
	v_g gamestate
) RETURNS text
LANGUAGE plpgsql AS $BODY$
DECLARE
	x int;
	y int;
	t text := '';
BEGIN
	FOR x IN 1 .. 3 LOOP
	FOR y IN 1 .. 3 LOOP
		t := t || ' ' || CASE
			WHEN v_g.cells[x][y] = true THEN 't'
			WHEN v_g.cells[x][y] = false THEN 'f'
			ELSE '.'
			END;
	END LOOP;
	t := t || E'\n';
	END LOOP;
	RETURN t;
END;
$BODY$;

------------------------------------------------------------
-- (*) generic pg2podg library
------------------------------------------------------------

\i libpg2podg.sql
