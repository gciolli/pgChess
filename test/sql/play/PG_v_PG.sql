\pset format unaligned
\pset tuples_only t
\o var-play-1.sql
SELECT * FROM ui_multi_loop
( side := 1
, iter := 1000
, depth_target := 2
);
\o
\i var-play-1.sql
