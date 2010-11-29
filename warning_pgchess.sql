--SET work_mem = 64;
--SET temp_buffers = 100;
SET synchronous_commit = off;
SET client_min_messages = WARNING;

\i libpgchess.sql

------------------------------------------------------------

\pset format unaligned
\pset tuples_only on
\set VERBOSITY terse

\qecho
\qecho ------------------------------------------------------------
\qecho -- (*) starting a new game
\qecho ------------------------------------------------------------
\qecho

SELECT ui_reset();

\o varfile1.sql
SELECT another_move(1,1);
\o
\i varfile1.sql
