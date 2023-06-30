TRUNCATE games;

--
-- Full game, 10 moves, depth 1
--

CALL load_game('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w QKqk - 0 1');
CALL ui_loop(iter := 10, depth_target := 1, time_target := NULL , regress := true);
