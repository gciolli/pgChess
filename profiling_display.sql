\echo ------------------------------------------------------------
\echo -- Displaying statistics for  the chess user functions
\echo ------------------------------------------------------------

\echo
\echo ------------------------------------------------------------
\echo -- order by total_ms
SELECT	schemaname || '.' || funcname as func
,	calls
,	self_time	AS total_ms
,	round(1.0 * self_time / calls, 3)	AS avg_ms
FROM pg_stat_user_functions
WHERE schemaname = 'chess' AND calls > 0
ORDER BY 3;

\echo
\echo ------------------------------------------------------------
\echo -- order by avg_ms
SELECT	schemaname || '.' || funcname as func
,	calls
,	self_time	AS total_ms
,	round(1.0 * self_time / calls, 3)	AS avg_ms
FROM pg_stat_user_functions
WHERE schemaname = 'chess' AND calls > 0
ORDER BY 4;
