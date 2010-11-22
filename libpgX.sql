DROP SCHEMA IF EXISTS X CASCADE;
CREATE SCHEMA X;
SET search_path = X, public;

------------------------------------------------------------
-- (*) custom data types
------------------------------------------------------------

CREATE TYPE gamemove AS (
	dscore	real
);

CREATE TYPE gamestate AS (
	score	real
,	moves	gamemove[]
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
	RETURN v_g;
END
$BODY$;

CREATE FUNCTION valid_moves (
	v_g	gamestate
) RETURNS SETOF gamemove
LANGUAGE plpgsql AS $BODY$
BEGIN
	NULL;	
END;
$BODY$;

CREATE FUNCTION apply_move(
	v_g gamestate
,	v_m gamemove
) RETURNS gamestate
LANGUAGE plpgsql
AS $BODY$
BEGIN
	RETURN v_g;
END;
$BODY$;

CREATE FUNCTION display (
	v_g gamestate
) RETURNS text
LANGUAGE plpgsql AS $BODY$
BEGIN
	RETURN '';
END;
$BODY$;

------------------------------------------------------------
-- (*) generic pg2podg library
------------------------------------------------------------

\i libpg2podg.sql
