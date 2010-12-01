SET search_path = chess, public;

------------------------------------------------------------

\pset format unaligned
\pset tuples_only on
\set VERBOSITY terse

\o varfile1.sql
SELECT another_move(1,1);
\o
\i varfile1.sql
