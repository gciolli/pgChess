\set move_depth 4

\i libpgttt.sql

\set VERBOSITY terse

SELECT ui_reset();

SELECT ui_think_best_move(:move_depth);
SELECT ui_apply_best_move();

SELECT ui_think_best_move(:move_depth);
SELECT ui_apply_best_move();

SELECT ui_think_best_move(:move_depth);
SELECT ui_apply_best_move();

SELECT ui_think_best_move(:move_depth);
SELECT ui_apply_best_move();

SELECT * FROM view_my_games;

BEGIN;
SET client_min_messages = DEBUG;
SELECT ui_think_best_move(:move_depth);
