SET search_path = pg2podg, public;

WITH c AS (
SELECT a.funcid
,      a.schemaname
,      a.funcname
,      a.calls - b.calls AS calls
,      (a.total_time - b.total_time) :: double precision
       AS total_ms
,      (a.self_time - b.self_time) :: double precision
       AS self_ms
,      CASE WHEN a.calls != b.calls
       	    THEN 1000 * (a.self_time - b.self_time) 
	    	 / (a.calls - b.calls) :: double precision
       END AS each_self_us
FROM pg_stat_user_functions a
JOIN function_stats b
ON a.funcid = b.funcid
AND a.schemaname = b.schemaname
AND a.funcname = b.funcname
)
SELECT funcid
,      schemaname
,      funcname
,      calls
,      to_char(total_ms, '99999.999') AS "total ms"
,      to_char(self_ms, '99999.999') AS "self ms"
,      to_char(each_self_us, '99999.999') AS "each self us"
FROM c
ORDER BY self_ms DESC, each_self_us;
