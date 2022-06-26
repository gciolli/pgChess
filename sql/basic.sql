\set ON_ERROR_STOP
\set pg2podg_iterations 1
\set pg2podg_depth_target 1

--\pset tuples_only t

CREATE EXTENSION pgchess;
CREATE EXTENSION pg2podg;

TRUNCATE status, games;

--
-- 1. Castling
--

CALL load_game('8/8/8/8/8/4k3/7P/4K2R w K - 0 2');

CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);
