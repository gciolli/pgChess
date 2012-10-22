SET search_path = pg2podg, public;
DROP TABLE IF EXISTS function_stats;
CREATE TABLE function_stats AS
SELECT funcid, schemaname, funcname, calls, total_time, self_time
FROM pg_stat_user_functions s
WHERE schemaname IN ('public','pg2podg');

