\set ON_ERROR_STOP
\set pg2podg_iterations 1
\set pg2podg_depth_target 1

--\pset tuples_only t

CREATE EXTENSION pgchess;
CREATE EXTENSION pg2podg;

TRUNCATE games;

--
-- The Pawn
--

CALL load_game('k7/8/8/3p4/4P3/8/8/7K w - - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);

--
-- The Knight
--

CALL load_game('k7/8/8/3p4/5N2/8/8/7K w - - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);

--
-- The Bishop
--

CALL load_game('k7/8/8/2p5/8/4B3/8/7K w - - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);

--
-- The Rook
--

CALL load_game('k7/8/8/3p4/8/3R4/8/7K w - - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);

--
-- The Queen
--

CALL load_game('k7/8/8/2p5/8/8/2Q5/7K w - - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);

--
-- Checkmate
--

CALL load_game('1k6/8/1K6/8/8/8/8/7R w - - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);

--
-- Castling
--

CALL load_game('8/8/8/8/8/4k3/7P/4K2R w K - 0 2');
CALL ui_loop(depth_target := 1, time_target := NULL , regress := true);
