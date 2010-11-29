CREATE TEMPORARY TABLE my_games (
	t timestamp DEFAULT current_timestamp
,	id SERIAL PRIMARY KEY
,	game gamestate NOT NULL
);

CREATE TEMPORARY TABLE my_moves (
	id SERIAL PRIMARY KEY
,	parent int -- REFERENCES my_moves(id)
,	move_level int DEFAULT 0
,	current_game gamestate NOT NULL
,	this_move gamemove NOT NULL
,	score float NOT NULL
);

CREATE TEMPORARY VIEW view_my_moves AS
SELECT display(current_game),id,parent,move_level,this_move,score FROM my_moves
ORDER BY score DESC;

CREATE TEMPORARY VIEW view_my_games AS
SELECT display(game),t,id,(game).moves FROM my_games
ORDER BY array_upper((game).moves,1) DESC NULLS LAST;

CREATE FUNCTION ui_reset()
RETURNS VOID
LANGUAGE plpgsql AS $BODY$
BEGIN
	TRUNCATE my_games;
	TRUNCATE my_moves;
	INSERT INTO my_games(game)
	SELECT CAST (ROW(a.*) AS gamestate) FROM starting_gamestate() a;
END;
$BODY$;

CREATE FUNCTION ui_display()
RETURNS SETOF text
LANGUAGE plpgsql AS $BODY$
BEGIN
	/*
	RETURN NEXT '
















';
	*/
	RETURN QUERY SELECT count(1) || ' my_moves' FROM my_moves;
	RETURN QUERY SELECT count(1) || ' my_games' FROM my_games;
	RETURN QUERY
		SELECT display(game) --,t,id,(game).moves
		FROM my_games
		ORDER BY t DESC
		LIMIT 1;
END;
$BODY$;

CREATE FUNCTION ui_apply_best_move()
RETURNS boolean
LANGUAGE plpgsql AS $BODY$
DECLARE
	v_game gamestate;
BEGIN
	TRUNCATE my_games;
	INSERT INTO my_games(game)
	SELECT apply_move(current_game, this_move)
	FROM (SELECT * FROM my_moves
	WHERE parent IS NULL
	ORDER BY score DESC
	LIMIT 1) x;
	RETURN FOUND;
END;
$BODY$;

CREATE FUNCTION ui_think_best_move(
	v_level int
) RETURNS boolean
LANGUAGE plpgsql AS $BODY$
DECLARE
	procname text := 'ui_think_best_move';
	v_x real;
	v_l int;
	v_i int;
	v_j int;
	v_n int;
	v_id int;
	v_m my_moves;
	v_g gamestate;
	v_t text;
	v_coeff int;
	t1 timestamp;
BEGIN
	t1 := clock_timestamp();
	RAISE NOTICE '[%] BEGIN', procname;
	v_coeff := CASE WHEN COALESCE(array_upper((v_g).moves,1),0) % 2 = 0 THEN 1 ELSE -1 END;
	-- (0) is the game settled?
	SELECT (game).score INTO STRICT v_x FROM my_games;
	IF v_x = 'Infinity' THEN
		RAISE EXCEPTION 'The game is settled: true wins';
	ELSIF v_x = '-Infinity' THEN
		RAISE EXCEPTION 'The game is settled: false wins';
	ELSE
		RAISE DEBUG '[%] The game is not yet settled, keep playing',procname;
	END IF;
	RAISE NOTICE '[%] (1) reset available moves',procname;
	TRUNCATE my_moves;
	RAISE NOTICE '[%] (2) insert all the possible next moves',procname;
	INSERT INTO my_moves(current_game,this_move,move_level,score)
		SELECT	a.game
		,	a.move
		,	0
		,	(a.game).score + (a.move).dscore
		FROM (
		SELECT game, valid_moves(game) as move
		FROM my_games) a;
	RAISE NOTICE '[%] (3) compute subsequent moves, up to level v_level',procname;
	FOR v_l IN 1 .. v_level LOOP
		RAISE NOTICE '[%] (3.1) level %',procname,v_l;
		v_j := 1;
		v_n := 0;
		FOR v_m IN
			SELECT * FROM my_moves
			WHERE move_level = v_l - 1
		LOOP
			RAISE DEBUG '[%] looping over v_m: %',procname,v_m;
			v_g := apply_move(v_m.current_game,v_m.this_move);
			INSERT INTO my_moves(move_level,parent,current_game,this_move,score)
				SELECT	a.move_level
				,	a.parent
				,	a.current_game
				,	a.this_move
				,	(a).current_game.score + (a.this_move).dscore
				FROM (
					SELECT	v_l AS move_level
					,	v_m.id AS parent
					,	v_g AS current_game
					,	valid_moves(v_g) as this_move
				) a;
			GET DIAGNOSTICS v_i = ROW_COUNT;
			v_n := v_n + v_i;
			RAISE NOTICE '[%] move % @ L% => % moves @ L%',procname,v_j,v_l,v_i,v_l+1;
--			-- DEBUG block
--			DECLARE
--				v_r RECORD;
--			BEGIN
--				FOR v_r IN
--					SELECT this_move FROM my_moves
--					WHERE parent = v_m.id
--				LOOP
--					RAISE DEBUG '[%]  move %',procname,v_r;
--				END LOOP;
--			END;
--			-- END
/*
			RAISE NOTICE 'game %, move %'
			,	CAST(v_m.id AS text)
			,	CAST(v_m.this_move AS text);
*/
			v_j := v_j + 1;
		END LOOP;
		RAISE NOTICE '[%] Total % moves @ %',procname,v_n,v_l;
	END LOOP;
	SELECT count(1) INTO v_j FROM my_moves;
	RAISE NOTICE '[%] Counted % moves',procname,v_j;
	RAISE DEBUG '[%] (4) choose the next move with the best score',procname;
	WITH RECURSIVE r AS (
		SELECT id, parent, score, id as last_move
		FROM my_moves
		WHERE parent IS NULL
	UNION ALL
		SELECT m.id, m.parent, m.score, r.last_move
		FROM my_moves m, r
		WHERE m.id = r.parent
	)
	SELECT	last_move
	,	v_coeff * min(score + 0.01*random())
	INTO v_id, v_x
	FROM r
	GROUP BY last_move
	ORDER BY 2 DESC
	LIMIT 1;
	IF NOT FOUND THEN
		RAISE NOTICE '[%] Stale',procname;
		RETURN false;
	END IF;
	RAISE DEBUG '[%] Move % seems to be the best one with a score of %',procname,v_id,v_x;
	RAISE DEBUG '[%] (5) clean up my_moves',procname;
	SELECT m.* INTO STRICT v_m
	FROM my_moves m WHERE id = v_id;
	TRUNCATE my_moves;
	INSERT INTO my_moves SELECT v_m.*;
	RAISE NOTICE '[%] END: dt = %',procname, clock_timestamp() - t1;
	RETURN true;
END;
$BODY$;

/* The another_move function has two arguments. If the first argument
   is 1, then the next move will have 2 as the next argument. If the
   first argument has zero, then the next argument will be */

CREATE OR REPLACE FUNCTION another_move( int , int ) RETURNS text
LANGUAGE SQL AS $BODY$ SELECT 
CASE WHEN $1 = 0 THEN $code$
----------------------------------------
-- if $1 = 0
----------------------------------------
SELECT ui_display();
\prompt 'Your next move? ' my_next_move
\o varfile$code$
	|| CAST($1 AS text)
	|| $code$.sql
SELECT CASE WHEN ui_parse_user_move(:'my_next_move')
	THEN another_move($code$
	|| CAST(3 - $1 AS text)
	|| $code$,$code$
	|| CAST($2 AS text)
	|| $code$)
	ELSE '' END;
\o
\i varfile$code$ || CAST($1 AS text) || $code$.sql
----------------------------------------
$code$ ELSE $code$
----------------------------------------
-- if $1 > 0
----------------------------------------
SELECT ui_display();
\qecho BEGIN waiting...
SELECT pg_sleep(1);
\qecho END waiting...
\o varfile$code$
	|| CAST($1 AS text)
	|| $code$.sql
SELECT CASE WHEN ui_think_best_move($code$
	|| CAST($2 AS text)
	|| $code$)
       	    AND  ui_apply_best_move()
	THEN another_move($code$
	|| CAST(3 - $1 AS text)
	|| $code$,$code$
	|| CAST($2 AS text)
	|| $code$)
	ELSE '' END;
\o
\i varfile$code$ || CAST($1 AS text) || $code$.sql
$code$
----------------------------------------
END $BODY$;
