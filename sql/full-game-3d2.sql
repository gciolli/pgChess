TRUNCATE games;

--
-- Full game, 3 moves, depth 2
--

CALL load_game('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w QKqk - 0 1');
CALL ui_loop(iter := 3, depth_target := 2, time_target := NULL , regress := true);
