\set ON_ERROR_STOP

\echo depth: :pg2podg_depth_target
\echo starting from :'my_game'

TRUNCATE status;

--
-- simplified CTE version of "INSERT IF NOT ALREADY THERE"
--

WITH new_game(fen) AS (
  ---------------------
  VALUES (:'my_game')
  ---------------------
), already_into_games (id, game, fen) AS (
  ----------------------------------------
  SELECT g.id, g.game, n.fen
  FROM games g, new_game n
  WHERE %% g.game = n.fen
  ----------------------------------------
), inserted_into_games (id, game) AS (
  ------------------------------------
  INSERT INTO games(game)
  SELECT %% n.fen
  FROM new_game n
  LEFT JOIN already_into_games a ON n.fen = a.fen
  WHERE a.fen IS NULL
  RETURNING id, game
  ------------------------------------
), full_new_game(id, game) AS (
  -----------------------------
  SELECT id, game
  FROM inserted_into_games
UNION ALL
  SELECT id, game
  FROM already_into_games
  -----------------------------
)
INSERT INTO status
SELECT id, game
FROM full_new_game;

\pset tuples_only t

SELECT ui_loop
  ( iter := :pg2podg_iterations
  , depth_target := :pg2podg_depth_target
  , time_target := NULL
  , regress := true
  );
